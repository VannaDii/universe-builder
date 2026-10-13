import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'unit_reference_field.dart';

import 'value_input_fields.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';

class TemporalValidityFields extends StatelessWidget {
  const TemporalValidityFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    this.expressionOnly = false,
    this.originalAmounts = const {},
  });
  final TemporalValidityInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final bool expressionOnly;
  final Map<String, DomainValue> originalAmounts;
  final ValueChanged<TemporalValidityInput> onChanged;

  Widget _text(
    String label,
    String value,
    ValueChanged<String> change, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      key: ValueKey(label),
      initialValue: value,
      maxLines: maxLines,
      enabled: !disabled,
      decoration: InputDecoration(labelText: label),
      onChanged: change,
    ),
  );
  Widget _choice(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey((label, selected)),
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: disabled ? null : (value) => change(value!),
    ),
  );
  Widget _bound(
    String label,
    TemporalBoundInput bound,
    ValueChanged<TemporalBoundInput> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _choice('$label bound', bound.kind, {
        if (bound.kind == 'retain') 'retain': 'Keep original bound',
        'exact': 'Exact',
        'unknown': 'Unknown',
        'unbounded': 'Unbounded',
        'uncertain': 'Bounded uncertainty',
        'approximate': 'Approximate',
      }, (kind) => change(bound.copyWith(kind: kind))),
      if (['exact', 'uncertain', 'approximate'].contains(bound.kind))
        _text(
          '$label ${bound.kind == 'uncertain' ? 'lower value' : 'value'}',
          bound.value,
          (value) => change(bound.copyWith(value: value)),
        ),
      if (bound.kind == 'uncertain')
        _text(
          '$label upper value',
          bound.upper,
          (value) => change(bound.copyWith(upper: value)),
        ),
      if (bound.kind == 'approximate')
        _amount('$label uncertainty', bound, change),
    ],
  );
  Widget _amount(
    String label,
    TemporalBoundInput amount,
    ValueChanged<TemporalBoundInput> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _choice('$label type', amount.uncertaintyKind, {
        if (amount.uncertaintyKind == 'retain')
          'retain': 'Keep original exact amount',
        'typed': 'Nested typed value',
        'text': 'Text',
        'boolean': 'Boolean',
        'integer': 'Integer',
        'decimal': 'Decimal',
        'rational': 'Rational',
      }, (kind) => change(amount.copyWith(uncertaintyKind: kind))),
      if (amount.uncertaintyKind == 'typed')
        ValueInputFields(
          key: ValueKey(('amount', label)),
          changes: changes,
          draft: draft,
          input: amount.amount ?? const QualifierInput(),
          original: originalAmounts[label],
          disabled: disabled,
          label: label,
          onChanged: (input) => change(amount.copyWith(amount: input)),
        )
      else if (amount.uncertaintyKind != 'retain') ...[
        if (amount.uncertaintyKind == 'boolean')
          _choice('$label boolean value', amount.uncertainty, {
            '': 'Choose true or false',
            'true': 'True',
            'false': 'False',
            if (!['', 'true', 'false'].contains(amount.uncertainty))
              amount.uncertainty: 'Pending input: ${amount.uncertainty}',
          }, (value) => change(amount.copyWith(uncertainty: value)))
        else
          _text(
            '$label ${amount.uncertaintyKind == 'rational' ? 'numerator' : 'amount'}',
            amount.uncertainty,
            (value) => change(amount.copyWith(uncertainty: value)),
            maxLines: amount.uncertaintyKind == 'text' ? 4 : 1,
          ),
        if (amount.uncertaintyKind == 'rational')
          _text(
            '$label denominator',
            amount.denominator,
            (value) => change(amount.copyWith(denominator: value)),
          ),
        if ([
              'integer',
              'decimal',
              'rational',
            ].contains(amount.uncertaintyKind) ||
            amount.unit.isNotEmpty)
          UnitReferenceField(
            changes: changes,
            draft: draft,
            unit: amount.unit,
            disabled: disabled,
            label: '$label unit',
            onChanged: (value) => change(amount.copyWith(unit: value)),
          ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _choice(
        expressionOnly ? 'Temporal expression' : 'Temporal validity',
        input.kind,
        {
          'instant': 'At an exact time',
          'instant_interval': 'At a time interval',
          'instant_approximate': 'At an approximate time',
          'instant_duration': 'Duration expression',
          'instant_relative': 'At a relative time',
          'instant_unspecified': 'Unspecified time expression',
          if (!expressionOnly) 'interval': 'Interval',
          if (!expressionOnly) 'calendar_interval': 'Interval in a calendar',
          if (!expressionOnly) 'persistent': 'From a bound until changed',
        },
        (kind) => onChanged(input.copyWith(kind: kind)),
      ),
      if ((input.kind.startsWith('instant') &&
              input.kind != 'instant_unspecified') ||
          input.kind == 'calendar_interval')
        _CalendarReferenceField(
          changes: changes,
          draft: draft,
          calendar: input.calendar,
          disabled: disabled,
          onChanged: (value) => onChanged(input.copyWith(calendar: value)),
        ),
      const Text(
        'Enter time values in the authored calendar’s notation. Values are retained exactly.',
      ),
      if (input.kind == 'instant' || input.kind == 'instant_approximate') ...[
        _text(
          'At value',
          input.start.value,
          (value) => onChanged(
            input.copyWith(start: input.start.copyWith(value: value)),
          ),
        ),
        if (input.kind == 'instant_approximate')
          _amount(
            'Time uncertainty',
            input.start,
            (amount) => onChanged(input.copyWith(start: amount)),
          ),
      ] else if (input.kind == 'instant_duration')
        _amount(
          'Duration',
          input.start,
          (amount) => onChanged(input.copyWith(start: amount)),
        )
      else if (input.kind == 'instant_relative') ...[
        _choice('Temporal relation', input.relation, {
          '': 'Choose a relation',
          'before': 'Before',
          'after': 'After',
          'during': 'During',
          'overlaps': 'Overlaps',
          'simultaneous': 'Simultaneous',
        }, (relation) => onChanged(input.copyWith(relation: relation))),
        _text(
          'Target universe ID (optional)',
          input.targetUniverse,
          (value) => onChanged(input.copyWith(targetUniverse: value)),
        ),
        _text(
          'Target record ID',
          input.targetRecord,
          (value) => onChanged(input.copyWith(targetRecord: value)),
        ),
      ] else if (input.kind == 'instant_unspecified')
        const Text('The time expression is explicitly unspecified.')
      else ...[
        _bound(
          'Start',
          input.start,
          (bound) => onChanged(input.copyWith(start: bound)),
        ),
        if (input.kind != 'persistent')
          _bound(
            'End',
            input.end,
            (bound) => onChanged(input.copyWith(end: bound)),
          ),
      ],
    ],
  );
}

