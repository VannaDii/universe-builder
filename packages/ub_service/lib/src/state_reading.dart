import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

import 'effective_objects.dart';

Frame stateReadFrame(
  Frame frame,
  List<RecordVersion> accessible,
  RecordId? event,
  EventTimeSide? side,
) {
  if ((event == null) != (side == null)) {
    throw const InvalidArgumentError(
      field: 'event',
      message: 'event and event_side must be supplied together',
    );
  }
  if (event == null) return frame;
  if (!accessible.any(
    (row) =>
        row.identity.recordId == event &&
        row.payload is EventRecord &&
        switch ((row.payload as EventRecord).occurrence) {
          SimpleOccurrence(kind: OccurrenceKind.occurred) => true,
          _ => false,
        },
  )) {
    throw const NotFoundOrNotAccessibleError(message: 'resource');
  }
  return Frame(
    universe: frame.universe,
    continuity: frame.continuity,
    revision: frame.revision,
    context: frame.context,
    time: AtEventFrameTime(
      RecordRef(universe: frame.universe, record: event),
      side!,
    ),
    perspective: frame.perspective,
    readerScene: frame.readerScene,
    personalSequence: frame.personalSequence,
  );
}

/// Select explicit evidence from an already admitted snapshot. Unknown validity
/// stays visible, absent evidence stays undefined and derived powers are not canon.
State assembleReadState({
  required List<RecordVersion> records,
  required Frame frame,
  required List<RecordId> ids,
  required List<RecordId> predicates,
  required WorldId? world,
  required bool restricted,
  Set<RecordId> excludedRules = const {},
  List<InitializationReceipt> receipts = const [],
  RecordVersion Function(RecordVersionId)? readVersion,
}) {
  for (final id in ids) {
    if (!records.any((row) => row.identity.recordId == id)) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
  }
  bool focus(Scope scope) =>
      world == null ||
      scope.applicability is! WorldsApplicability ||
      (scope.applicability as WorldsApplicability).worldIds.contains(world);
  final propositionIds = <RecordId>{
    for (final row in records)
      if (row.payload case PropositionRecord(
        :final subject,
        :final context,
        :final predicate,
      ))
        if (ids.contains(subject.record) &&
            context == frame.context &&
            (predicates.isEmpty || predicates.contains(predicate.record)))
          row.identity.recordId,
  };
  final assertions = records
      .where(
        (row) => switch (row.payload) {
          AssertionRecord(:final proposition, :final scope, :final validity) =>
            propositionIds.contains(proposition.record) &&
                focus(scope) &&
                scope.context == frame.context &&
                eventApplies(validity, frame.time, records) != false,
          _ => false,
        },
      )
      .toList();
  final completeness = records
      .where(
        (row) => switch (row.payload) {
          CompletenessRecord(
            :final subject,
            :final scope,
            :final validity,
            :final predicate,
          ) =>
            ids.contains(subject.record) &&
                focus(scope) &&
                scope.context == frame.context &&
                eventApplies(validity, frame.time, records) != false &&
                (predicates.isEmpty ||
                    predicates.any((id) => id.value == predicate)),
          _ => false,
        },
      )
      .toList();
  bool represented(RecordRef proposition) => records.any(
    (row) =>
        row.identity.recordId == proposition.record &&
        row.payload is PropositionRecord &&
        (row.payload as PropositionRecord).context == frame.context,
  );
  final epistemic = records
      .where(
        (row) => switch (row.payload) {
          EpistemicAttitudeRecord(
            :final holder,
            :final proposition,
            :final validity,
          ) =>
            ids.contains(holder.record) &&
                represented(proposition) &&
                eventApplies(validity, frame.time, records) != false,
          MemoryRecord(:final holder, :final content, :final validity) =>
            ids.contains(holder.record) &&
                represented(content) &&
                eventApplies(validity, frame.time, records) != false,
          _ => false,
        },
      )
      .toList();
  Chronology? chronology;
  for (final row in records) {
    if (row.identity.recordId == frame.context.record &&
        row.payload is RepresentedContextRecord) {
      chronology = (row.payload as RepresentedContextRecord).chronology;
      break;
    }
  }
  late List<PowerFact> derived;
  try {
    derived = derivePowers(
      records: records,
      subjects: ids,
      predicates: predicates,
      context: frame.context,
      time: frame.time,
      world: world,
    );
  } on PowerEvaluationError catch (error) {
    throw EvaluationLimitReachedError(message: error.toString());
  }
  final objects = assembleEffectiveObjects(
    records: records,
    ids: ids,
    predicates: predicates,
    frame: frame,
    world: world,
    restricted: restricted,
    excludedRules: excludedRules,
  );
  final reviewedObjects = <EffectiveObject>[];
  for (final object in objects) {
    final selected = <InitializationReceipt>[];
    if (!restricted) {
      for (final receipt in receipts) {
        if (receipt.instance != object.identity.identity.recordId ||
            predicates.isNotEmpty && !predicates.contains(receipt.property)) {
          continue;
        }
        if (readVersion == null) {
          throw StateError(
            'Initialization history requires immutable version reads',
          );
        }
        final original = readVersion(receipt.assertion).payload;
        if (original is! AssertionRecord ||
            original.scope.context != frame.context) {
          continue;
        }
        if (world != null &&
            worldApplies(original.scope.applicability, [
                  RecordId.parse(
                    'rec_${world.value.substring(WorldId.prefix.length)}',
                  ),
                ]) !=
                true) {
          continue;
        }
        selected.add(receipt);
      }
    }
    reviewedObjects.add(
      EffectiveObject(
        identity: object.identity,
        contextualNames: object.contextualNames,
        ancestry: object.ancestry,
        ancestryComplete: object.ancestryComplete,
        sharedAttributes: object.sharedAttributes,
        instanceFacts: object.instanceFacts,
        initialValueCandidates: object.initialValueCandidates,
        initializationReceipts: selected,
        initializationHistoryCoverage: restricted
            ? Coverage.restricted
            : Coverage.complete,
        behavioralRequirements: object.behavioralRequirements,
        rules: object.rules,
        dependencies: object.dependencies,
        conflicts: object.conflicts,
        unknowns: object.unknowns,
        coverage: object.coverage,
      ),
    );
  }
  return State(
    objects: reviewedObjects,
    derived: derived.map(
      (fact) => DerivedFact(
        subject: fact.subject,
        predicate: fact.predicate,
        value: fact.value,
        evidence: fact.evidence,
        rule: fact.rule,
      ),
    ),
    epistemic: epistemic,
    chronology: chronology,
    unresolvedAssertionIds: assertions
        .where(
          (row) =>
              eventApplies(
                (row.payload as AssertionRecord).validity,
                frame.time,
                records,
              ) ==
              null,
        )
        .map((row) => row.identity.recordId),
    assertions: assertions,
    propositions: records.where(
      (row) => propositionIds.contains(row.identity.recordId),
    ),
    completeness: completeness,
    coverage: Coverage.partial,
    unsupportedCapabilities: [
      'Explicit evidence filtered by the authored time frame; unresolved validities remain visible. Exact event effects and explicit possession powers are evaluated; complex causality and temporal completeness inference remain unavailable; absent evidence remains undefined.',
    ],
  );
}
