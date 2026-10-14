import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'value_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class WorldAssociationInputFields extends StatefulWidget {
  const WorldAssociationInputFields({
    super.key,
    required this.input,
    required this.original,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final WorkAssociationInput input;
  final WorldAssociation? original;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<WorkAssociationInput> onChanged;
  @override
  State<WorldAssociationInputFields> createState() =>
      _WorldAssociationInputFieldsState();
}

class _WorldAssociationInputFieldsState
    extends State<WorldAssociationInputFields> {
  int _layout = 0;
  @override
  Widget build(BuildContext context) {
    final a = widget.input,
        original = widget.original,
        disabled = widget.disabled;
    void association(WorkAssociationInput v) => widget.onChanged(v);
    Widget text(String label, String value, ValueChanged<String> callback) =>
        TextFormField(
          initialValue: value,
          enabled: !disabled,
          decoration: InputDecoration(labelText: label),
          onChanged: callback,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.world,
          label: 'Associated world',
          record: a.world.isEmpty ? '' : worldChoiceRecord(a.world).value,
          universe: widget.changes.scope.universe.value,
          disabled: disabled,
          onChanged: (ref) =>
              association(a.copyWith(world: worldFromChoice(ref).value)),
        ),
        text('World role', a.role, (v) => association(a.copyWith(role: v))),
        DropdownButtonFormField<String>(
          key: ValueKey(('validity', a.validity.kind)),
          initialValue:
              {
                'unknown',
                'unspecified',
                'condition_dependent',
              }.contains(a.validity.kind)
              ? a.validity.kind
              : 'temporal',
          decoration: const InputDecoration(labelText: 'Association validity'),
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
                    association(
                      a.copyWith(
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
        }.contains(a.validity.kind))
          TemporalValidityFields(
            input: a.validity,
            originalAmounts: temporalOriginalAmounts(original?.validity),
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: (v) => association(a.copyWith(validity: v)),
          ),
        const Text('Association qualifiers'),
        for (var q = 0; q < a.qualifiers.length; q++)
          Column(
            key: ValueKey((_layout, 'qualifier', q)),
            children: [
              ValueInputFields(
                input: a.qualifiers[q],
                original: original?.qualifiers[a.qualifiers[q].originalKey],
                changes: widget.changes,
                draft: widget.draft,
                disabled: disabled,
                named: true,
                onChanged: (v) {
                  final rows = [...a.qualifiers];
                  rows[q] = v;
                  association(a.copyWith(qualifiers: rows));
                },
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () {
                        _layout++;
                        association(
                          a.copyWith(
                            qualifiers: [...a.qualifiers]..removeAt(q),
                          ),
                        );
                      },
                child: const Text('Remove qualifier'),
              ),
            ],
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  association(
                    a.copyWith(
                      qualifiers: [...a.qualifiers, const QualifierInput()],
                    ),
                  );
                },
          child: const Text('Add qualifier'),
        ),
      ],
    );
  }
}
