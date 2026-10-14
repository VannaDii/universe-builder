import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';
import 'evidence_basis_fields.dart';

class ObservationInputFields extends StatelessWidget {
  const ObservationInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedObservationForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedObservationForm> onChanged;
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
        'Observer',
        form.observer,
        (v) => onChanged(form.copyWith(observer: v)),
        kind: RecordKind.entity,
      ),
      _reference(
        'Observed record',
        form.observed,
        (v) => onChanged(form.copyWith(observed: v)),
      ),
      DropdownButtonFormField<bool>(
        key: ValueKey(('sensory-access', form.sensoryAccess)),
        initialValue: form.sensoryAccess,
        decoration: const InputDecoration(labelText: 'Sensory access'),
        items: const [
          DropdownMenuItem(value: true, child: Text('Had sensory access')),
          DropdownMenuItem(
            value: false,
            child: Text('Did not have sensory access'),
          ),
        ],
        onChanged: disabled
            ? null
            : (v) {
                if (v != null) onChanged(form.copyWith(sensoryAccess: v));
              },
      ),
      const Text('Observation time'),
      TemporalValidityFields(
        input: form.time,
        expressionOnly: true,
        originalAmounts: temporalOriginalAmounts(
          form.original == null ? null : InstantValidity(form.original!.time),
        ),
        changes: changes,
        draft: draft,
        disabled: disabled,
        onChanged: (v) => onChanged(form.copyWith(time: v)),
      ),
      SwitchListTile(
        title: const Text('Include an interpretation'),
        value: form.interpretationEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(form.copyWith(interpretationEnabled: v)),
      ),
      if (form.interpretationEnabled)
        _reference(
          'Interpretation',
          form.interpretation,
          (v) => onChanged(form.copyWith(interpretation: v)),
        ),
      EvidenceBasisFields(
        input: form.basis,
        original: form.original?.basis ?? const AuthorDecisionBasis(''),
        changes: changes,
        draft: draft,
        disabled: disabled,
        onChanged: (v) => onChanged(form.copyWith(basis: v)),
      ),
    ],
  );
}
