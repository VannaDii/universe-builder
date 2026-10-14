import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'value_input_fields.dart';
import 'scope_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';
import 'unit_reference_field.dart';

class ActionRequirementFields extends StatelessWidget {
  const ActionRequirementFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final ActionRequirementInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<ActionRequirementInput> onChanged;
  void change({
    String? role,
    ExpressionReferenceInput? predicate,
    QualifierInput? value,
  }) => onChanged(
    ActionRequirementInput(
      role: role ?? input.role,
      predicate: predicate ?? input.predicate,
      value: value ?? input.value,
      original: input.original,
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: input.role,
        enabled: !disabled,
        decoration: const InputDecoration(labelText: 'Participant role'),
        onChanged: (v) => change(role: v),
      ),
      DraftRecordChoiceField(
        changes: changes,
        draft: draft,
        kind: RecordKind.property,
        label: 'Required property',
        record: input.predicate.record,
        universe: input.predicate.universe,
        disabled: disabled,
        onChanged: (v) => change(
          predicate: ExpressionReferenceInput(
            record: v.record.value,
            universe: v.universe?.value ?? '',
          ),
        ),
      ),
      ValueInputFields(
        input: input.value,
        changes: changes,
        draft: draft,
        disabled: disabled,
        named: false,
        label: 'Required value',
        original: input.original?.value,
        onChanged: (v) => change(value: v),
      ),
    ],
  );
}

class ActionInputFields extends StatefulWidget {
  const ActionInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onRequirements,
    required this.onSlots,
    required this.onScope,
    required this.onValidity,
  });
  final UnfinishedActionForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<List<ActionRequirementInput>> onRequirements;
  final ValueChanged<List<ActionSlotInput>?> onSlots;
  final ValueChanged<ScopeInput> onScope;
  final ValueChanged<TemporalValidityInput> onValidity;
  @override
  State<ActionInputFields> createState() => _ActionInputFieldsState();
}

class _ActionInputFieldsState extends State<ActionInputFields> {
  int _layout = 0;
  UnfinishedActionForm get form => widget.form;
  bool get disabled => widget.disabled;
  void _slot(
    int i, {
    Map<String, String>? fields,
    ExpressionReferenceInput? target,
    ActionRequirementInput? condition,
    QualifierInput? value,
  }) {
    final slots = [...form.slots!], old = slots[i];
    slots[i] = ActionSlotInput(
      fields: fields ?? old.fields,
      target: target ?? old.target,
      condition: condition ?? old.condition,
      value: value ?? old.value,
      original: old.original,
    );
    widget.onSlots(slots);
  }

