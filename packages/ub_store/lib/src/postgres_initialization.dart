import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'initialization_policy.dart';
import 'journal.dart' show Membership, maxChain;
import 'postgres_journal.dart';
import 'postgres_values.dart';
import 'revision_input.dart';

/// Initialization admission and retained provenance in the caller-owned
/// publication transaction. Installation authority and exact approval remain
/// responsibilities of the complete kernel; this gate cannot grant either.
final class PostgresInitializationEvidence {
  PostgresInitializationEvidence(this._session, this.universe)
    : _schema = postgresUniverseSchema(universe),
      _journal = PostgresJournal(_session, universe);
  final TxSession _session;
  final UniverseId universe;
  final String _schema;
  final PostgresJournal _journal;

  Future<List<InitializationReceipt>> pending(
    CommitInput input,
    Membership base,
    Membership candidate,
  ) async {
    if (input.universe != universe) {
      throw const FormatException('Initialization universe mismatch');
    }
    // Receipt absence and admission must remain coordinated until outer commit.
    await _journal.lockUniverse();
    final receipts = await read();
    final records = <RecordVersionId, StoredVersion>{};
    for (final version in {
      ...base.values,
      ...candidate.values,
      for (final change in input.changes)
        if (change.expected != null) change.expected!,
      for (final receipt in receipts) receipt.assertion,
    }) {
      records[version] = await _journal.load(version);
    }
    final prior = <RecordId, List<RecordVersionId>>{};
    final initialized = <(RecordId, RecordId)>{};
    for (final receipt in receipts) {
      final record = records[receipt.assertion]!;
      prior
          .putIfAbsent(record.identity.recordId, () => [])
          .add(receipt.assertion);
      initialized.add((receipt.instance, receipt.property));
    }
    return pendingInitializationRecords(
      input: input,
      base: base,
      candidate: candidate,
      load: (version) =>
          records[version] ??
          (throw const FormatException('Initialization version absent')),
      priorAssertions: (record) => prior[record] ?? const [],
      initialized: (instance, property) =>
          initialized.contains((instance, property)),
    );
  }

  Future<void> insert(InitializationReceipt receipt) async {
    await _journal.lockUniverse();
    await _session.execute(
      'INSERT INTO $_schema.initialization_receipt VALUES(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8)',
      parameters: [
        universe.value,
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

  Future<List<InitializationReceipt>> read() async => List.unmodifiable([
    for (final row in await _rows(
      'SELECT instance_id,start_event_id,predicate_id,initial_definition_version,assertion_version,revision_id,source_revision FROM $_schema.initialization_receipt WHERE universe_id=\$1 ORDER BY instance_id,predicate_id,start_event_id',
      [universe.value],
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

  /// Includes fork ancestry, excluding later/sibling admissions. Snapshot
  /// resolution first verifies the requested continuity/revision binding.
  Future<List<InitializationReceipt>> readAt(
    ContinuityId continuity,
    RevisionId revision,
  ) async {
    await _journal.snapshot(continuity, revision);
    final reachable = <String>{};
    String? next = revision.value;
    while (next != null) {
      if (!reachable.add(next) || reachable.length > maxChain) {
        throw const FormatException('Initialization history budget exceeded');
      }
      final row = (await _rows(
        'SELECT parent_id,continuity_id FROM $_schema.commits WHERE universe_id=\$1 AND id=\$2',
        [universe.value, next],
      )).single;
      next = row['parent_id'] as String?;
      next ??=
          (await _rows(
                'SELECT baseline_commit FROM $_schema.continuities WHERE universe_id=\$1 AND id=\$2',
                [universe.value, row['continuity_id']],
              )).single['baseline_commit']
              as String?;
    }
    return List.unmodifiable(
      (await read()).where((r) => reachable.contains(r.revision.value)),
    );
  }

  /// Recovery checks original admissions; reviewed historical restoration
  /// retains the original receipt instead of creating a refill.
  Future<void> verify() async {
    final actual = await read();
    final expected = <InitializationReceipt>[];
    final changes = await _rows(
      "SELECT ch.version_id,ch.revision_id,co.continuity_id,co.parent_id FROM $_schema.commit_changes ch JOIN $_schema.commits co ON co.universe_id=ch.universe_id AND co.id=ch.revision_id JOIN $_schema.record_versions v ON v.universe_id=ch.universe_id AND v.id=ch.version_id WHERE v.kind='assertion' AND ch.universe_id=\$1 AND ch.prior_version IS NULL AND ch.version_id IS NOT NULL ORDER BY ch.revision_id,ch.record_id",
      [universe.value],
    );
    for (final row in changes) {
      final record = await _journal.load(
        RecordVersionId.parse(row['version_id'] as String),
      );
      final a = objectFields(record.payload);
      final provenance = initializationProvenance(a['basis']!);
      if (provenance == null) continue;
      final (start, definition, sourceRevision) = provenance;
      var restored = false;
      for (final receipt in actual) {
        if (receipt.assertion == record.versionId) continue;
        final original = await _journal.load(receipt.assertion);
        if (original.identity.recordId == record.identity.recordId &&
            original.identity.recordKind == RecordKind.assertion &&
            initializationProvenance(
                  objectFields(original.payload)['basis']!,
                ) ==
                provenance) {
          restored = true;
          break;
        }
      }
      if (restored) continue;
      if (row['parent_id'] != sourceRevision.value) {
        throw const FormatException(
          'Initialization source revision differs from admitting parent',
        );
      }
      final revision = RevisionId.parse(row['revision_id'] as String);
      final membership = await _journal.snapshot(
        ContinuityId.parse(row['continuity_id'] as String),
        revision,
      );
      final version =
          membership[RecordRef.fromCanonical(a['proposition']!).record];
      if (version == null) {
        throw const FormatException('Initial receipt proposition absent');
      }
      final proposition = await _journal.load(version);
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

  Future<List<Map<String, Object?>>> _rows(
    String sql,
    List<Object?> parameters,
  ) async => [
    for (final row in await _session.execute(sql, parameters: parameters))
      row.toColumnMap(),
  ];
}
