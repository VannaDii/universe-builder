import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'journal.dart';
import 'initialization_policy.dart';
import 'revision_input.dart';

export 'package:ub_domain/ub_domain.dart' show InitializationReceipt;

/// The internal admission gate. This does not authorize publication or infer a
/// start, ancestry, clock, value or source revision from names or prose.
final class InitializationEvidence {
  InitializationEvidence(this.journal);
  final SqliteJournal journal;

  List<InitializationReceipt> pending(
    CommitInput input,
    Membership base,
    Membership candidate,
  ) {
    if (input.universe != journal.universe) {
      throw const FormatException('Initialization universe mismatch');
    }
    return pendingInitializationRecords(
      input: input,
      base: base,
      candidate: candidate,
      load: journal.load,
      priorAssertions: (record) => [
        for (final row in journal.database.select(
          'SELECT r.assertion_version FROM initialization_receipt r JOIN record_versions v ON v.universe_id=r.universe_id AND v.id=r.assertion_version WHERE r.universe_id=? AND v.record_id=?',
          [input.universe.value, record.value],
        ))
          RecordVersionId.parse(row['assertion_version'] as String),
      ],
      initialized: (instance, property) =>
          journal.database.select(
            'SELECT EXISTS(SELECT 1 FROM initialization_receipt WHERE universe_id=? AND instance_id=? AND predicate_id=?) AS present',
            [input.universe.value, instance.value, property.value],
          ).single['present'] ==
          1,
    );
  }

  void insert(InitializationReceipt receipt) {
    if (journal.database.autocommit) {
      throw StateError('Initialization receipts require an owned transaction');
    }
    journal.database.execute(
      'INSERT INTO initialization_receipt VALUES(?,?,?,?,?,?,?,?)',
      [
        journal.universe.value,
        receipt.instance.value,
        receipt.start.value,
        receipt.property.value,
        receipt.definition.value,
        receipt.assertion.value,
        receipt.revision.value,
        receipt.sourceRevision.value,
      ],
    );
  }

  List<InitializationReceipt> read() => List.unmodifiable([
    for (final row in journal.database.select(
      'SELECT instance_id,start_event_id,predicate_id,initial_definition_version,assertion_version,revision_id,source_revision FROM initialization_receipt WHERE universe_id=? ORDER BY instance_id,predicate_id,start_event_id',
      [journal.universe.value],
    ))
      InitializationReceipt(
        instance: RecordId.parse(row['instance_id'] as String),
        start: RecordId.parse(row['start_event_id'] as String),
        property: RecordId.parse(row['predicate_id'] as String),
        definition: RecordVersionId.parse(
          row['initial_definition_version'] as String,
        ),
        assertion: RecordVersionId.parse(row['assertion_version'] as String),
        revision: RevisionId.parse(row['revision_id'] as String),
        sourceRevision: RevisionId.parse(row['source_revision'] as String),
      ),
  ]);

  /// Includes fork ancestry while excluding receipts from later or sibling
  /// revisions. Snapshot resolution first verifies the requested binding.
  List<InitializationReceipt> readAt(
    ContinuityId continuity,
    RevisionId revision,
  ) {
    journal.snapshot(continuity, revision);
    final reachable = <String>{};
    String? next = revision.value;
    while (next != null) {
      if (!reachable.add(next) || reachable.length > maxChain) {
        throw const FormatException('Initialization history budget exceeded');
      }
      final row = journal.database.select(
        'SELECT parent_id,continuity_id FROM commits WHERE universe_id=? AND id=?',
        [journal.universe.value, next],
      ).single;
      next = row['parent_id'] as String?;
      next ??=
          journal.database.select(
                'SELECT baseline_commit FROM continuities WHERE universe_id=? AND id=?',
                [journal.universe.value, row['continuity_id'] as String],
              ).single['baseline_commit']
              as String?;
    }
    return List.unmodifiable(
      read().where((r) => reachable.contains(r.revision.value)),
    );
  }

  /// Recovery checks receipt history against original admissions. A reviewed
  /// restoration retains the original receipt rather than creating a refill.
  void verify() {
    final actual = read();
    final expected = <InitializationReceipt>[];
    final changes = journal.database.select(
      "SELECT ch.version_id,ch.revision_id,co.continuity_id,co.parent_id FROM commit_changes ch JOIN commits co ON co.universe_id=ch.universe_id AND co.id=ch.revision_id JOIN record_versions v ON v.universe_id=ch.universe_id AND v.id=ch.version_id WHERE v.kind='assertion' AND ch.universe_id=? AND ch.prior_version IS NULL AND ch.version_id IS NOT NULL ORDER BY ch.revision_id,ch.record_id",
      [journal.universe.value],
    );
    var changeIndex = 0;
    for (final record in journal.loadMany(
      changes.map((row) => RecordVersionId.parse(row['version_id'] as String)),
    )) {
      final row = changes[changeIndex++];
      final a = objectFields(record.payload);
      final provenance = initializationProvenance(a['basis']!);
      if (provenance == null) continue;
      final (start, definition, sourceRevision) = provenance;
      final restored = actual.any((r) {
        if (r.assertion == record.versionId) return false;
        final original = journal.load(r.assertion);
        return original.identity.recordId == record.identity.recordId &&
            original.identity.recordKind == RecordKind.assertion &&
            initializationProvenance(
                  objectFields(original.payload)['basis']!,
                ) ==
                provenance;
      });
      if (restored) continue;
      if (row['parent_id'] != sourceRevision.value) {
        throw const FormatException(
          'Initialization source revision differs from admitting parent',
        );
      }
      final revision = RevisionId.parse(row['revision_id'] as String);
      final membership = journal.snapshot(
        ContinuityId.parse(row['continuity_id'] as String),
        revision,
      );
      final version =
          membership[RecordRef.fromCanonical(a['proposition']!).record];
      if (version == null) {
        throw const FormatException('Initial receipt proposition absent');
      }
      final proposition = journal.load(version);
      if (proposition.identity.recordKind != RecordKind.proposition) {
        throw const FormatException('Receipt proposition has wrong kind');
      }
      final p = objectFields(proposition.payload);
      expected.add(
        InitializationReceipt(
          instance: RecordRef.fromCanonical(p['subject']!).record,
          start: start.record,
          property: RecordRef.fromCanonical(p['predicate']!).record,
          definition: definition.version,
          assertion: record.versionId,
          revision: revision,
          sourceRevision: sourceRevision,
        ),
      );
    }
    expected.sort((a, b) {
      final instance = a.instance.value.compareTo(b.instance.value);
      if (instance != 0) return instance;
      final property = a.property.value.compareTo(b.property.value);
      return property != 0 ? property : a.start.value.compareTo(b.start.value);
    });
    if (expected.length != actual.length ||
        Iterable<int>.generate(expected.length)
            .any((i) => expected[i] != actual[i])) {
      throw const FormatException('Initialization receipt history mismatch');
    }
  }
}
