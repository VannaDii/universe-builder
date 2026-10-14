import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'value_input_fields.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'connection.dart';

const expressionChoices = {
  'lit': 'Boolean literal',
  'not': 'Not',
  'all': 'All conditions',
  'any': 'Any condition',
  'claim': 'Supporting or refuting claim',
  'negated_claim': 'Negated claim',
  'existence': 'Claim existence',
  'no_opposing_evidence': 'No opposing evidence',
  'attitude': 'Knowledge or attitude',
  'compare': 'Value comparison',
  'temporal': 'Temporal relation',
  'membership': 'Collection membership',
  'cardinality': 'Collection size',
  'quantify': 'Quantified condition',
  'role_holds': 'Relation role holds',
};

class OperandInputFields extends StatelessWidget {
  const OperandInputFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.label,
  });
  final OperandInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final String label;
  final ValueChanged<OperandInput> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey(('kind', input.kind)),
        initialValue: input.kind.isEmpty ? null : input.kind,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: 'record', child: Text('Named record')),
          DropdownMenuItem(value: 'value', child: Text('Typed value')),
          DropdownMenuItem(value: 'variable', child: Text('Variable')),
          DropdownMenuItem(value: 'frame_time', child: Text('Context time')),
          DropdownMenuItem(
            value: 'event_participant',
            child: Text('Event participant role'),
          ),
          DropdownMenuItem(value: 'event_ref', child: Text('This event')),
        ],
        onChanged: disabled
            ? null
            : (kind) {
                if (kind != null && kind != input.kind) {
                  onChanged(OperandInput(kind: kind));
                }
              },
      ),
      if (input.kind == 'record')
        DraftRecordChoiceField(
          key: ValueKey(input.kind),
          changes: changes,
          draft: draft,
          kind: null,
          label: '$label record',
          record: input.reference.record,
          universe: input.reference.universe,
          disabled: disabled,
          onChanged: (ref) => onChanged(
            OperandInput(
              kind: input.kind,
              reference: ExpressionReferenceInput(
                record: ref.record.value,
                universe: ref.universe?.value ?? '',
              ),
            ),
          ),
        ),
      if (input.kind == 'variable' || input.kind == 'event_participant')
        TextFormField(
          key: ValueKey(input.kind),
          initialValue: input.name,
          enabled: !disabled,
          decoration: InputDecoration(
            labelText: input.kind == 'variable'
                ? 'Variable name'
                : 'Participant role',
          ),
          onChanged: (name) =>
              onChanged(OperandInput(kind: input.kind, name: name)),
        ),
      if (input.kind == 'value')
        ValueInputFields(
          key: ValueKey(input.kind),
          input: input.value ?? const QualifierInput(),
          changes: changes,
          draft: draft,
          original: input.original is ValueOperand
              ? (input.original as ValueOperand).value
              : null,
          disabled: disabled,
          named: false,
          label: label,
          onChanged: (value) => onChanged(
            OperandInput(
              kind: input.kind,
              value: value,
              original: input.original,
            ),
          ),
        ),
    ],
  );
}

class ExpressionInputFields extends StatefulWidget {
  const ExpressionInputFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final ExpressionInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<ExpressionInput> onChanged;
  @override
  State<ExpressionInputFields> createState() => _ExpressionInputFieldsState();
}