  void _field(int i, String key, String value) =>
      _slot(i, fields: {...form.slots![i].fields, key: value});
  Widget _text(int i, String key, String label) => TextFormField(
    key: ValueKey((_layout, i, key)),
    initialValue: form.slots![i].fields[key] ?? '',
    enabled: !disabled,
    decoration: InputDecoration(labelText: label),
    onChanged: (v) => _field(i, key, v),
  );
  Widget _choice(
    int i,
    String key,
    String label,
    Map<String, String> choices,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((_layout, i, key)),
    initialValue: (form.slots![i].fields[key] ?? '').isEmpty
        ? null
        : form.slots![i].fields[key],
    decoration: InputDecoration(labelText: label),
    items: [
      for (final e in choices.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: disabled
        ? null
        : (v) {
            if (v != null) _field(i, key, v);
          },
  );
  Widget _rowActions(
    int i,
    int length,
    void Function(int, int) move,
    VoidCallback remove,
  ) => Wrap(
    children: [
      TextButton(
        onPressed: disabled || i == 0 ? null : () => move(i, i - 1),
        child: const Text('Move earlier'),
      ),
      TextButton(
        onPressed: disabled || i == length - 1 ? null : () => move(i, i + 1),
        child: const Text('Move later'),
      ),
      TextButton(
        onPressed: disabled ? null : remove,
        child: const Text('Remove'),
      ),
    ],
  );
  void _requirements(List<ActionRequirementInput> inputs) {
    _layout++;
    widget.onRequirements(inputs);
  }

  void _slots(List<ActionSlotInput>? inputs) {
    _layout++;
    widget.onSlots(inputs);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Action requirements'),
      for (var i = 0; i < form.requirements.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ActionRequirementFields(
                  key: ValueKey((_layout, 'requirement', i)),
                  input: form.requirements[i],
                  changes: widget.changes,
                  draft: widget.draft,
                  disabled: disabled,
                  onChanged: (v) {
                    final inputs = [...form.requirements];
                    inputs[i] = v;
                    widget.onRequirements(inputs);
                  },
                ),
                _rowActions(i, form.requirements.length, (a, b) {
                  final inputs = [...form.requirements],
                      input = inputs.removeAt(a);
                  inputs.insert(b, input);
                  _requirements(inputs);
                }, () => _requirements([...form.requirements]..removeAt(i))),
              ],
            ),
          ),
        ),
      TextButton(
        onPressed: disabled
            ? null
            : () => _requirements([
                ...form.requirements,
                const ActionRequirementInput(),
              ]),
        child: const Text('Add requirement'),
      ),
      SwitchListTile(
        title: const Text('Declare a consequence contract'),
        subtitle: const Text(
          'An empty contract declares no consequence slots. Turning this off removes the contract.',
        ),
        value: form.slots != null,
        onChanged: disabled ? null : (v) => _slots(v ? [] : null),
      ),
      if (form.slots != null) ...[
        for (var i = 0; i < form.slots!.length; i++)
          Card(
            key: ValueKey((_layout, 'slot', i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _text(i, 'slot', 'Slot name'),
                  _text(i, 'order', 'Execution order (0–63)'),
                  _choice(i, 'presence', 'Presence', {
                    for (final p in EffectPresence.values) p.name: p.name,
                  }),
                  _text(i, 'role', 'Target participant role'),
                  DraftRecordChoiceField(
                    changes: widget.changes,
                    draft: widget.draft,
                    kind: RecordKind.property,
                    label: 'Target property',
                    record: form.slots![i].target.record,
                    universe: form.slots![i].target.universe,
                    disabled: disabled,
                    onChanged: (v) => _slot(
                      i,
                      target: ExpressionReferenceInput(
                        record: v.record.value,
                        universe: v.universe?.value ?? '',
                      ),
                    ),
                  ),
                  _choice(i, 'condition', 'Consequence condition', {
                    'always': 'Always',
                    'attribute_equals': 'When a property equals a value',
                  }),
                  if (form.slots![i].fields['condition'] == 'attribute_equals')
                    ActionRequirementFields(
                      key: ValueKey((_layout, 'condition', i)),
                      input: form.slots![i].condition,
                      changes: widget.changes,
                      draft: widget.draft,
                      disabled: disabled,
                      onChanged: (v) => _slot(i, condition: v),
                    ),
                  _choice(i, 'change', 'Change', {
                    'set': 'Set a value',
                    'delta': 'Numeric change with bounds',
                  }),
                  if (form.slots![i].fields['change'] == 'set') ...[
                    _choice(i, 'polarity', 'Evidence polarity', {
                      for (final p in Polarity.values) p.wireName: p.wireName,
                    }),
                    ValueInputFields(
                      key: ValueKey((_layout, 'value', i)),
                      input: form.slots![i].value,
                      changes: widget.changes,
                      draft: widget.draft,
                      disabled: disabled,
                      named: false,
                      label: 'Consequence value',
                      original: form.slots![i].original?.change is SetEffect
                          ? (form.slots![i].original!.change as SetEffect).value
                          : null,
                      onChanged: (v) => _slot(i, value: v),
                    ),
                  ],
                  if (form.slots![i].fields['change'] == 'delta') ...[
                    _text(i, 'delta', 'Exact numeric change'),
                    _text(i, 'minimum', 'Exact minimum'),
                    _text(i, 'maximum', 'Exact maximum'),
                    UnitReferenceField(
                      changes: widget.changes,
                      draft: widget.draft,
                      unit: form.slots![i].fields['unit'] ?? '',
                      disabled: disabled,
                      onChanged: (v) => _field(i, 'unit', v),
                    ),
                  ],
                  _choice(i, 'lifetime', 'Lifetime', {
                    'until_changed': 'Until changed',
                    'ticks': 'A number of ticks',
                  }),
                  if (form.slots![i].fields['lifetime'] == 'ticks')
                    _text(i, 'count', 'Exact tick count'),
                  _rowActions(i, form.slots!.length, (a, b) {
                    final inputs = [...form.slots!], input = inputs.removeAt(a);
                    inputs.insert(b, input);
                    _slots(inputs);
                  }, () => _slots([...form.slots!]..removeAt(i))),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () => _slots([...form.slots!, ActionSlotInput()]),
          child: const Text('Add consequence slot'),
        ),
        const Text(
          'Moving slots preserves declared execution-order numbers. Consequences are declarations; this editor does not execute an event.',
        ),
      ],
      ExpansionTile(
        title: const Text('Action scope'),
        children: [
          ScopeInputFields(
            input: form.scope,
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: widget.onScope,
          ),
        ],
      ),
      DropdownButtonFormField<String>(
        key: ValueKey((_layout, 'validity-kind')),
        initialValue:
            {
              'unknown',
              'unspecified',
              'condition_dependent',
            }.contains(form.validity.kind)
            ? form.validity.kind
            : 'temporal',
        decoration: const InputDecoration(labelText: 'Action validity'),
        items: const [
          DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
          DropdownMenuItem(value: 'unspecified', child: Text('Unspecified')),
          DropdownMenuItem(
            value: 'condition_dependent',
            child: Text('Condition dependent'),
          ),
          DropdownMenuItem(value: 'temporal', child: Text('Temporal validity')),
        ],
        onChanged: disabled
            ? null
            : (v) {
                if (v != null) {
                  _layout++;
                  widget.onValidity(
                    v == 'temporal'
                        ? const TemporalValidityInput()
                        : TemporalValidityInput(kind: v),
                  );
                }
              },
      ),
      if (!{
        'unknown',
        'unspecified',
        'condition_dependent',
      }.contains(form.validity.kind))
        TemporalValidityFields(
          key: ValueKey((_layout, 'validity')),
          input: form.validity,
          originalAmounts: temporalOriginalAmounts(form.original?.validity),
          changes: widget.changes,
          draft: widget.draft,
          disabled: disabled,
          onChanged: widget.onValidity,
        ),
    ],
  );
}