/// Keep the raw reference editable when a recovered ID is incomplete.
class _CalendarReferenceField extends StatefulWidget {
  const _CalendarReferenceField({
    required this.changes,
    required this.draft,
    required this.calendar,
    required this.disabled,
    required this.onChanged,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final String calendar;
  final bool disabled;
  final ValueChanged<String> onChanged;
  @override
  State<_CalendarReferenceField> createState() =>
      _CalendarReferenceFieldState();
}

class _CalendarReferenceFieldState extends State<_CalendarReferenceField> {
  late final TextEditingController _calendar;
  @override
  void initState() {
    super.initState();
    _calendar = TextEditingController(text: widget.calendar);
  }

  @override
  void didUpdateWidget(_CalendarReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_calendar.text != widget.calendar) _calendar.text = widget.calendar;
  }

  @override
  void dispose() {
    _calendar.dispose();
    super.dispose();
  }

  String get _record {
    try {
      return calendarChoiceRecord(widget.calendar).value;
    } on FormatException {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DraftRecordChoiceField(
        changes: widget.changes,
        draft: widget.draft,
        kind: RecordKind.calendar,
        label: 'Calendar',
        record: _record,
        universe: widget.changes.scope.universe.value,
        disabled: widget.disabled,
        onChanged: (ref) {
          _calendar.text = calendarFromChoice(ref).value;
          widget.onChanged(_calendar.text);
        },
      ),
      ExpansionTile(
        title: const Text('Advanced references'),
        children: [
          TextField(
            controller: _calendar,
            enabled: !widget.disabled,
            decoration: const InputDecoration(labelText: 'Calendar ID'),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    ],
  );
}
