import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class MemoryInputFields extends StatelessWidget {
  const MemoryInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedMemoryForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedMemoryForm> onChanged;
  Widget _reference(
    String label,
    ExpressionReferenceInput value,
    ValueChanged<ExpressionReferenceInput> change, {
    RecordKind? kind,
  }) => DraftRecordChoiceField(
    changes: changes,
    draft: draft,
    kind: kind,
    label: label,
    record: value.record,
    universe: value.universe,
    disabled: disabled,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _reference(
        'Holder',
        form.holder,
        (v) => onChanged(form.copyWith(holder: v)),
        kind: RecordKind.entity,
      ),
      _reference(
        'Remembered content',
        form.content,
        (v) => onChanged(form.copyWith(content: v)),
      ),
      SwitchListTile(
        title: const Text('Include an alleged record'),
        value: form.allegedEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(form.copyWith(allegedEnabled: v)),
      ),
      if (form.allegedEnabled)
        _reference(
          'Alleged record',
          form.alleged,
          (v) => onChanged(form.copyWith(alleged: v)),
        ),
      TextFormField(
        initialValue: form.accessibility,
        enabled: !disabled,
        decoration: const InputDecoration(labelText: 'Authored accessibility'),
        maxLines: 3,
        onChanged: (v) => onChanged(form.copyWith(accessibility: v)),
      ),
      DropdownButtonFormField<bool>(
        key: ValueKey(('altered', form.altered)),
        initialValue: form.altered,
        decoration: const InputDecoration(labelText: 'Alteration'),
        items: const [
          DropdownMenuItem(value: true, child: Text('Altered')),
          DropdownMenuItem(value: false, child: Text('Not altered')),
        ],
        onChanged: disabled
            ? null
            : (v) {
                if (v != null) onChanged(form.copyWith(altered: v));
              },
      ),
      DropdownButtonFormField<String>(
        key: ValueKey(('validity', form.validity.kind)),
        initialValue:
            {
              'unknown',
              'unspecified',
              'condition_dependent',
            }.contains(form.validity.kind)
            ? form.validity.kind
            : 'temporal',
        decoration: const InputDecoration(labelText: 'Memory validity'),
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
                  onChanged(
                    form.copyWith(
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
      }.contains(form.validity.kind))
        TemporalValidityFields(
          input: form.validity,
          originalAmounts: temporalOriginalAmounts(form.original?.validity),
          changes: changes,
          draft: draft,
          disabled: disabled,
          onChanged: (v) => onChanged(form.copyWith(validity: v)),
        ),
    ],
  );
}