class _ExpressionInputFieldsState extends State<ExpressionInputFields> {
  int _layout = 0;
  RecordRef? _predicateReference;
  RecordKind? _predicateKind;
  String? _predicateName, _predicateError;
  bool _predicateBusy = false;
  ExpressionInput get input => widget.input;
  Future<void> _pickPredicate(RecordRef reference) async {
    final layout = _layout;
    setState(() {
      _predicateBusy = true;
      _predicateError = null;
    });
    try {
      final opened = await openDraftChoiceContext(widget.changes, widget.draft);
      if (reference.universe != null &&
          reference.universe != widget.changes.scope.universe) {
        throw const FormatException('Choose a definition in this universe.');
      }
      final row = await readContextRecord(
        session: widget.changes.session,
        universe: LibraryEntry(
          widget.changes.scope.universe,
          widget.changes.universe.value,
        ),
        context: opened,
        record: reference.record,
      );
      final definition = switch (row.payload) {
        PropertyRecord(:final namespace, :final key, :final labels) ||
        RelationRecord(
          :final namespace,
          :final key,
          :final labels,
        ) => (namespace, key, labels),
        _ => throw const FormatException(
          'Choose a property or relation definition.',
        ),
      };
      if (!mounted || layout != _layout) return;
      setState(() {
        _layout++;
        _predicateReference = reference;
        _predicateKind = row.identity.recordKind;
        _predicateName =
            definition.$3['en'] ??
            definition.$3.values.firstOrNull ??
            definition.$2;
      });
      widget.onChanged(
        input.copyWith(
          strings: {
            ...input.strings,
            'predicate': '${definition.$1}:${definition.$2}',
          },
        ),
      );
    } on Object {
      if (mounted && layout == _layout) {
        setState(
          () => _predicateError =
              'Could not read the selected definition. Check access and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _predicateBusy = false);
    }
  }

  Widget _predicate() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_predicateName != null) Text('Predicate: $_predicateName'),
      Text(
        'Authored predicate: ${input.strings['predicate'] ?? 'not selected'}',
      ),
      if (_predicateBusy) const LinearProgressIndicator(),
      for (final kind in [RecordKind.property, RecordKind.relation])
        DraftRecordChoiceField(
          key: ValueKey((_layout, 'predicate', kind)),
          changes: widget.changes,
          draft: widget.draft,
          kind: kind,
          label: kind == RecordKind.property
              ? 'Property predicate'
              : 'Relation predicate',
          record: _predicateKind == kind
              ? _predicateReference?.record.value ?? ''
              : '',
          universe: _predicateKind == kind
              ? _predicateReference?.universe?.value ?? ''
              : '',
          disabled: widget.disabled || _predicateBusy,
          onChanged: _pickPredicate,
        ),
      ExpansionTile(
        title: const Text('Advanced predicate key'),
        children: [_text('predicate', 'Predicate (namespace:key)')],
      ),
      if (_predicateError != null) Text(_predicateError!),
    ],
  );
  void _moveRole(int index, int destination) {
    final roles = [...input.roles], role = roles.removeAt(index);
    roles.insert(destination, role);
    _layout++;
    widget.onChanged(input.copyWith(roles: roles));
  }

  Widget _text(String key, String label) => TextFormField(
    key: ValueKey((_layout, input.kind, key)),
    initialValue: input.strings[key] ?? '',
    enabled: !widget.disabled && (key != 'predicate' || !_predicateBusy),
    decoration: InputDecoration(labelText: label),
    onChanged: (value) {
      if (key == 'predicate') {
        setState(() {
          _predicateReference = null;
          _predicateKind = null;
          _predicateName = null;
          _predicateError = null;
        });
      }
      widget.onChanged(input.copyWith(strings: {...input.strings, key: value}));
    },
  );
  Widget _choice(String key, String label, Map<String, String> choices) =>
      DropdownButtonFormField<String>(
        key: ValueKey((_layout, input.kind, key)),
        initialValue: (input.strings[key] ?? '').isEmpty
            ? null
            : input.strings[key],
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in choices.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: widget.disabled
            ? null
            : (value) {
                if (value != null) {
                  widget.onChanged(
                    input.copyWith(strings: {...input.strings, key: value}),
                  );
                }
              },
      );
  Widget _flag(String key, String label, {bool optional = false}) =>
      DropdownButtonFormField<String>(
        key: ValueKey((_layout, input.kind, key)),
        initialValue:
            input.flags[key]?.toString() ?? (optional ? 'unspecified' : null),
        decoration: InputDecoration(labelText: label),
        items: [
          if (optional)
            const DropdownMenuItem(
              value: 'unspecified',
              child: Text('Unspecified'),
            ),
          const DropdownMenuItem(value: 'true', child: Text('True')),
          const DropdownMenuItem(value: 'false', child: Text('False')),
        ],
        onChanged: widget.disabled
            ? null
            : (value) {
                if (value != null) {
                  widget.onChanged(
                    input.copyWith(
                      flags: {
                        ...input.flags,
                        key: value == 'unspecified' ? null : value == 'true',
                      },
                    ),
                  );
                }
              },
      );
  Widget _operand(String key, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: OperandInputFields(
      key: ValueKey((_layout, input.kind, key)),
      input: input.operands[key] ?? const OperandInput(),
      changes: widget.changes,
      draft: widget.draft,
      disabled: widget.disabled,
      label: label,
      onChanged: (operand) => widget.onChanged(
        input.copyWith(operands: {...input.operands, key: operand}),
      ),
    ),
  );
  Widget _optionalOperand(String key, String label) => Column(
    children: [
      SwitchListTile(
        title: Text('Include $label'),
        value: input.operands.containsKey(key),
        onChanged: widget.disabled
            ? null
            : (include) {
                final operands = {...input.operands};
                if (include) {
                  operands[key] = const OperandInput();
                } else {
                  operands.remove(key);
                }
                _layout++;
                widget.onChanged(input.copyWith(operands: operands));
              },
      ),
      if (input.operands.containsKey(key)) _operand(key, label),
    ],
  );
  Widget _reference(String key, String label, RecordKind? kind) {
    final reference = input.references[key] ?? const ExpressionReferenceInput();
    return DraftRecordChoiceField(
      key: ValueKey((_layout, input.kind, key)),
      changes: widget.changes,
      draft: widget.draft,
      kind: kind,
      label: label,
      record: reference.record,
      universe: reference.universe,
      disabled: widget.disabled,
      onChanged: (ref) => widget.onChanged(
        input.copyWith(
          references: {
            ...input.references,
            key: ExpressionReferenceInput(
              record: ref.record.value,
              universe: ref.universe?.value ?? '',
            ),
          },
        ),
      ),
    );
  }

  Widget _child(String key, String label) => ExpansionTile(
    title: Text(label),
    children: [
      ExpressionInputFields(
        key: ValueKey((_layout, input.kind, key)),
        input: input.children[key] ?? ExpressionInput(),
        changes: widget.changes,
        draft: widget.draft,
        disabled: widget.disabled,
        onChanged: (child) => widget.onChanged(
          input.copyWith(children: {...input.children, key: child}),
        ),
      ),
    ],
  );
  void _items(List<ExpressionInput> items) {
    _layout++;
    widget.onChanged(input.copyWith(items: items));
  }

  Widget _group() => Column(
    children: [
      for (var i = 0; i < input.items.length; i++)
        Card(
          child: Column(
            children: [
              ExpressionInputFields(
                key: ValueKey((_layout, i)),
                input: input.items[i],
                changes: widget.changes,
                draft: widget.draft,
                disabled: widget.disabled,
                onChanged: (child) {
                  final items = [...input.items];
                  items[i] = child;
                  widget.onChanged(input.copyWith(items: items));
                },
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: widget.disabled || i == 0
                        ? null
                        : () {
                            final items = [...input.items],
                                item = items.removeAt(i);
                            items.insert(i - 1, item);
                            _items(items);
                          },
                    child: const Text('Move earlier'),
                  ),
                  TextButton(
                    onPressed: widget.disabled || i == input.items.length - 1
                        ? null
                        : () {
                            final items = [...input.items],
                                item = items.removeAt(i);
                            items.insert(i + 1, item);
                            _items(items);
                          },
                    child: const Text('Move later'),
                  ),
                  TextButton(
                    onPressed: widget.disabled
                        ? null
                        : () => _items([...input.items]..removeAt(i)),
                    child: const Text('Remove condition'),
                  ),
                ],
              ),
            ],
          ),
        ),
      TextButton(
        onPressed: widget.disabled
            ? null
            : () => _items([...input.items, ExpressionInput()]),
        child: const Text('Add condition'),
      ),
      if (input.items.isEmpty)
        Text(
          input.kind == 'all'
              ? 'An empty all-conditions group is true.'
              : 'An empty any-condition group is false.',
        ),
    ],
  );
  Widget _roles() => Column(
    children: [
      for (var i = 0; i < input.roles.length; i++)
        Card(
          child: Column(
            children: [
              TextFormField(
                key: ValueKey((_layout, 'role', i)),
                initialValue: input.roles[i].role,
                enabled: !widget.disabled,
                decoration: const InputDecoration(labelText: 'Role'),
                onChanged: (role) {
                  final roles = [...input.roles];
                  roles[i] = ExpressionRoleInput(
                    role: role,
                    operand: roles[i].operand,
                  );
                  widget.onChanged(input.copyWith(roles: roles));
                },
              ),
              OperandInputFields(
                key: ValueKey((_layout, 'role-operand', i)),
                input: input.roles[i].operand,
                changes: widget.changes,
                draft: widget.draft,
                disabled: widget.disabled,
                label: 'Role participant',
                onChanged: (operand) {
                  final roles = [...input.roles];
                  roles[i] = ExpressionRoleInput(
                    role: roles[i].role,
                    operand: operand,
                  );
                  widget.onChanged(input.copyWith(roles: roles));
                },
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: widget.disabled || i == 0
                        ? null
                        : () => _moveRole(i, i - 1),
                    child: const Text('Move earlier'),
                  ),
                  TextButton(
                    onPressed: widget.disabled || i == input.roles.length - 1
                        ? null
                        : () => _moveRole(i, i + 1),
                    child: const Text('Move later'),
                  ),
                  TextButton(
                    onPressed: widget.disabled
                        ? null
                        : () {
                            _layout++;
                            widget.onChanged(
                              input.copyWith(
                                roles: [...input.roles]..removeAt(i),
                              ),
                            );
                          },
                    child: const Text('Remove role'),
                  ),
                ],
              ),
            ],
          ),
        ),
      TextButton(
        onPressed: widget.disabled
            ? null
            : () {
                _layout++;
                widget.onChanged(
                  input.copyWith(
                    roles: [...input.roles, const ExpressionRoleInput()],
                  ),
                );
              },
        child: const Text('Add role'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey((_layout, 'kind')),
        initialValue: input.kind.isEmpty ? null : input.kind,
        decoration: const InputDecoration(labelText: 'Condition kind'),
        items: [
          for (final item in expressionChoices.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: widget.disabled
            ? null
            : (kind) {
                if (kind != null && kind != input.kind) {
                  _layout++;
                  _predicateReference = null;
                  _predicateKind = null;
                  _predicateName = null;
                  _predicateError = null;
                  widget.onChanged(ExpressionInput(kind: kind));
                }
              },
      ),
      if (input.kind == 'lit') _flag('value', 'Literal value'),
      if (input.kind == 'not') _child('expr', 'Negated condition'),
      if (input.kind == 'all' || input.kind == 'any') _group(),
      if ({
        'claim',
        'negated_claim',
        'existence',
        'no_opposing_evidence',
        'role_holds',
      }.contains(input.kind)) ...[
        _operand('subject', 'Subject'),
        _predicate(),
        if (input.kind == 'claim')
          _choice('polarity', 'Evidence polarity', {
            for (final p in Polarity.values) p.wireName: p.wireName,
          }),
        if ({'claim', 'negated_claim', 'existence'}.contains(input.kind)) ...[
          _roles(),
          _optionalOperand('value', 'claim value'),
          _optionalOperand('context', 'represented context'),
        ],
        if (input.kind == 'no_opposing_evidence')
          _operand('context', 'Represented context'),
        if (input.kind == 'role_holds') ...[
          _text('role', 'Role'),
          _operand('participant', 'Participant'),
        ],
      ],
      if (input.kind == 'attitude') ...[
        _reference('holder', 'Knowledge holder', null),
        _reference('proposition', 'Proposition', RecordKind.proposition),
        _choice('attitude', 'Attitude', {
          for (final kind in EpistemicAttitudeKind.values) kind.name: kind.name,
        }),
      ],
      if (input.kind == 'compare' || input.kind == 'temporal') ...[
        _operand('left', 'Left operand'),
        _operand('right', 'Right operand'),
        if (input.kind == 'compare')
          _choice('op', 'Comparison', {
            for (final c in Comparator.values) c.wireName: c.wireName,
          }),
        if (input.kind == 'temporal')
          _choice('relation', 'Temporal relation', {
            for (final r in TemporalRelation.values) r.name: r.name,
          }),
      ],
      if (input.kind == 'membership') ...[
        _operand('element', 'Element'),
        _operand('collection', 'Collection'),
        _flag('complete', 'Collection completeness', optional: true),
      ],
      if (input.kind == 'cardinality') ...[
        _operand('collection', 'Collection'),
        _choice('op', 'Comparison', {
          for (final c in Comparator.values) c.wireName: c.wireName,
        }),
        ValueInputFields(
          key: ValueKey((_layout, 'count')),
          input: input.value ?? const QualifierInput(),
          changes: widget.changes,
          draft: widget.draft,
          original: input.original is CardinalityExpr
              ? (input.original as CardinalityExpr).count
              : null,
          disabled: widget.disabled,
          named: false,
          label: 'Count',
          onChanged: (value) => widget.onChanged(input.copyWith(value: value)),
        ),
        _flag('complete', 'Collection completeness', optional: true),
      ],
      if (input.kind == 'quantify') ...[
        _text('variable', 'Bound variable'),
        _operand('over', 'Collection'),
        _flag('complete', 'Collection completeness'),
        _choice('quantifier', 'Quantifier', {
          for (final q in Quantifier.values) q.wireName: q.wireName,
        }),
        _child('body', 'Quantified condition'),
      ],
    ],
  );
}
