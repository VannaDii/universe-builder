import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';

class InterpretationInputFields extends StatelessWidget {
  const InterpretationInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedInterpretationForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedInterpretationForm> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DraftRecordChoiceField(
        changes: changes,
        draft: draft,
        kind: RecordKind.epistemicAttitude,
        label: 'Published knowledge',
        record: form.target.record,
        universe: form.target.universe,
        disabled: true,
        onChanged: (_) {},
      ),
      SwitchListTile(
        title: const Text('Include an interpretation'),
        value: form.interpretationEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(form.copyWith(interpretationEnabled: v)),
      ),
      if (form.interpretationEnabled)
        DraftRecordChoiceField(
          changes: changes,
          draft: draft,
          kind: RecordKind.proposition,
          label: 'Interpretation claim',
          record: form.interpretation.record,
          universe: form.interpretation.universe,
          disabled: disabled,
          onChanged: (ref) => onChanged(
            form.copyWith(
              interpretation: ExpressionReferenceInput(
                record: ref.record.value,
                universe: ref.universe?.value ?? '',
              ),
            ),
          ),
        ),
      const Text(
        'Choose a proposition in the original acquisition truth context. Clearing the interpretation retains the current knowledge claim; existing checks may find it unsupported.',
      ),
    ],
  );
}
