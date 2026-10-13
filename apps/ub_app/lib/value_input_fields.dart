import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'unit_reference_field.dart';

import 'qualifier_draft.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';
import 'record_fields.dart';

/// Recoverable typed value controls shared by qualifiers and authored amounts.
class ValueInputFields extends StatefulWidget {
  const ValueInputFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.original,
    required this.disabled,
    required this.onChanged,
    this.named = false,
    this.label,
  });
  final QualifierInput input;
  final DomainValue? original;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled, named;
  final String? label;
  final ValueChanged<QualifierInput> onChanged;
  @override
  State<ValueInputFields> createState() => _ValueInputFieldsState();
}

class _ValueInputFieldsState extends State<ValueInputFields> {
  late _QualifierFields _fields;
  bool get _disabled => widget.disabled;
  @override
  void initState() {
    super.initState();
    _fields = _QualifierFields(widget.input);
  }

  @override
  void didUpdateWidget(ValueInputFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.input.toWire().toText() != _fields.form.toWire().toText()) {
      _fields.dispose();
      _fields = _QualifierFields(widget.input);
    }
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  void _changed() => widget.onChanged(_fields.form);
  Widget _field(
    TextEditingController controller,
    String label, {
    int? maxLines,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      enabled: !_disabled,
      decoration: InputDecoration(labelText: label),
      maxLines: maxLines ?? 1,
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(BuildContext context) => _qualifierRow(
    [_fields],
    0,
    {
      if (_fields.originalKey != null && widget.original != null)
        _fields.originalKey!: widget.original!,
    },
    named: widget.named,
    fixed: true,
    label: widget.label,
  );
  Widget _qualifierRow(
    List<_QualifierFields> rows,
    int index,
    Map<String, DomainValue> original, {
    bool named = true,
    bool fixed = false,
    String? label,
  }) {
    final fields = rows[index];
    final retained = original[fields.originalKey];
    return Card(
      key: ValueKey(fields),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (named)
              _field(fields.name, 'Qualifier name')
            else
              Text(label ?? 'Item ${index + 1}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey((fields, fields.kind)),
              initialValue: fields.kind,
              decoration: InputDecoration(
                labelText: label == null
                    ? 'Qualifier value type'
                    : '$label type',
              ),
              items: [
                if (retained != null || fields.kind == 'retain')
                  const DropdownMenuItem(
                    value: 'retain',
                    child: Text('Keep original exact value'),
                  ),
                for (final choice in {
                  'text': 'Text',
                  'boolean': 'Boolean',
                  'integer': 'Integer',
                  'decimal': 'Decimal',
                  'rational': 'Rational',
                  'entity_ref': 'Entity reference',
                  'record_ref': 'Record reference',
                  'proposition_ref': 'Proposition reference',
                  'enum': 'Enumeration',
                  'spatial_coordinates': 'Spatial coordinates',
                  'spatial_distance': 'Spatial distance',
                  'spatial_contained_in': 'Contained in',
                  'spatial_adjacent_to': 'Adjacent to',
                  'spatial_connected_to': 'Connected to',
                  'spatial_unspecified': 'Unspecified space',
                  'temporal': 'Temporal expression',
                  'range': 'Range',
                  'sequence': 'Sequence',
                  'set': 'Set',
                  'structured': 'Structured fields',
                }.entries)
                  DropdownMenuItem(
                    value: choice.key,
                    child: Text(choice.value),
                  ),
              ],
              onChanged: _disabled
                  ? null
                  : (value) {
                      setState(() {
                        fields.kind = value!;
                        if (value == 'temporal') {
                          fields.temporal ??= const TemporalValidityInput(
                            kind: 'instant',
                          );
                        }
                        if (value == 'spatial_distance') {
                          fields.lower ??= _QualifierFields(
                            const QualifierInput(),
                          );
                        }
                        if (value == 'range') {
                          fields.lower ??= _QualifierFields(
                            const QualifierInput(),
                          );
                          fields.upper ??= _QualifierFields(
                            const QualifierInput(),
                          );
                        }
                      });
                      _changed();
                    },
            ),
            if (fields.kind == 'retain')
              retained == null
                  ? const Text(
                      'Original value unavailable. Reopen the current draft fields before saving.',
                    )
                  : ExactFields(value: retained.toWire())
            else ...[
              if (fields.kind == 'spatial_distance') ...[
                _field(fields.universe, 'From universe ID (optional)'),
                _field(fields.value, 'From record ID'),
                _qualifierRow(
                  [fields.lower!],
                  0,
                  retained is SpatialValue &&
                          retained.spatial is SpatialDistance
                      ? {'amount': (retained.spatial as SpatialDistance).value}
                      : {},
                  named: false,
                  fixed: true,
                  label: 'Distance amount',
                ),
              ] else if ([
                'spatial_contained_in',
                'spatial_adjacent_to',
                'spatial_connected_to',
              ].contains(fields.kind)) ...[
                _field(fields.universe, 'Target universe ID (optional)'),
                _field(fields.value, 'Target record ID'),
              ] else if (fields.kind == 'spatial_unspecified')
                const Text('The spatial expression is explicitly unspecified.')
              else if (fields.kind == 'temporal')
                TemporalValidityFields(
                  key: ValueKey(('qualifier temporal', fields)),
                  changes: widget.changes,
                  draft: widget.draft,
                  input: fields.temporal!,
                  originalAmounts: temporalOriginalAmounts(
                    retained is TemporalValue
                        ? InstantValidity(retained.temporal)
                        : null,
                  ),
                  expressionOnly: true,
                  disabled: _disabled,
                  onChanged: (input) {
                    setState(() => fields.temporal = input);
                    _changed();
                  },
                )
              else if (fields.kind == 'range') ...[
                _qualifierRow(
                  [fields.lower!],
                  0,
                  retained is RangeValue ? {'lower': retained.lower} : {},
                  named: false,
                  fixed: true,
                  label: 'Lower bound',
                ),
                _rangeInclusion(fields, lower: true),
                _qualifierRow(
                  [fields.upper!],
                  0,
                  retained is RangeValue ? {'upper': retained.upper} : {},
                  named: false,
                  fixed: true,
                  label: 'Upper bound',
                ),
                _rangeInclusion(fields, lower: false),
              ] else if ([
                'sequence',
                'set',
                'structured',
                'spatial_coordinates',
              ].contains(fields.kind)) ...[
                if (fields.kind == 'spatial_coordinates')
                  _field(fields.value, 'Coordinate reference'),
                if (fields.kind == 'structured')
                  _definitionChoice(fields, 'Structure definition'),
                for (var c = 0; c < fields.children.length; c++)
                  _qualifierRow(
                    fields.children,
                    c,
                    qualifierChildren(retained),
                    named: fields.kind == 'structured',
                  ),
                TextButton(
                  onPressed: _disabled
                      ? null
                      : () {
                          setState(
                            () => fields.children.add(
                              _QualifierFields(const QualifierInput()),
                            ),
                          );
                          _changed();
                        },
                  child: Text(
                    fields.kind == 'structured' ? 'Add field' : 'Add item',
                  ),
                ),
              ] else if (fields.kind == 'boolean')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey((fields, fields.value.text)),
                    initialValue: fields.value.text,
                    decoration: const InputDecoration(
                      labelText: 'Boolean value',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choose true or false'),
                      ),
                      const DropdownMenuItem(
                        value: 'true',
                        child: Text('True'),
                      ),
                      const DropdownMenuItem(
                        value: 'false',
                        child: Text('False'),
                      ),
                      if (!['', 'true', 'false'].contains(fields.value.text))
                        DropdownMenuItem(
                          value: fields.value.text,
                          child: Text('Pending input: ${fields.value.text}'),
                        ),
                    ],
                    onChanged: _disabled
                        ? null
                        : (value) {
                            setState(() => fields.value.text = value!);
                            _changed();
                          },
                  ),
                )
              else if ([
                'entity_ref',
                'record_ref',
                'proposition_ref',
              ].contains(fields.kind)) ...[
                _field(fields.universe, 'Target universe ID (optional)'),
                _field(fields.value, 'Target record ID'),
              ] else if (fields.kind == 'enum') ...[
                _definitionChoice(fields, 'Enumeration definition'),
                _field(fields.value, 'Enumeration entry key'),
              ] else
                _field(
                  fields.value,
                  fields.kind == 'rational'
                      ? 'Numerator'
                      : label ?? 'Qualifier value',
                  maxLines: fields.kind == 'text' ? 4 : 1,
                ),
              if (fields.kind == 'rational')
                _field(fields.denominator, 'Denominator'),
              if ([
                    'integer',
                    'decimal',
                    'rational',
                    'range',
                    'spatial_distance',
                  ].contains(fields.kind) ||
                  fields.unit.text.isNotEmpty)
                UnitReferenceField(
                  changes: widget.changes,
                  draft: widget.draft,
                  unit: fields.unit.text,
                  disabled: _disabled,
                  label: fields.kind == 'spatial_distance'
                      ? 'Distance unit'
                      : fields.kind == 'range'
                      ? 'Range unit'
                      : 'Unit',
                  optional: fields.kind != 'spatial_distance',
                  onChanged: (unit) {
                    setState(() => fields.unit.text = unit);
                    _changed();
                  },
                ),
            ],
            if (!named && !fixed)
              Wrap(
                children: [
                  TextButton(
                    onPressed: _disabled || index == 0
                        ? null
                        : () {
                            setState(() {
                              rows.removeAt(index);
                              rows.insert(index - 1, fields);
                            });
                            _changed();
                          },
                    child: const Text('Move earlier'),
                  ),
                  TextButton(
                    onPressed: _disabled || index == rows.length - 1
                        ? null
                        : () {
                            setState(() {
                              rows.removeAt(index);
                              rows.insert(index + 1, fields);
                            });
                            _changed();
                          },
                    child: const Text('Move later'),
                  ),
                ],
              ),
            if (!fixed)
              TextButton(
                onPressed: _disabled
                    ? null
                    : () {
                        setState(() => rows.removeAt(index));
                        fields.dispose();
                        _changed();
                      },
                child: Text(
                  named ? 'Remove qualifier or field' : 'Remove item',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _definitionChoice(_QualifierFields fields, String label) {
    String record;
    try {
      record = valueDefinitionChoiceRecord(fields.definition.text).value;
    } on FormatException {
      record = '';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.valueDefinition,
          label: label,
          record: record,
          universe: widget.changes.scope.universe.value,
          disabled: _disabled,
          onChanged: (ref) {
            setState(
              () =>
                  fields.definition.text = valueDefinitionFromChoice(ref).value,
            );
            _changed();
          },
        ),
        ExpansionTile(
          title: const Text('Advanced references'),
          children: [_field(fields.definition, '$label ID')],
        ),
      ],
    );
  }

  Widget _rangeInclusion(_QualifierFields fields, {required bool lower}) {
    final value = lower ? fields.lowerInclusive : fields.upperInclusive;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey((fields, lower, value)),
        initialValue: value,
        decoration: InputDecoration(
          labelText: lower ? 'Include lower bound' : 'Include upper bound',
        ),
        items: [
          for (final entry in {
            '': 'Choose inclusion',
            'true': 'Included',
            'false': 'Excluded',
          }.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          if (!['', 'true', 'false'].contains(value))
            DropdownMenuItem(
              value: value,
              child: Text('Pending input: $value'),
            ),
        ],
        onChanged: _disabled
            ? null
            : (value) {
                setState(() {
                  if (lower) {
                    fields.lowerInclusive = value!;
                  } else {
                    fields.upperInclusive = value!;
                  }
                });
                _changed();
              },
      ),
    );
  }
}

