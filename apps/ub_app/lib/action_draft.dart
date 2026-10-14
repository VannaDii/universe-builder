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

UnfinishedActionForm actionFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! DefineActionOperation) {
    throw const FormatException('Choose an action definition from Changes.');
  }
  final record = operation.record;
  return UnfinishedActionForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
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
    draftVersion: draft.version,
  );
}

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
  final operation = actionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = actionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current action-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
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
