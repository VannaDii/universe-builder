import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'journal.dart';
import 'revision_input.dart';

/// Domain evidence, admitted atomically with the original instance fact.
final class InitializationReceipt {
  const InitializationReceipt({
    required this.instance,
    required this.start,
    required this.property,
    required this.definition,
    required this.assertion,
    required this.revision,
    required this.sourceRevision,
  });
  final RecordId instance, start, property;
  final RecordVersionId definition, assertion;
  final RevisionId revision, sourceRevision;
  InitializationReceipt admittedAt(RevisionId revision) =>
      InitializationReceipt(
        instance: instance,
        start: start,
        property: property,
        definition: definition,
        assertion: assertion,
        revision: revision,
        sourceRevision: sourceRevision,
      );
  @override
  bool operator ==(Object other) =>
      other is InitializationReceipt &&
      instance == other.instance &&
      start == other.start &&
      property == other.property &&
      definition == other.definition &&
      assertion == other.assertion &&
      revision == other.revision &&
      sourceRevision == other.sourceRevision;
  @override
  int get hashCode => Object.hash(
    instance,
    start,
    property,
    definition,
    assertion,
    revision,
    sourceRevision,
  );
}

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
    StoredVersion get(Membership map, RecordId id) {
      final version = map[id];
      if (version == null) {
        throw const FormatException('Initialization reference absent');
      }
      return journal.load(version);
    }

    StoredVersion pinned(VersionRef reference, Membership map) {
      if (reference.universe != input.universe) {
        throw const FormatException(
          'Initialization needs explicit local provenance',
        );
      }
      final record = get(map, reference.record);
      if (record.versionId != reference.version) {
        throw const FormatException(
          'Initialization provenance version differs',
        );
      }
      return record;
    }

    Map<String, CanonicalValue> body(StoredVersion record, RecordKind kind) {
      if (record.identity.recordKind != kind) {
        throw const FormatException('Initialization reference has wrong kind');
      }
      return objectFields(record.payload);
    }

    final receipts = <InitializationReceipt>[];
    final keys = <(RecordId, RecordId)>{};
    for (final change in input.changes) {
      final record = change.next;
      if (record == null ||
          record.identity.recordKind != RecordKind.assertion) {
        continue;
      }
      final a = objectFields(record.payload);
      final provenance = _provenance(a['basis']!);
      if (provenance == null) continue;
      final (start, definition, sourceRevision) = provenance;
      final prior = journal.database.select(
        'SELECT r.assertion_version FROM initialization_receipt r JOIN record_versions v ON v.universe_id=r.universe_id AND v.id=r.assertion_version WHERE r.universe_id=? AND v.record_id=?',
        [input.universe.value, change.recordId.value],
      );
      bool sameBasis(RecordVersionId version) {
        final old = journal.load(version);
        return old.identity.recordKind == RecordKind.assertion &&
            _provenance(objectFields(old.payload)['basis']!) == provenance;
      }

      if (prior.isNotEmpty) {
        if (sameBasis(
          RecordVersionId.parse(prior.single['assertion_version'] as String),
        )) {
          continue;
        }
        throw const FormatException(
          'Initialization provenance cannot change on historical restoration',
        );
      }
      if (change.expected != null) {
        if (!sameBasis(change.expected!)) {
          throw const FormatException(
            'Initialization provenance cannot be added or changed by correction',
          );
        }
        continue;
      }
      if (sourceRevision != input.expectedHead) {
        throw const FormatException(
          'Initialization source revision differs from review base',
        );
      }
      final source = pinned(definition, base);
      if (get(candidate, definition.record).versionId != source.versionId) {
        throw const FormatException(
          'Initial definition changed in initialization proposal',
        );
      }
      final initial = body(source, RecordKind.assertion);
      final sourceRef = RecordRef.fromCanonical(initial['proposition']!);
      final sourceProposition = get(base, sourceRef.record);
      final sourceP = body(sourceProposition, RecordKind.proposition);
      if (get(candidate, sourceRef.record).versionId !=
          sourceProposition.versionId) {
        throw const FormatException('Initial definition proposition changed');
      }
      final p = body(
        get(candidate, RecordRef.fromCanonical(a['proposition']!).record),
        RecordKind.proposition,
      );
      final event = EventRecord.fromWire(pinned(start, candidate).payload);
      final time = event.time;
      if (time is! ExactTime) {
        throw const FormatException(
          'Initialization needs an exact authored start',
        );
      }
      final subject = RecordRef.fromCanonical(p['subject']!);
      final predicate = RecordRef.fromCanonical(p['predicate']!);
      final scope = Scope.fromWire(a['scope']!);
      final validity = Validity.fromWire(a['validity']!);
      final value = p['value'];
      final sourceValue = sourceP['value'];
      final isStart =
          validity is CalendarIntervalValidity &&
          validity.calendar == time.calendar &&
          validity.start == ExactBound(time.value);
      final occurrence = event.occurrence;
      if (occurrence is! SimpleOccurrence ||
          occurrence.kind != OccurrenceKind.occurred ||
          !event.participants.any(
            (participant) => participant.record == subject,
          ) ||
          _string(a['attributeMode']!) != 'instance' ||
          _string(initial['attributeMode']!) != 'initial_value' ||
          _string(a['polarity']!) != 'support' ||
          _string(initial['polarity']!) != 'support' ||
          _string(a['precision']!) != 'exact' ||
          _string(initial['precision']!) != 'exact' ||
          !_empty(a['alternatives']) ||
          !_empty(initial['alternatives']) ||
          !_absent(a['establishedBy']) ||
          !_scopeContains(Scope.fromWire(initial['scope']!), scope) ||
          RecordRef.fromCanonical(p['context']!) !=
              RecordRef.fromCanonical(sourceP['context']!) ||
          RecordRef.fromCanonical(p['context']!) != scope.context ||
          predicate != RecordRef.fromCanonical(sourceP['predicate']!) ||
          value == null ||
          value is CanonicalNull ||
          sourceValue == null ||
          sourceValue is CanonicalNull ||
          DomainValue.fromWire(value) != DomainValue.fromWire(sourceValue) ||
          _string(p['quantification']!) != 'particular' ||
          !isStart) {
        throw const FormatException(
          'Initialization evidence disagrees with authored start or definition',
        );
      }
      body(get(candidate, predicate.record), RecordKind.property);
      final entity = body(get(candidate, subject.record), RecordKind.entity);
      if (_string(entity['classificationResolution']!) != 'resolved') {
        throw const FormatException('Initialization classification unresolved');
      }
      RecordId? next = _optionalId(entity['classification']);
      final ancestry = <RecordId>{};
      while (next != null) {
        if (!ancestry.add(next)) {
          throw const FormatException('Initialization ancestry cyclic');
        }
        final type = body(get(candidate, next), RecordKind.entityType);
        if (!(type['classificationExecutable'] as CanonicalBool).value ||
            _string(type['parentResolution']!) == 'ambiguous') {
          throw const FormatException('Initialization ancestry unresolved');
        }
        next = _optionalId(type['parent']);
      }
      if (!ancestry.contains(
        RecordRef.fromCanonical(sourceP['subject']!).record,
      )) {
        throw const FormatException(
          'Initial definition is not an instance ancestor',
        );
      }
      for (final version in base.values) {
        final prior = journal.load(version);
        if (prior.identity.recordKind != RecordKind.assertion) continue;
        final assertion = objectFields(prior.payload);
        if (_string(assertion['attributeMode']!) != 'instance') continue;
        final proposition = get(
          base,
          RecordRef.fromCanonical(assertion['proposition']!).record,
        );
        if (proposition.identity.recordKind != RecordKind.proposition) continue;
        final priorP = objectFields(proposition.payload);
        if (RecordRef.fromCanonical(priorP['subject']!) == subject &&
            RecordRef.fromCanonical(priorP['predicate']!) == predicate) {
          throw const FormatException(
            'Existing instance evidence requires resolution, not initialization',
          );
        }
      }
      final exists =
          journal.database.select(
            'SELECT EXISTS(SELECT 1 FROM initialization_receipt WHERE universe_id=? AND instance_id=? AND predicate_id=?) AS present',
            [
              input.universe.value,
              subject.record.value,
              predicate.record.value,
            ],
          ).single['present'] ==
          1;
      if (!keys.add((subject.record, predicate.record)) || exists) {
        throw const FormatException(
          'Instance property has already been initialized',
        );
      }
      receipts.add(
        InitializationReceipt(
          instance: subject.record,
          start: start.record,
          property: predicate.record,
          definition: definition.version,
          assertion: record.versionId,
          revision: input.expectedHead,
          sourceRevision: sourceRevision,
        ),
      );
    }
    return List.unmodifiable(receipts);
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
    for (final row in changes) {
      final record = journal.load(
        RecordVersionId.parse(row['version_id'] as String),
      );
      final a = objectFields(record.payload);
      final provenance = _provenance(a['basis']!);
      if (provenance == null) continue;
      final (start, definition, sourceRevision) = provenance;
      final restored = actual.any((r) {
        if (r.assertion == record.versionId) return false;
        final original = journal.load(r.assertion);
        return original.identity.recordId == record.identity.recordId &&
            original.identity.recordKind == RecordKind.assertion &&
            _provenance(objectFields(original.payload)['basis']!) == provenance;
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

(VersionRef, VersionRef, RevisionId)? _provenance(CanonicalValue basis) {
  final evidence = EvidenceBasis.fromWire(basis);
  return evidence is InstanceInitializationBasis
      ? (evidence.start, evidence.definition, evidence.sourceRevision)
      : null;
}

String _string(CanonicalValue value) => (value as CanonicalString).value;
bool _absent(CanonicalValue? value) => value == null || value is CanonicalNull;
bool _empty(CanonicalValue? value) =>
    _absent(value) || (value as CanonicalArray).items.isEmpty;
RecordId? _optionalId(CanonicalValue? value) =>
    _absent(value) ? null : RecordId.parse(_string(value!));

bool _scopeContains(Scope source, Scope target) {
  if (source.context != target.context || source.realm != target.realm) {
    return false;
  }
  final from = source.applicability;
  final to = target.applicability;
  if (from is UniverseApplicability && to is UniverseApplicability) return true;
  if (to is! WorldsApplicability || to.worldIds.isEmpty) return false;
  if (from is UniverseApplicability) return true;
  if (from is! WorldsApplicability) return false;
  final allowed = from.worldIds.toSet();
  return to.worldIds.every(allowed.contains);
}
