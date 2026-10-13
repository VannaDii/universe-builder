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

  Widget _text(String label, String value, ValueChanged<String> change) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextFormField(
          key: ValueKey(label),
          initialValue: value,
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
  ) => DropdownButtonFormField<String>(
    key: ValueKey((label, selected)),
    initialValue: selected,
    decoration: InputDecoration(labelText: label),
    items: options.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: disabled ? null : (value) => change(value!),
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
      if (bound.kind == 'approximate') ...[
        _choice('$label uncertainty type', bound.uncertaintyKind, {
          'integer': 'Integer',
          'decimal': 'Decimal',
          'rational': 'Rational',
        }, (kind) => change(bound.copyWith(uncertaintyKind: kind))),
        _text(
          '$label uncertainty ${bound.uncertaintyKind == 'rational' ? 'numerator' : 'amount'}',
          bound.uncertainty,
          (value) => change(bound.copyWith(uncertainty: value)),
        ),
        if (bound.uncertaintyKind == 'rational')
          _text(
            '$label uncertainty denominator',
            bound.denominator,
            (value) => change(bound.copyWith(denominator: value)),
          ),
        _text(
          '$label uncertainty unit ID (optional)',
          bound.unit,
          (value) => change(bound.copyWith(unit: value)),
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
        'interval': 'Interval',
        'calendar_interval': 'Interval in a calendar',
        'persistent': 'From a bound until changed',
      }, (kind) => onChanged(input.copyWith(kind: kind))),
      if (input.kind == 'instant' || input.kind == 'calendar_interval')
        _text(
          'Calendar ID',
          input.calendar,
          (value) => onChanged(input.copyWith(calendar: value)),
        ),
      const Text(
        'Enter time values in the authored calendar’s notation. Values are retained exactly.',
      ),
      if (input.kind == 'instant')
        _text(
          'At value',
          input.start.value,
          (value) => onChanged(
            input.copyWith(start: input.start.copyWith(value: value)),
          ),
        )
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
