import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart';

class TemporalValidityFields extends StatelessWidget {
  const TemporalValidityFields({
    super.key,
    required this.input,
    required this.disabled,
    required this.onChanged,
  });
  final TemporalValidityInput input;
  final bool disabled;
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
        'text': 'Text',
        'boolean': 'Boolean',
        'integer': 'Integer',
        'decimal': 'Decimal',
        'rational': 'Rational',
      }, (kind) => change(amount.copyWith(uncertaintyKind: kind))),
      if (amount.uncertaintyKind != 'retain') ...[
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
        _text(
          '$label unit ID (numeric amounts only, optional)',
          amount.unit,
          (value) => change(amount.copyWith(unit: value)),
        ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _choice('Temporal validity', input.kind, {
        'instant': 'At an exact time',
        'instant_interval': 'At a time interval',
        'instant_approximate': 'At an approximate time',
        'instant_duration': 'Duration expression',
        'instant_relative': 'At a relative time',
        'instant_unspecified': 'Unspecified time expression',
        'interval': 'Interval',
        'calendar_interval': 'Interval in a calendar',
        'persistent': 'From a bound until changed',
      }, (kind) => onChanged(input.copyWith(kind: kind))),
      if ((input.kind.startsWith('instant') &&
              input.kind != 'instant_unspecified') ||
          input.kind == 'calendar_interval')
        _text(
          'Calendar ID',
          input.calendar,
          (value) => onChanged(input.copyWith(calendar: value)),
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
