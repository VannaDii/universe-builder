import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/ub_store.dart';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'initialize_instance', message: message);
final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
bool _sameRecord(RecordVersion a, RecordVersion b) =>
    a.toWire().toText() == b.toWire().toText();
bool? _sameValue(DomainValue? a, DomainValue? b) => a == b
    ? true
    : a == null || b == null
    ? null
    : compareValues(a, Comparator.eq, b);

/// Compiles only explicit starts into frozen changes before exact review.
/// The caller discards a failed compilation; no canonical state is written here.
void compileInitializations({
  required UniverseId universe,
  required RevisionId revision,
  required List<RecordVersion> base,
  required List<DomainOperation> operations,
  required List<Assignment> changes,
}) {
  final candidate = <RecordId, RecordVersion>{
    for (final r in base) r.identity.recordId: r,
  };
  for (final change in changes) {
    if (change.next == null) {
      candidate.remove(change.recordId);
    } else {
      candidate[change.recordId] = RecordVersion.fromWire(
        change.next!.toCanonical(),
      );
    }
  }
  final ids = candidate.keys.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final records = ids.map((id) => candidate[id]!).toList();
  RecordVersion get(RecordId id) {
    final r = candidate[id];
    if (r == null) throw _invalid('referenced record absent');
    return r;
  }

  final keys = <(RecordId, RecordId)>{},
      inputRefs = changes.map((c) => c.recordId).toSet();
  for (final op in operations) {
    if (op is! InitializeInstanceOperation) continue;
    final instance = op.instance,
        start = op.start,
        definition = op.definition,
        scope = op.scope,
        validity = op.validity;
    if (instance.universe != universe ||
        start.universe != universe ||
        definition.universe != universe ||
        scope.context.universe != universe) {
      throw _invalid('explicit local identities and context required');
    }
    if (get(instance.record).payload is! EntityRecord) {
      throw _invalid('subject is not an instance');
    }
    final chain = definitionAncestry(instance.record, records);
    if (!chain.complete) {
      throw _invalid('classification or ancestry unresolved');
    }
    final startVersion = get(start.record), event = startVersion.payload;
    if (event is! EventRecord) {
      throw _invalid('start must be an authored event');
    }
    final time = event.time;
    if (time is! ExactTime) throw _invalid('exact authored start required');
    if (event.occurrence is! SimpleOccurrence ||
        (event.occurrence as SimpleOccurrence).kind !=
            OccurrenceKind.occurred ||
        !event.participants.any((p) => p.record == instance) ||
        validity is! CalendarIntervalValidity ||
        validity.calendar != time.calendar ||
        validity.start is! ExactBound ||
        (validity.start as ExactBound).value != time.value ||
        eventApplies(validity, AtFrameTime(time), records) != true) {
      throw _invalid(
        'initial interval must include and begin at this occurred instance start',
      );
    }
    RecordVersion? source;
    for (final r in base) {
      if (r.identity.recordId == definition.record &&
          r.recordVersionId == definition.version) {
        source = r;
        break;
      }
    }
    if (source == null) {
      throw _invalid('source definition must be approved at the review base');
    }
    if (!_sameRecord(get(definition.record), source)) {
      throw _invalid('source definition changed in proposal');
    }
    final initial = source.payload;
    if (initial is! AssertionRecord) {
      throw _invalid('source must be an initial-value assertion');
    }
    RecordVersion? sourceProp;
    for (final r in base) {
      if (r.identity.recordId == initial.proposition.record) {
        sourceProp = r;
        break;
      }
    }
    if (sourceProp == null) throw _invalid('source proposition absent');
    if (!_sameRecord(get(initial.proposition.record), sourceProp)) {
      throw _invalid('source proposition changed in proposal');
    }
    final p = sourceProp.payload;
    if (p is! PropositionRecord) throw _invalid('source proposition kind');
    if (initial.attributeMode != AttributeMode.initialValue ||
        initial.polarity != Polarity.support ||
        initial.precision != Precision.exact ||
        initial.alternatives.isNotEmpty ||
        p.value == null ||
        p.roles.isNotEmpty ||
        p.context != scope.context ||
        initial.scope.context != scope.context ||
        scope.realm != null ||
        initial.scope.realm != null) {
      throw _invalid(
        'initial source value, polarity, precision or context unresolved',
      );
    }
    final property = get(p.predicate.record).payload;
    if (property is! PropertyRecord) {
      throw _invalid('initialization requires a property');
    }
    if (!keys.add((instance.record, p.predicate.record))) {
      throw _invalid('duplicate instance/property initialization');
    }
    final List<WorldId?> worlds;
    switch (scope.applicability) {
      case WorldsApplicability(:final worldIds) when worldIds.isNotEmpty:
        worlds = worldIds;
      case UniverseApplicability():
        final all = records
            .where((r) => r.payload is WorldRecord)
            .map(
              (r) => WorldId.parse(
                'wld_${r.identity.recordId.value.substring(4)}',
              ),
            )
            .toList();
        worlds = all.isEmpty ? [null] : all;
      default:
        throw _invalid('initialization jurisdiction unresolved');
    }
    for (final world in worlds) {
      if (world != null && !event.worlds.contains(world)) {
        throw _invalid('start does not establish the requested world');
      }
      final worldRecords = world == null
          ? <RecordId>[]
          : [RecordId.parse('rec_${world.value.substring(4)}')];
      if (definitionMatches(
            instance.record,
            property.subjectTypes,
            records,
            worldRecords,
          ) !=
          true) {
        throw _invalid('property applicability unresolved');
      }
      var selected = false;
      for (final row in records) {
        final a = row.payload;
        if (a is! AssertionRecord ||
            a.attributeMode != AttributeMode.initialValue) {
          continue;
        }
        final other = get(a.proposition.record).payload;
        if (other is! PropositionRecord) continue;
        if (other.predicate != p.predicate ||
            !chain.types.contains(other.subject.record) ||
            other.context != scope.context ||
            a.scope.context != scope.context) {
          continue;
        }
        final type = get(other.subject.record).payload;
        if (type is! EntityTypeRecord) continue;
        final checks = [
          worldApplies(a.scope.applicability, worldRecords),
          worldApplies(type.applicability, worldRecords),
          eventApplies(a.validity, AtFrameTime(time), records),
        ];
        if (checks.contains(false)) continue;
        if (checks.contains(null) ||
            a.scope.realm != null ||
            a.precision != Precision.exact ||
            a.alternatives.isNotEmpty ||
            other.value == null ||
            other.roles.isNotEmpty) {
          throw _invalid(
            'initial-value candidates unresolved; retain evidence for resolution',
          );
        }
        final equal = _sameValue(p.value, other.value);
        if (a.polarity == Polarity.support && equal != true ||
            a.polarity == Polarity.refutation && equal != false) {
          throw _invalid(
            'initial-value candidates conflict or are unresolved; retain evidence for resolution',
          );
        }
        selected = selected || row.recordVersionId == definition.version;
      }
      if (!selected) {
        throw _invalid('selected initial source is inapplicable to this start');
      }
    }
    RecordId propositionId;
    try {
      propositionId = RecordId.parse(op.clientRef);
    } on FormatException {
      propositionId = RecordId.generate();
    }
    if (!_nonWhitespace.hasMatch(op.clientRef) ||
        candidate.containsKey(propositionId) ||
        !inputRefs.add(propositionId)) {
      throw _invalid('initial proposition identity already used');
    }
    final assertionId = RecordId.generate();
    final assertion = AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: RecordRef(universe: universe, record: propositionId),
      polarity: Polarity.support,
      scope: scope,
      validity: validity,
      persistence: initial.persistence,
      precision: Precision.exact,
      alternatives: const [],
      basis: InstanceInitializationBasis(
        VersionRef(
          universe: universe,
          record: start.record,
          version: startVersion.recordVersionId,
        ),
        definition,
        revision,
      ),
    );
    final proposition = PropositionRecord(
      subject: instance,
      predicate: p.predicate,
      roles: p.roles,
      value: p.value,
      context: p.context,
      quantification: Quantification.particular,
    );
    for (final (id, payload) in <(RecordId, RecordPayload)>[
      (propositionId, proposition),
      (assertionId, assertion),
    ]) {
      final next = RecordVersion.build(
        recordVersionId: RecordVersionId.generate(),
        identity: RecordIdentity(
          universeId: universe,
          recordId: id,
          recordKind: payload.recordKind,
        ),
        payload: payload,
      );
      changes.add(
        Assignment(
          recordId: id,
          next: StoredVersion(
            versionId: next.recordVersionId,
            identity: next.identity,
            payload: next.payload.toWire(),
            digest: next.payloadDigest,
          ),
        ),
      );
    }
  }
}
