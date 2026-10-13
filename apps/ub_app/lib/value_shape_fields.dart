import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'saved_changes.dart';

class SubjectTypeFields extends StatelessWidget {
  const SubjectTypeFields({
    super.key,
    required this.changes,
    required this.draft,
    required this.values,
    required this.disabled,
    required this.onChanged,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final List<String> values;
  final bool disabled;
  final ValueChanged<List<String>> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Subject types (empty means no type restriction)'),
      for (var i = 0; i < values.length; i++)
        Column(
          children: [
            DraftRecordChoiceField(
              changes: changes,
              draft: draft,
              kind: RecordKind.entityType,
              label: 'Subject type ${i + 1}',
              record: values[i],
              universe: changes.scope.universe.value,
              disabled: disabled,
              onChanged: (ref) {
                final rows = [...values];
                rows[i] = ref.record.value;
                onChanged(rows);
              },
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: disabled || i == 0
                      ? null
                      : () {
                          final rows = [...values];
                          final value = rows.removeAt(i);
                          rows.insert(i - 1, value);
                          onChanged(rows);
                        },
                  child: const Text('Move earlier'),
                ),
                TextButton(
                  onPressed: disabled
                      ? null
                      : () {
                          final rows = [...values]..removeAt(i);
                          onChanged(rows);
                        },
                  child: const Text('Remove type'),
                ),
              ],
            ),
          ],
        ),
      TextButton(
        onPressed: disabled ? null : () => onChanged([...values, '']),
        child: const Text('Add subject type'),
      ),
    ],
  );
}

class ValueShapeFields extends StatelessWidget {
  const ValueShapeFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final ValueShapeInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<ValueShapeInput> onChanged;
  void _change({
    String? kind,
    String? unit,
    String? definition,
    List<String>? types,
    ValueShapeInput? item,
  }) => onChanged(
    ValueShapeInput(
      kind: kind ?? input.kind,
      unit: unit ?? input.unit,
      definition: definition ?? input.definition,
      subjectTypes: types ?? input.subjectTypes,
      item: item ?? input.item,
    ),
  );
  String _record(String value) {
    try {
      final prefix = input.kind == 'quantity' || input.kind == 'range'
          ? UnitId.prefix
          : ValueDefinitionId.prefix;
      if (prefix == UnitId.prefix) {
        UnitId.parse(value);
      } else {
        ValueDefinitionId.parse(value);
      }
      return '${RecordId.prefix}${value.substring(prefix.length)}';
    } on FormatException {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(input.kind),
            initialValue: input.kind,
            decoration: const InputDecoration(labelText: 'Value shape'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Choose a shape')),
              for (final kind in [
                ...SimpleShapeKind.values.map((k) => k.name),
                'quantity',
                'range',
                'entity_ref',
                'enum',
                'structured',
                'sequence',
              ])
                DropdownMenuItem(
                  value: kind,
                  child: Text(kind.replaceAll('_', ' ')),
                ),
            ],
            onChanged: disabled
                ? null
                : (kind) => _change(
                    kind: kind,
                    item: kind == 'sequence'
                        ? input.item ?? ValueShapeInput()
                        : null,
                  ),
          ),
          if (input.kind == 'quantity' || input.kind == 'range') ...[
            DraftRecordChoiceField(
              changes: changes,
              draft: draft,
              kind: RecordKind.unit,
              label: 'Unit',
              record: _record(input.unit),
              universe: changes.scope.universe.value,
              disabled: disabled,
              onChanged: (ref) => _change(
                unit:
                    '${UnitId.prefix}${ref.record.value.substring(RecordId.prefix.length)}',
              ),
            ),
            if (input.kind == 'range')
              TextButton(
                onPressed: disabled ? null : () => _change(unit: ''),
                child: const Text('Use no unit'),
              ),
          ],
          if (input.kind == 'enum' || input.kind == 'structured')
            DraftRecordChoiceField(
              changes: changes,
              draft: draft,
              kind: RecordKind.valueDefinition,
              label: 'Value definition',
              record: _record(input.definition),
              universe: changes.scope.universe.value,
              disabled: disabled,
              onChanged: (ref) => _change(
                definition:
                    '${ValueDefinitionId.prefix}${ref.record.value.substring(RecordId.prefix.length)}',
              ),
            ),
          if (input.kind == 'entity_ref')
            SubjectTypeFields(
              changes: changes,
              draft: draft,
              values: input.subjectTypes,
              disabled: disabled,
              onChanged: (types) => _change(types: types),
            ),
          if (input.kind == 'sequence')
            ValueShapeFields(
              key: const ValueKey('item shape'),
              input: input.item ?? ValueShapeInput(),
              changes: changes,
              draft: draft,
              disabled: disabled,
              onChanged: (item) => _change(item: item),
            ),
        ],
      ),
    ),
  );
}
