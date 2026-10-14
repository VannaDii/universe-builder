import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'value_input_fields.dart';
import 'scope_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class ItemPowerInputFields extends StatelessWidget {
  const ItemPowerInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedItemPowerForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedItemPowerForm> onChanged;
  Widget _reference(
    String label,
    ExpressionReferenceInput value,
    RecordKind kind,
    ValueChanged<ExpressionReferenceInput> change,
  ) => DraftRecordChoiceField(
    changes: changes,
    draft: draft,
    kind: kind,
    label: label,
    record: value.record,
    universe: value.universe,
    disabled: disabled || form.correctionTarget != null,
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
      if (form.correctionTarget != null)
        const Text(
          'Corrections retain the item, holder property, power property, represented context and authored calendar. Explain the change in the rationale.',
        ),
      _reference(
        'Item',
        form.item,
        RecordKind.entity,
        (v) => onChanged(form.copyWith(item: v)),
      ),
      _reference(
        'Holder property',
        form.holderPredicate,
        RecordKind.property,
        (v) => onChanged(form.copyWith(holderPredicate: v)),
      ),
      const Text(
        'The holder property must be single-valued and contain an entity reference. Location and ownership do not establish possession.',
      ),
      _reference(
        'Power property',
        form.powerPredicate,
        RecordKind.property,
        (v) => onChanged(form.copyWith(powerPredicate: v)),
      ),
      ValueInputFields(
        input: form.value,
        changes: changes,
        draft: draft,
        original: form.original?.value,
        disabled: disabled,
        onChanged: (v) => onChanged(form.copyWith(value: v)),
        label: 'Power value',
      ),
      ExpansionTile(
        title: const Text('Item power scope'),
        children: [
          ScopeInputFields(
            input: form.scope,
            explicitWorldScope: true,
            contextReadOnly: form.correctionTarget != null,
            changes: changes,
            draft: draft,
            disabled: disabled,
            onChanged: (v) => onChanged(form.copyWith(scope: v)),
          ),
        ],
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
        decoration: const InputDecoration(labelText: 'Item power validity'),
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
