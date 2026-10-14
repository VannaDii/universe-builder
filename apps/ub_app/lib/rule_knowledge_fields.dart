import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';

class RuleKnowledgeFields extends StatelessWidget {
  const RuleKnowledgeFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final RuleKnowledgeInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<RuleKnowledgeInput> onChanged;
  Widget _reference(
    String label,
    RecordKind? kind,
    ExpressionReferenceInput value,
    ValueChanged<ExpressionReferenceInput> change,
  ) => DraftRecordChoiceField(
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
      SwitchListTile(
        title: const Text('Knowledge acquisition policy'),
        value: input.policyEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(input.copyWith(policyEnabled: v)),
      ),
      if (input.policyEnabled) ...[
        const Text(
          'Choose whether knowledge is established by the author or requires the existing justification checks. Belief, suspicion, rejection and memory remain distinct from knowledge.',
        ),
        _reference(
          'Policy context',
          RecordKind.representedContext,
          input.policyContext,
          (v) => onChanged(input.copyWith(policyContext: v)),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('mode', input.mode)),
          initialValue: input.mode.isEmpty ? null : input.mode,
          decoration: const InputDecoration(labelText: 'Knowledge mode'),
          items: [
            const DropdownMenuItem(
              value: 'author_established',
              child: Text('Author established'),
            ),
            const DropdownMenuItem(
              value: 'justified',
              child: Text('Justified'),
            ),
            if (input.mode.isNotEmpty &&
                !{'author_established', 'justified'}.contains(input.mode))
              DropdownMenuItem(
                value: input.mode,
                child: Text('Unfinished mode: ${input.mode}'),
              ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) onChanged(input.copyWith(mode: v));
                },
        ),
        const Text(
          'Use a separate executable physical-constraint rule with always-block policy, whole-universe applicability, unspecified validity, literal true and only knowledge.acquisition.v1. Subject types and target predicates must be empty.',
        ),
      ],
      SwitchListTile(
        title: const Text('Scoped knowledge boundary'),
        value: input.boundaryEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(input.copyWith(boundaryEnabled: v)),
      ),
      if (input.boundaryEnabled) ...[
        const Text(
          'A scoped restriction on a holder knowing this proposition. Absence of knowledge is not refutation of the proposition.',
        ),
        _reference(
          'Knowledge holder',
          null,
          input.holder,
          (v) => onChanged(input.copyWith(holder: v)),
        ),
        _reference(
          'Boundary proposition',
          RecordKind.proposition,
          input.proposition,
          (v) => onChanged(input.copyWith(proposition: v)),
        ),
        _reference(
          'Boundary context',
          RecordKind.representedContext,
          input.boundaryContext,
          (v) => onChanged(input.copyWith(boundaryContext: v)),
        ),
        const Text(
          'Use a separate executable physical-constraint rule with always-block policy, explicit universe/world applicability, a calendar interval, literal true and only knowledge.boundaries.v1. Subject types and target predicates must be empty.',
        ),
      ],
    ],
  );
}
