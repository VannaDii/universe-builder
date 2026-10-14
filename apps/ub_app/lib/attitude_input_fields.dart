import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'evidence_basis_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class AttitudeInputFields extends StatelessWidget {
  const AttitudeInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedAttitudeForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedAttitudeForm> onChanged;
  Widget _reference(
    String label,
    ExpressionReferenceInput value,
    ValueChanged<ExpressionReferenceInput> change, {
    RecordKind? kind,
    bool readOnly = false,
  }) => DraftRecordChoiceField(
    changes: changes,
    draft: draft,
    kind: kind,
    label: label,
    record: value.record,
    universe: value.universe,
    disabled: disabled || readOnly,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  void _acquisition(KnowledgeAcquisitionInput value) =>
      onChanged(form.copyWith(acquisition: value));
  @override
  Widget build(BuildContext context) {
    final a = form.acquisition;
    final fixed = disabled || form.correctionTarget != null;
    final knowledgeFixed =
        disabled || (form.correctionTarget != null && form.attitude == 'knows');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (form.correctionTarget != null)
          Text(
            form.attitude == 'knows'
                ? 'Knowledge corrections change duration only. Holder, claim, certainty, basis and acquisition remain fixed.'
                : 'Corrections retain holder, stance, basis and acquisition. A different claim must change its value only; subject, property, roles, polarity and truth context remain fixed. Existing checks retain an authored calendar.',
          ),
        _reference(
          'Holder',
          form.holder,
          (v) => onChanged(form.copyWith(holder: v)),
          readOnly: form.correctionTarget != null,
        ),
        _reference(
          'Proposition',
          form.proposition,
          (v) => onChanged(form.copyWith(proposition: v)),
          kind: RecordKind.proposition,
          readOnly: knowledgeFixed,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('attitude', form.attitude)),
          initialValue: form.attitude.isEmpty ? null : form.attitude,
          decoration: const InputDecoration(labelText: 'Attitude'),
          items: const [
            DropdownMenuItem(value: 'believes', child: Text('Believes')),
            DropdownMenuItem(value: 'suspects', child: Text('Suspects')),
            DropdownMenuItem(value: 'rejects', child: Text('Rejects')),
            DropdownMenuItem(value: 'remembers', child: Text('Remembers')),
            DropdownMenuItem(value: 'knows', child: Text('Knows')),
          ],
          onChanged: fixed
              ? null
              : (v) {
                  if (v != null) onChanged(form.copyWith(attitude: v));
                },
        ),
        SwitchListTile(
          title: const Text('Include a certainty description'),
          value: form.certaintyEnabled,
          onChanged: knowledgeFixed
              ? null
              : (v) => onChanged(form.copyWith(certaintyEnabled: v)),
        ),
        if (form.certaintyEnabled)
          TextFormField(
            initialValue: form.certainty,
            enabled: !knowledgeFixed,
            decoration: const InputDecoration(labelText: 'Authored certainty'),
            onChanged: (v) => onChanged(form.copyWith(certainty: v)),
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
          decoration: const InputDecoration(labelText: 'Attitude validity'),
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
        EvidenceBasisFields(
          input: form.basis,
          original: form.original?.basis ?? const AuthorDecisionBasis(''),
          disabled: fixed,
          changes: changes,
          draft: draft,
          onChanged: (v) => onChanged(form.copyWith(basis: v)),
        ),
        SwitchListTile(
          title: const Text('Declare knowledge acquisition'),
          value: a.enabled,
          onChanged: fixed ? null : (v) => _acquisition(a.copyWith(enabled: v)),
        ),
        if (a.enabled) ...[
          const Text(
            'Declare how this holder acquired knowledge. The existing policy checks truth, receipt and interpretation. Omitting a world keeps universe-wide evidence.',
          ),
          _reference(
            'Truth context',
            a.truthContext,
            (v) => _acquisition(a.copyWith(truthContext: v)),
            readOnly: form.correctionTarget != null,
            kind: RecordKind.representedContext,
          ),
          const Text('Acquisition time'),
          TemporalValidityFields(
            input: a.time,
            expressionOnly: true,
            originalAmounts: temporalOriginalAmounts(
              form.original?.acquisition == null
                  ? null
                  : InstantValidity(form.original!.acquisition!.time),
            ),
            changes: changes,
            draft: draft,
            disabled: fixed,
            onChanged: (v) => _acquisition(a.copyWith(time: v)),
          ),
          SwitchListTile(
            title: const Text('Limit acquisition to a world'),
            value: a.worldEnabled,
            onChanged: fixed
                ? null
                : (v) => _acquisition(a.copyWith(worldEnabled: v)),
          ),
          if (a.worldEnabled)
            _reference(
              'Acquisition world',
              a.world,
              (v) => _acquisition(a.copyWith(world: v)),
              readOnly: form.correctionTarget != null,
              kind: RecordKind.world,
            ),
          DropdownButtonFormField<String>(
            key: ValueKey(('acquisition-basis', a.basis)),
            initialValue: a.basis.isEmpty ? null : a.basis,
            decoration: const InputDecoration(labelText: 'Acquisition basis'),
            items: const [
              DropdownMenuItem(
                value: 'author_established',
                child: Text('Author established'),
              ),
              DropdownMenuItem(
                value: 'communication_receipt',
                child: Text('Communication receipt'),
              ),
            ],
            onChanged: fixed
                ? null
                : (v) {
                    if (v != null) _acquisition(a.copyWith(basis: v));
                  },
          ),
          if (a.basis == 'communication_receipt') ...[
            _reference(
              'Received communication',
              a.communication,
              (v) => _acquisition(a.copyWith(communication: v)),
              readOnly: form.correctionTarget != null,
              kind: RecordKind.communication,
            ),
            SwitchListTile(
              title: const Text('Include an interpretation'),
              value: a.interpretationEnabled,
              onChanged: fixed
                  ? null
                  : (v) => _acquisition(a.copyWith(interpretationEnabled: v)),
            ),
            if (a.interpretationEnabled)
              _reference(
                'Interpretation',
                a.interpretation,
                (v) => _acquisition(a.copyWith(interpretation: v)),

                readOnly: form.correctionTarget != null,
              ),
          ],
        ],
      ],
    );
  }
}