final class _QualifierFields {
  _QualifierFields(QualifierInput form)
    : name = TextEditingController(text: form.key),
      value = TextEditingController(text: form.value),
      denominator = TextEditingController(text: form.denominator),
      unit = TextEditingController(text: form.unit),
      universe = TextEditingController(text: form.universe),
      definition = TextEditingController(text: form.definition),
      kind = form.kind,
      children = form.children.map(_QualifierFields.new).toList(),
      temporal =
          form.temporal ??
          (form.kind == 'temporal'
              ? const TemporalValidityInput(kind: 'instant')
              : null),
      lower = form.lower == null
          ? (['range', 'spatial_distance'].contains(form.kind)
                ? _QualifierFields(const QualifierInput())
                : null)
          : _QualifierFields(form.lower!),
      upper = form.upper == null
          ? (form.kind == 'range'
                ? _QualifierFields(const QualifierInput())
                : null)
          : _QualifierFields(form.upper!),
      lowerInclusive = form.lowerInclusive,
      upperInclusive = form.upperInclusive,
      originalKey = form.originalKey;
  final TextEditingController name,
      value,
      denominator,
      unit,
      universe,
      definition;
  String kind;
  final List<_QualifierFields> children;
  _QualifierFields? lower, upper;
  TemporalValidityInput? temporal;
  String lowerInclusive, upperInclusive;
  final String? originalKey;
  QualifierInput get form => QualifierInput(
    key: name.text,
    kind: kind,
    value: value.text,
    denominator: denominator.text,
    unit: unit.text,
    universe: universe.text,
    definition: definition.text,
    originalKey: originalKey,
    children: children.map((c) => c.form).toList(),
    temporal: temporal,
    lower: lower?.form,
    upper: upper?.form,
    lowerInclusive: lowerInclusive,
    upperInclusive: upperInclusive,
  );
  void dispose() {
    name.dispose();
    value.dispose();
    denominator.dispose();
    unit.dispose();
    universe.dispose();
    definition.dispose();
    for (final child in [...children, ?lower, ?upper]) {
      child.dispose();
    }
  }
}
