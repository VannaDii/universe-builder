import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';
import 'scope_draft.dart';
import 'temporal_validity_draft.dart';

ExpressionReferenceInput _inputRef(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
ActionRequirementInput actionRequirementInput(
  AttributeRequirement requirement,
) => ActionRequirementInput(
  role: requirement.role,
  predicate: _inputRef(requirement.predicate),
  value: qualifierInput('value', requirement.value),
  original: requirement,
);
AttributeRequirement buildActionRequirement(ActionRequirementInput input) =>
    AttributeRequirement(
      input.role,
      _ref(input.predicate),
      buildQualifierValue(input.value, input.original?.value),
    );
ActionSlotInput actionSlotInput(EffectSlot slot) => ActionSlotInput(
  fields: {
    'slot': slot.slot,
    'order': slot.order.toString(),
    'presence': slot.presence.name,
    'role': slot.target.role,
    'condition': slot.condition is AlwaysEffect ? 'always' : 'attribute_equals',
    'change': slot.change is SetEffect ? 'set' : 'delta',
    if (slot.change case SetEffect(:final polarity))
      'polarity': polarity.wireName,
    if (slot.change case DeltaEffect(
      :final delta,
      :final minimum,
      :final maximum,
      :final unit,
    )) ...{
      'delta': delta.digits,
      'minimum': minimum.digits,
      'maximum': maximum.digits,
      'unit': unit?.value ?? '',
    },
    'lifetime': slot.lifetime is UntilChangedEffect ? 'until_changed' : 'ticks',
    if (slot.lifetime case TicksEffect(:final count)) 'count': count.digits,
  },
  target: _inputRef(slot.target.predicate),
  condition: slot.condition is AttributeEqualsEffect
      ? actionRequirementInput(
          AttributeRequirement(
            (slot.condition as AttributeEqualsEffect).role,
            (slot.condition as AttributeEqualsEffect).predicate,
            (slot.condition as AttributeEqualsEffect).value,
          ),
        )
      : const ActionRequirementInput(),
  value: slot.change is SetEffect
      ? qualifierInput('value', (slot.change as SetEffect).value)
      : const QualifierInput(),
  original: slot,
);
EffectSlot buildActionSlot(ActionSlotInput input) {
  String field(String key) => input.fields[key] ?? '';
  final condition = switch (field('condition')) {
    'always' => const AlwaysEffect(),
    'attribute_equals' => AttributeEqualsEffect(
      input.condition.role,
      _ref(input.condition.predicate),
      buildQualifierValue(
        input.condition.value,
        input.condition.original?.value,
      ),
    ),
    _ => throw const FormatException('Choose a consequence condition.'),
  };
  final change = switch (field('change')) {
    'set' => SetEffect(
      Polarity.fromWire(CanonicalString(field('polarity'))),
      buildQualifierValue(
        input.value,
        input.original?.change is SetEffect
            ? (input.original!.change as SetEffect).value
            : null,
      ),
    ),
    'delta' => DeltaEffect(
      delta: ConsequenceDecimal(field('delta')),
      minimum: ConsequenceDecimal(field('minimum')),
      maximum: ConsequenceDecimal(field('maximum')),
      unit: field('unit').isEmpty ? null : UnitId.parse(field('unit')),
    ),
    _ => throw const FormatException('Choose a consequence change.'),
  };
  return EffectSlot(
    slot: field('slot'),
    order: int.parse(field('order')),
    presence: EffectPresence.fromName(field('presence')),
    target: EffectTarget(field('role'), _ref(input.target)),
    condition: condition,
    change: change,
    lifetime: switch (field('lifetime')) {
      'until_changed' => const UntilChangedEffect(),
      'ticks' => TicksEffect(ConsequenceInteger(field('count'))),
      _ => throw const FormatException('Choose a consequence lifetime.'),
    },
  );
}

TemporalValidityInput actionValidityInput(Validity validity) =>
    switch (validity) {
      UnknownValidity() => const TemporalValidityInput(kind: 'unknown'),
      UnspecifiedValidity() => const TemporalValidityInput(kind: 'unspecified'),
      ConditionalValidity() => const TemporalValidityInput(
        kind: 'condition_dependent',
      ),
      _ => temporalValidityInput(validity),
    };
Validity buildActionValidity(TemporalValidityInput input, Validity? original) =>
    switch (input.kind) {
      'unknown' => const UnknownValidity(),
      'unspecified' => const UnspecifiedValidity(),
      'condition_dependent' => const ConditionalValidity(),
      _ => buildTemporalValidity(input, original),
    };
DefineActionOperation actionOperation(UnfinishedActionForm form) {
  if ([form.namespace, form.key, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException('Enter an action namespace and key.');
  }
  final labels = <String, String>{};
  for (final label in form.labels) {
    if (labels.containsKey(label.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[label.language] = label.text;
  }
  return DefineActionOperation(
    clientRef: form.clientRef,
    record: ActionDefinitionRecord(
      namespace: form.namespace,
      key: form.key,
      labels: labels,
      requirements: form.requirements.map(buildActionRequirement),
      consequenceContract: form.slots == null
          ? null
          : ConsequenceContract(form.slots!.map(buildActionSlot)),
      scope: buildScope(form.scope),
      validity: buildActionValidity(form.validity, form.original?.validity),
    ),
  );
}

ReviseDefinitionOperation actionRevisionOperation(UnfinishedActionForm form) {
  if (form.revisionTarget == null ||
      form.expectedRecordVersion == null ||
      form.original == null) {
    throw const FormatException(
      'Open a published action definition to revise it.',
    );
  }
  final next = actionOperation(form).record;
  if (next.namespace != form.original!.namespace ||
      next.key != form.original!.key) {
    throw const FormatException('Action revisions retain namespace and key.');
  }
  final target = form.revisionTarget!;
  return ReviseDefinitionOperation(
    record: RecordRef(
      record: RecordId.parse(target.record),
      universe: target.universe.isEmpty
          ? null
          : UniverseId.parse(target.universe),
    ),
    expectedVersion: form.expectedRecordVersion!,
    replacement: next,
  );
}

UnfinishedActionForm actionRevisionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! ActionDefinitionRecord) {
    throw const FormatException('Choose a published action definition.');
  }
  return _actionForm(
    record: record.payload as ActionDefinitionRecord,
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    revisionTarget: ExpressionReferenceInput(
      record: record.identity.recordId.value,
      universe: record.identity.universeId.value,
    ),
    expectedRecordVersion: record.recordVersionId,
  );
}

UnfinishedActionForm actionFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is ActionDefinitionRecord) {
    return _actionForm(
      record: operation.replacement as ActionDefinitionRecord,
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: operation.record.record.value,
      revisionTarget: ExpressionReferenceInput(
        record: operation.record.record.value,
        universe: operation.record.universe?.value ?? '',
      ),
      expectedRecordVersion: operation.expectedVersion,
      draftVersion: draft.version,
    );
  }
  if (operation is! DefineActionOperation) {
    throw const FormatException('Choose an action definition from Changes.');
  }
  return _actionForm(
    record: operation.record,
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    draftVersion: draft.version,
  );
}

