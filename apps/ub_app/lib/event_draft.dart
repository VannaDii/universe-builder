import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'temporal_validity_draft.dart';
import 'scope_draft.dart';
import 'expression_draft.dart';

EventEffectInput eventEffectInput(EntityEffect effect) => EventEffectInput(
  slot: effect.slot,
  propositionRecord: effect.proposition.record.value,
  propositionUniverse: effect.proposition.universe?.value ?? '',
  polarity: effect.polarity.wireName,
  order: effect.order.toString(),
  scope: scopeInput(effect.scope),
  validity: switch (effect.validity) {
    UnknownValidity() => const TemporalValidityInput(kind: 'unknown'),
    UnspecifiedValidity() => const TemporalValidityInput(kind: 'unspecified'),
    ConditionalValidity() => const TemporalValidityInput(kind: 'retain'),
    _ => temporalValidityInput(effect.validity),
  },
  original: effect,
);

EntityEffect buildEventEffect(EventEffectInput input) => EntityEffect(
  slot: input.slot,
  proposition: _reference(input.propositionRecord, input.propositionUniverse),
  polarity: Polarity.fromWire(CanonicalString(input.polarity)),
  order: BigInt.parse(input.order),
  scope: buildScope(input.scope),
  validity: switch (input.validity.kind) {
    'retain' =>
      input.original?.validity ??
          (throw const FormatException('No original validity to retain.')),
    'unknown' => const UnknownValidity(),
    'unspecified' => const UnspecifiedValidity(),
    _ => buildTemporalValidity(input.validity, input.original?.validity),
  },
);

RecordRef _reference(String record, String universe) => RecordRef(
  record: RecordId.parse(record),
  universe: universe.isEmpty ? null : UniverseId.parse(universe),
);

RecordEventOperation eventOperation(UnfinishedEventForm form) {
  final temporal = buildTemporalValidity(
    form.time,
    form.original == null ? null : InstantValidity(form.original!.time),
  );
  if (temporal is! InstantValidity) {
    throw const FormatException('Choose an event time expression.');
  }
  final old = form.original;
  return RecordEventOperation(
    clientRef: form.clientRef,
    record: EventRecord(
      occurrence: form.occurrence == 'descriptive'
          ? DescriptiveOccurrence(form.description)
          : SimpleOccurrence(OccurrenceKind.fromName(form.occurrence)),
      action: form.actionRecord.isEmpty
          ? null
          : _reference(form.actionRecord, form.actionUniverse),
      time: temporal.at,
      labels: {
        ...?old?.labels,
        if (form.label.isNotEmpty || (old?.labels.containsKey('en') ?? false))
          'en': form.label,
      },
      participants: form.participants.map(
        (p) => EventParticipant(_reference(p.record, p.universe), p.role),
      ),
      worlds: form.worlds.map(WorldId.parse),
      region: form.regionRecord.isEmpty
          ? null
          : _reference(form.regionRecord, form.regionUniverse),
      sequence: form.sequence.isEmpty
          ? (old?.sequence == '' ? '' : null)
          : form.sequence,
      occurrenceId: form.occurrenceId.isEmpty
          ? (old?.occurrenceId == '' ? '' : null)
          : form.occurrenceId,
      preconditions:
          form.preconditions?.map(buildExpression) ?? old?.preconditions ?? [],
      effects: form.effects?.map(buildEventEffect) ?? old?.effects ?? [],
      expansionVersion: old?.expansionVersion,
    ),
  );
}

UnfinishedEventForm eventFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! RecordEventOperation) {
    throw const FormatException('Choose an event from Changes.');
  }
  final record = operation.record;
  return UnfinishedEventForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    label: record.labels['en'] ?? '',
    occurrence: switch (record.occurrence) {
      SimpleOccurrence(:final kind) => kind.name,
      DescriptiveOccurrence() => 'descriptive',
    },
    description: record.occurrence is DescriptiveOccurrence
        ? (record.occurrence as DescriptiveOccurrence).label
        : '',
    actionRecord: record.action?.record.value ?? '',
    actionUniverse: record.action?.universe?.value ?? '',
    time: temporalValidityInput(InstantValidity(record.time)),
    participants: record.participants.map(
      (p) => EventParticipantInput(
        record: p.record.record.value,
        universe: p.record.universe?.value ?? '',
        role: p.role,
      ),
    ),
    original: record,
    effects: record.effects.map(eventEffectInput),
    preconditions: record.preconditions.map(expressionInput),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest eventDraftRequest({
  required SavedDraft draft,
  required UnfinishedEventForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException('Review Changes before adding this event.');
  }
  final operation = eventOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = eventFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current event fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This event is already in Changes. Edit it there.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }
    }
    operations.add(operation);
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: DraftContent(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      operations: operations,
      rationale: index != null
          ? draft.content.rationale
          : [
              if (draft.content.rationale.isNotEmpty) draft.content.rationale,
              if (form.rationale.isNotEmpty) form.rationale,
            ].join('\n\n'),
    ),
  );
}
