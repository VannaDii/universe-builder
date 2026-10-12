import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'journal.dart' show Membership;
import 'revision_input.dart';

/// Shared factual admission policy. Storage callbacks belong to the caller's
/// transaction; this policy does not grant publication rights.
List<InitializationReceipt> pendingInitializationRecords({
  required CommitInput input,
  required Membership base,
  required Membership candidate,
  required StoredVersion Function(RecordVersionId) load,
  required List<RecordVersionId> Function(RecordId) priorAssertions,
  required bool Function(RecordId, RecordId) initialized,
}) {
  StoredVersion get(Membership map, RecordId id) {
    final version = map[id];
    if (version == null) {
      throw const FormatException('Initialization reference absent');
    }
    return load(version);
  }

  StoredVersion pinned(VersionRef reference, Membership map) {
    if (reference.universe != input.universe) {
      throw const FormatException(
        'Initialization needs explicit local provenance',
      );
    }
    final record = get(map, reference.record);
    if (record.versionId != reference.version) {
      throw const FormatException('Initialization provenance version differs');
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
    if (record == null || record.identity.recordKind != RecordKind.assertion) {
      continue;
    }
    final a = objectFields(record.payload);
    final provenance = initializationProvenance(a['basis']!);
    if (provenance == null) continue;
    final (start, definition, sourceRevision) = provenance;
    final prior = priorAssertions(change.recordId);
    bool sameBasis(RecordVersionId version) {
      final old = load(version);
      return old.identity.recordKind == RecordKind.assertion &&
          initializationProvenance(objectFields(old.payload)['basis']!) ==
              provenance;
    }

    if (prior.isNotEmpty) {
      if (sameBasis(prior.single)) {
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
      final prior = load(version);
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
    final exists = initialized(subject.record, predicate.record);
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

(VersionRef, VersionRef, RevisionId)? initializationProvenance(
  CanonicalValue basis,
) {
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
