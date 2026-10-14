import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'scope_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class RuleConstraintFields extends StatelessWidget {
  const RuleConstraintFields({
    super.key,
    required this.input,
    required this.originalCardinality,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final RuleConstraintInput input;
  final RelationCardinality? originalCardinality;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<RuleConstraintInput> onChanged;
  Widget _text(
    String key,
    String label,
    String value,
    ValueChanged<String> change,
  ) => TextFormField(
    key: ValueKey(key),
    initialValue: value,
    enabled: !disabled,
    decoration: InputDecoration(labelText: label),
    onChanged: change,
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        title: const Text('Relation cardinality contract'),
        value: input.cardinalityEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(input.copyWith(cardinalityEnabled: v)),
      ),
      if (input.cardinalityEnabled) ...[
        const Text(
          'Limit a counted role across relation instances in an authored scope and period. This is separate from a relation definition’s local role multiplicity.',
        ),
        DraftRecordChoiceField(
          changes: changes,
          draft: draft,
          kind: RecordKind.relation,
          label: 'Counted relation',
          record: input.relation.record,
          universe: input.relation.universe,
          disabled: disabled,
          onChanged: (ref) => onChanged(
            input.copyWith(
              relation: ExpressionReferenceInput(
                record: ref.record.value,
                universe: ref.universe?.value ?? '',
              ),
            ),
          ),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('grouping', input.grouping)),
          initialValue: input.grouping.isEmpty ? null : input.grouping,
          decoration: const InputDecoration(labelText: 'Group instances by'),
          items: [
            const DropdownMenuItem(value: 'subject', child: Text('Subject')),
            const DropdownMenuItem(
              value: 'role',
              child: Text('Participant role'),
            ),
            if (input.grouping.isNotEmpty &&
                !{'subject', 'role'}.contains(input.grouping))
              DropdownMenuItem(
                value: input.grouping,
                child: Text('Unfinished grouping: ${input.grouping}'),
              ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) onChanged(input.copyWith(grouping: v));
                },
        ),
        if (input.grouping == 'role')
          _text(
            'group-role',
            'Grouping role',
            input.groupingRole,
            (v) => onChanged(input.copyWith(groupingRole: v)),
          ),
        _text(
          'counted-role',
          'Counted role',
          input.countedRole,
          (v) => onChanged(input.copyWith(countedRole: v)),
        ),
        _text(
          'maximum',
          'Exact maximum (0–4294967295)',
          input.maximum,
          (v) => onChanged(input.copyWith(maximum: v)),
        ),
        ExpansionTile(
          title: const Text('Cardinality scope'),
          children: [
            ScopeInputFields(
              input: input.scope,
              changes: changes,
              draft: draft,
              disabled: disabled,
              onChanged: (v) => onChanged(input.copyWith(scope: v)),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('cardinality-validity', input.validity.kind)),
          initialValue:
              {
                'unknown',
                'unspecified',
                'condition_dependent',
              }.contains(input.validity.kind)
              ? input.validity.kind
              : 'temporal',
          decoration: const InputDecoration(labelText: 'Cardinality validity'),
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
                      input.copyWith(
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
        }.contains(input.validity.kind))
          TemporalValidityFields(
            input: input.validity,
            originalAmounts: temporalOriginalAmounts(
              originalCardinality?.validity,
            ),
            changes: changes,
            draft: draft,
            disabled: disabled,
            onChanged: (v) => onChanged(input.copyWith(validity: v)),
          ),
        const Text(
          'Use a separate executable physical-constraint rule with always-block policy, a whole-universe wrapper, unspecified wrapper validity, literal true and only relations.cardinality.v1. Scope and time belong to this contract.',
        ),
      ],
      SwitchListTile(
        title: const Text('Channel chronology contract'),
        value: input.chronologyEnabled,
        onChanged: disabled
            ? null
            : (v) => onChanged(input.copyWith(chronologyEnabled: v)),
      ),
      if (input.chronologyEnabled) ...[
        _text(
          'channel',
          'Authored channel',
          input.channel,
          (v) => onChanged(input.copyWith(channel: v)),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('forward', input.forwardOnly)),
          initialValue: input.forwardOnly?.toString(),
          decoration: const InputDecoration(labelText: 'Forward-only delivery'),
          items: const [
            DropdownMenuItem(value: 'true', child: Text('Forward only')),
            DropdownMenuItem(
              value: 'false',
              child: Text('Either temporal direction'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) {
                    onChanged(input.copyWith(forwardOnly: v == 'true'));
                  }
                },
        ),
        SwitchListTile(
          title: const Text('Include minimum delay'),
          value: input.minimumEnabled,
          onChanged: disabled
              ? null
              : (v) => onChanged(input.copyWith(minimumEnabled: v)),
        ),
        if (input.minimumEnabled)
          _text(
            'minimum-delay',
            'Exact minimum delay in clock ticks',
            input.minimumDelay,
            (v) => onChanged(input.copyWith(minimumDelay: v)),
          ),
        SwitchListTile(
          title: const Text('Include maximum delay'),
          value: input.maximumEnabled,
          onChanged: disabled
              ? null
              : (v) => onChanged(input.copyWith(maximumEnabled: v)),
        ),
        if (input.maximumEnabled)
          _text(
            'maximum-delay',
            'Exact maximum delay in clock ticks',
            input.maximumDelay,
            (v) => onChanged(input.copyWith(maximumDelay: v)),
          ),
        const Text(
          'Delay bounds are inclusive in the same clock. No clock conversion is inferred. Use a separate executable physical-constraint rule with always-block policy, whole-universe applicability, unspecified validity, literal true and only communications.chronology.v1. Subject types and target predicates must be empty.',
        ),
      ],
    ],
  );
}
