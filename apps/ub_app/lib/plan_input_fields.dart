import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'expression_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class PlanInputFields extends StatefulWidget {
  const PlanInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedPlanForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedPlanForm> onChanged;
  @override
  State<PlanInputFields> createState() => _PlanInputFieldsState();
}

class _PlanInputFieldsState extends State<PlanInputFields> {
  int _layout = 0;
  Widget _reference(
    String label,
    ExpressionReferenceInput input,
    ValueChanged<ExpressionReferenceInput> change, {
    RecordKind? kind,
  }) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
    label: label,
    record: input.record,
    universe: input.universe,
    disabled: widget.disabled,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  Widget _controls(
    int i,
    int length,
    void Function(int) move,
    VoidCallback remove,
  ) => Wrap(
    children: [
      TextButton(
        onPressed: widget.disabled || i == 0 ? null : () => move(-1),
        child: const Text('Move earlier'),
      ),
      TextButton(
        onPressed: widget.disabled || i == length - 1 ? null : () => move(1),
        child: const Text('Move later'),
      ),
      TextButton(
        onPressed: widget.disabled ? null : remove,
        child: const Text('Remove entry'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedPlanForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reference(
          'Actor',
          f.actor,
          (v) => change(f.copyWith(actor: v)),
          kind: RecordKind.entity,
        ),
        SwitchListTile(
          title: const Text('Include a desired record'),
          value: f.desiredEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(desiredEnabled: v)),
        ),
        if (f.desiredEnabled)
          _reference(
            'Desired record',
            f.desired,
            (v) => change(f.copyWith(desired: v)),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey(('status', f.status)),
          initialValue: f.status.isEmpty ? null : f.status,
          decoration: const InputDecoration(labelText: 'Plan status'),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('Active')),
            DropdownMenuItem(value: 'abandoned', child: Text('Abandoned')),
            DropdownMenuItem(value: 'achieved', child: Text('Achieved')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(status: v));
                },
        ),
        const Text('Declared prerequisites'),
        for (var i = 0; i < f.prerequisites.length; i++)
          Card(
            key: ValueKey((_layout, 'prerequisite', i)),
            child: Column(
              children: [
                ExpressionInputFields(
                  input: f.prerequisites[i],
                  changes: widget.changes,
                  draft: widget.draft,
                  disabled: disabled,
                  onChanged: (v) {
                    final rows = [...f.prerequisites];
                    rows[i] = v;
                    change(f.copyWith(prerequisites: rows));
                  },
                ),
                _controls(
                  i,
                  f.prerequisites.length,
                  (offset) {
                    final rows = [...f.prerequisites], row = rows.removeAt(i);
                    rows.insert(i + offset, row);
                    _layout++;
                    change(f.copyWith(prerequisites: rows));
                  },
                  () {
                    _layout++;
                    change(
                      f.copyWith(
                        prerequisites: [...f.prerequisites]..removeAt(i),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      prerequisites: [...f.prerequisites, ExpressionInput()],
                    ),
                  );
                },
          child: const Text('Add prerequisite'),
        ),
        const Text('Ordered steps'),
        for (var i = 0; i < f.steps.length; i++)
          Card(
            key: ValueKey((_layout, 'step', i)),
            child: Column(
              children: [
                _reference('Step ${i + 1}', f.steps[i], (v) {
                  final rows = [...f.steps];
                  rows[i] = v;
                  change(f.copyWith(steps: rows));
                }),
                _controls(
                  i,
                  f.steps.length,
                  (offset) {
                    final rows = [...f.steps], row = rows.removeAt(i);
                    rows.insert(i + offset, row);
                    _layout++;
                    change(f.copyWith(steps: rows));
                  },
                  () {
                    _layout++;
                    change(f.copyWith(steps: [...f.steps]..removeAt(i)));
                  },
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      steps: [...f.steps, const ExpressionReferenceInput()],
                    ),
                  );
                },
          child: const Text('Add step'),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('validity', f.validity.kind)),
          initialValue:
              {
                'unknown',
                'unspecified',
                'condition_dependent',
              }.contains(f.validity.kind)
              ? f.validity.kind
              : 'temporal',
          decoration: const InputDecoration(labelText: 'Plan validity'),
          items: const [
            DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
            DropdownMenuItem(value: 'unspecified', child: Text('Unspecified')),
            DropdownMenuItem(
              value: 'condition_dependent',
              child: Text('Condition dependent'),
            ),
            DropdownMenuItem(
              value: 'temporal',
              child: Text('Temporal validity'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) {
                    change(
                      f.copyWith(
                        validity: v == 'temporal'
                            ? const TemporalValidityInput()
                            : TemporalValidityInput(kind: v),
                      ),
                    );
                  }
                },
        ),
        if (!{
          'unknown',
          'unspecified',
          'condition_dependent',
        }.contains(f.validity.kind))
          TemporalValidityFields(
            input: f.validity,
            originalAmounts: temporalOriginalAmounts(f.original?.validity),
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: (v) => change(f.copyWith(validity: v)),
          ),
      ],
    );
  }
}
