import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

TemporalValidityInput temporalValidityInput(Validity? value) => switch (value) {
  InstantValidity(at: ExactTime(:final calendar, :final value)) =>
    TemporalValidityInput(
      kind: 'instant',
      calendar: calendar.value,
      start: TemporalBoundInput(value: value),
    ),
  IntervalValidity(:final start, :final end) => TemporalValidityInput(
    start: _input(start),
    end: _input(end),
  ),
  CalendarIntervalValidity(:final calendar, :final start, :final end) =>
    TemporalValidityInput(
      kind: 'calendar_interval',
      calendar: calendar.value,
      start: _input(start),
      end: _input(end),
    ),
  PersistentValidity(:final from) => TemporalValidityInput(
    kind: 'persistent',
    start: _input(from),
  ),
  _ => const TemporalValidityInput(),
};

TemporalBoundInput _input(TemporalBound bound) => switch (bound) {
  UnknownBound() => const TemporalBoundInput(kind: 'unknown'),
  UnboundedBound() => const TemporalBoundInput(kind: 'unbounded'),
  ExactBound(:final value) => TemporalBoundInput(value: value),
  UncertainBound(:final lower, :final upper) => TemporalBoundInput(
    kind: 'uncertain',
    value: lower,
    upper: upper,
  ),
  ApproximateBound(:final value, :final uncertainty) => _approximate(
    value,
    uncertainty,
  ),
};
TemporalBoundInput _approximate(String value, DomainValue uncertainty) {
  final unit = uncertainty is QuantityValue ? uncertainty.unit.value : '';
  final amount = uncertainty is QuantityValue ? uncertainty.value : uncertainty;
  return switch (amount) {
    IntegerValue(:final digits) => TemporalBoundInput(
      kind: 'approximate',
      value: value,
      uncertaintyKind: 'integer',
      uncertainty: digits,
      unit: unit,
    ),
    DecimalValue(:final digits) => TemporalBoundInput(
      kind: 'approximate',
      value: value,
      uncertainty: digits,
      unit: unit,
    ),
    RationalValue(:final numerator, :final denominator) => TemporalBoundInput(
      kind: 'approximate',
      value: value,
      uncertaintyKind: 'rational',
      uncertainty: numerator,
      denominator: denominator,
      unit: unit,
    ),
    _ => const TemporalBoundInput(kind: 'retain'),
  };
}

Validity buildTemporalValidity(
  TemporalValidityInput input,
  Validity? original,
) {
  final originals = switch (original) {
    IntervalValidity(:final start, :final end) ||
    CalendarIntervalValidity(:final start, :final end) => (start, end),
    PersistentValidity(:final from) => (from, null),
    _ => (null, null),
  };
  TemporalBound start() => _bound(input.start, originals.$1);
  TemporalBound end() => _bound(input.end, originals.$2);
  final result = switch (input.kind) {
    'instant' => InstantValidity(
      ExactTime(CalendarId.parse(input.calendar), _required(input.start.value)),
    ),
    'interval' => IntervalValidity(start(), end()),
    'calendar_interval' => CalendarIntervalValidity(
      CalendarId.parse(input.calendar),
      start(),
      end(),
    ),
    'persistent' => PersistentValidity(start()),
    _ => throw const FormatException('Choose a temporal validity kind.'),
  };
  if (result is InstantValidity) result.at.validate();
  return result;
}

String _required(String value) {
  if (value.trim().isEmpty) {
    throw const FormatException('Enter the temporal value.');
  }
  return value;
}

TemporalBound _bound(
  TemporalBoundInput input,
  TemporalBound? original,
) => switch (input.kind) {
  'retain' =>
    original ??
        (throw const FormatException('No original temporal bound to retain.')),
  'unknown' => const UnknownBound(),
  'unbounded' => const UnboundedBound(),
  'exact' => ExactBound(_required(input.value)),
  'uncertain' => UncertainBound(_required(input.value), _required(input.upper)),
  'approximate' => ApproximateBound(
    _required(input.value),
    _uncertainty(input),
  ),
  _ => throw const FormatException('Choose a temporal bound kind.'),
};
DomainValue _uncertainty(TemporalBoundInput input) {
  final amount = switch (input.uncertaintyKind) {
    'integer' => IntegerValue(input.uncertainty),
    'decimal' => DecimalValue(input.uncertainty),
    'rational' => RationalValue(input.uncertainty, input.denominator),
    _ => throw const FormatException('Choose an uncertainty number type.'),
  };
  amount.validate();
  return input.unit.isEmpty
      ? amount
      : QuantityValue(amount, UnitId.parse(input.unit));
}
