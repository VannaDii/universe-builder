import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'expression_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class CommitmentInputFields extends StatefulWidget {
  const CommitmentInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedCommitmentForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedCommitmentForm> onChanged;
  @override
  State<CommitmentInputFields> createState() => _CommitmentInputFieldsState();
}

class _CommitmentInputFieldsState extends State<CommitmentInputFields> {
  int _layout = 0;
  Widget _reference(
    String label,
    ExpressionReferenceInput input,
    ValueChanged<ExpressionReferenceInput> change,
  ) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: null,
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
    void change(UnfinishedCommitmentForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Parties and roles'),
        for (var i = 0; i < f.parties.length; i++)
          Card(
            key: ValueKey((_layout, 'party', i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _reference(
                    'Party ${i + 1}',
                    ExpressionReferenceInput(
                      record: f.parties[i].record,
                      universe: f.parties[i].universe,
                    ),
                    (v) {
                      final rows = [...f.parties], p = rows[i];
                      rows[i] = CommitmentPartyInput(
                        record: v.record,
                        universe: v.universe,
                        role: p.role,
                      );
                      change(f.copyWith(parties: rows));
                    },
                  ),
                  TextFormField(
                    initialValue: f.parties[i].role,
                    enabled: !disabled,
                    decoration: const InputDecoration(labelText: 'Party role'),
                    onChanged: (v) {
                      final rows = [...f.parties], p = rows[i];
                      rows[i] = CommitmentPartyInput(
                        record: p.record,
                        universe: p.universe,
                        role: v,
                      );
                      change(f.copyWith(parties: rows));
                    },
                  ),
                  _controls(
                    i,
                    f.parties.length,
                    (offset) {
                      final rows = [...f.parties], row = rows.removeAt(i);
                      rows.insert(i + offset, row);
                      _layout++;
                      change(f.copyWith(parties: rows));
                    },
                    () {
                      _layout++;
                      change(f.copyWith(parties: [...f.parties]..removeAt(i)));
                    },
                  ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      parties: [...f.parties, const CommitmentPartyInput()],
                    ),
                  );
                },
          child: const Text('Add party'),
        ),
        _reference(
          'Obligated record',
          f.obligated,
          (v) => change(f.copyWith(obligated: v)),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('status', f.status)),
          initialValue: f.status.isEmpty ? null : f.status,
          decoration: const InputDecoration(labelText: 'Commitment status'),
          items: const [
            DropdownMenuItem(value: 'unfulfilled', child: Text('Unfulfilled')),
            DropdownMenuItem(value: 'fulfilled', child: Text('Fulfilled')),
            DropdownMenuItem(value: 'breached', child: Text('Breached')),
            DropdownMenuItem(value: 'released', child: Text('Released')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(status: v));
                },
        ),
        const Text('Declared conditions'),
        for (var i = 0; i < f.conditions.length; i++)
          Card(
            key: ValueKey((_layout, 'condition', i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ExpressionInputFields(
                    input: f.conditions[i],
                    changes: widget.changes,
                    draft: widget.draft,
                    disabled: disabled,
                    onChanged: (v) {
                      final rows = [...f.conditions];
                      rows[i] = v;
                      change(f.copyWith(conditions: rows));
                    },
                  ),
                  _controls(
                    i,
                    f.conditions.length,
                    (offset) {
                      final rows = [...f.conditions], row = rows.removeAt(i);
                      rows.insert(i + offset, row);
                      _layout++;
                      change(f.copyWith(conditions: rows));
                    },
                    () {
                      _layout++;
                      change(
                        f.copyWith(conditions: [...f.conditions]..removeAt(i)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      conditions: [...f.conditions, ExpressionInput()],
                    ),
                  );
                },
          child: const Text('Add condition'),
        ),
        SwitchListTile(
          title: const Text('Include a deadline'),
          value: f.deadlineEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(deadlineEnabled: v)),
        ),
        if (f.deadlineEnabled)
          TemporalValidityFields(
            input: f.deadline,
            expressionOnly: true,
            originalAmounts: temporalOriginalAmounts(
              f.original?.deadline == null
                  ? null
                  : InstantValidity(f.original!.deadline!),
            ),
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: (v) => change(f.copyWith(deadline: v)),
          ),
      ],
    );
  }
}