UnfinishedActionForm _actionForm({
  required ActionDefinitionRecord record,
  required RevisionId baseRevision,
  required RecordId representedContext,
  required String clientRef,
  ExpressionReferenceInput? revisionTarget,
  RecordVersionId? expectedRecordVersion,
  BigInt? draftVersion,
}) => UnfinishedActionForm(
  baseRevision: baseRevision,
  representedContext: representedContext,
  clientRef: clientRef,
  revisionTarget: revisionTarget,
  expectedRecordVersion: expectedRecordVersion,
  namespace: record.namespace,
  key: record.key,
  labels: record.labels.entries.map(
    (e) => PropertyLabelInput(language: e.key, text: e.value),
  ),
  requirements: record.requirements.map(actionRequirementInput),
  slots: record.consequenceContract?.slots.map(actionSlotInput),
  scope: scopeInput(record.scope),
  validity: actionValidityInput(record.validity),
  original: record,
  draftVersion: draftVersion,
);

SaveDraftEngineRequest actionDraftRequest({
  required SavedDraft draft,
  required UnfinishedActionForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this action definition.',
    );
  }
  final operation = form.revisionTarget == null
      ? actionOperation(form)
      : actionRevisionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = actionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.revisionTarget?.toWire().toText() !=
            before.revisionTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current action-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is ReviseDefinitionOperation &&
          existing is ReviseDefinitionOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This action already has a revision. Edit it in Changes.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }

      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This action definition is already in Changes. Edit it there.',
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
      rationale: index == null
          ? [
              if (draft.content.rationale.isNotEmpty) draft.content.rationale,
              if (form.rationale.isNotEmpty) form.rationale,
            ].join('\n\n')
          : draft.content.rationale,
    ),
  );
}
