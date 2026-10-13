import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

TemporalValidityInput temporalValidityInput(Validity? value) => switch (value) {
  InstantValidity(at: ExactTime(:final calendar, :final value)) =>
    TemporalValidityInput(
      kind: 'instant',
      calendar: calendar.value,
      start: TemporalBoundInput(value: value),
    ),
  InstantValidity(
    at: IntervalTime(:final calendar, :final start, :final end),
  ) =>
    TemporalValidityInput(
      kind: 'instant_interval',
      calendar: calendar.value,
      start: _input(start),
      end: _input(end),
    ),
  InstantValidity(
    at: ApproximateTime(:final calendar, :final value, :final uncertainty),
  ) =>
    TemporalValidityInput(
      kind: 'instant_approximate',
      calendar: calendar.value,
      start: _amountInput(value, uncertainty),
    ),
  InstantValidity(at: DurationTime(:final calendar, :final amount)) =>
    TemporalValidityInput(
      kind: 'instant_duration',
      calendar: calendar.value,
      start: _amountInput('', amount),
    ),
  InstantValidity(
    at: RelativeTime(:final calendar, :final relation, :final target),
  ) =>
    TemporalValidityInput(
      kind: 'instant_relative',
      calendar: calendar.value,
      relation: relation.name,
      targetUniverse: target.universe?.value ?? '',
      targetRecord: target.record.value,
    ),
  InstantValidity(at: UnspecifiedTime()) => const TemporalValidityInput(
    kind: 'instant_unspecified',
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

TemporalBoundInput _amountInput(String value, DomainValue amount) {
  final input = _approximate(value, amount);
  return input.kind == 'retain'
      ? TemporalBoundInput(value: value, uncertaintyKind: 'retain')
      : input;
}

Validity buildTemporalValidity(
  TemporalValidityInput input,
  Validity? original,
) {
  final originals = switch (original) {
    IntervalValidity(:final start, :final end) ||
    CalendarIntervalValidity(:final start, :final end) => (start, end),
    PersistentValidity(:final from) => (from, null),
    InstantValidity(at: IntervalTime(:final start, :final end)) => (start, end),
    _ => (null, null),
  };
  TemporalBound start() => _bound(input.start, originals.$1);
  TemporalBound end() => _bound(input.end, originals.$2);
  final result = switch (input.kind) {
    'instant' => InstantValidity(
      ExactTime(CalendarId.parse(input.calendar), _required(input.start.value)),
    ),
    'instant_interval' => InstantValidity(
      IntervalTime(CalendarId.parse(input.calendar), start(), end()),
    ),
    'instant_approximate' => InstantValidity(
      ApproximateTime(
        CalendarId.parse(input.calendar),
        _required(input.start.value),
        _uncertainty(
          input.start,
          original is InstantValidity && original.at is ApproximateTime
              ? (original.at as ApproximateTime).uncertainty
              : null,
        ),
      ),
    ),
    'instant_duration' => InstantValidity(
      DurationTime(
        CalendarId.parse(input.calendar),
        _uncertainty(
          input.start,
          original is InstantValidity && original.at is DurationTime
              ? (original.at as DurationTime).amount
              : null,
        ),
      ),
    ),
    'instant_relative' => InstantValidity(
      RelativeTime(
        CalendarId.parse(input.calendar),
        TemporalRelation.values.firstWhere(
          (r) => r.name == input.relation,
          orElse: () =>
              throw const FormatException('Choose the temporal relation.'),
        ),
        RecordRef(
          universe: input.targetUniverse.isEmpty
              ? null
              : UniverseId.parse(input.targetUniverse),
          record: RecordId.parse(input.targetRecord),
        ),
      ),
    ),
    'instant_unspecified' => const InstantValidity(UnspecifiedTime()),
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
    _uncertainty(
      input,
      original is ApproximateBound ? original.uncertainty : null,
    ),
  ),
  _ => throw const FormatException('Choose a temporal bound kind.'),
};
DomainValue _uncertainty(TemporalBoundInput input, [DomainValue? original]) {
  if (input.uncertaintyKind == 'retain') {
    return original ??
        (throw const FormatException('No original amount to retain.'));
  }
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
