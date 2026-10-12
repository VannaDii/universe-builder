import 'dart:convert';

import 'package:ub_domain/ub_domain.dart';

final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
final _digits = RegExp(r'^[+-]?[0-9]+$');
BigInt? _integer(String value) {
  if (_digits.stringMatch(value) != value) return null;
  final n = BigInt.tryParse(value, radix: 10);
  return n == null || n < _min || n > _max ? null : n;
}

BigInt? _product(BigInt a, BigInt b) {
  final n = a * b;
  return n < _min || n > _max ? null : n;
}

typedef _Number = ({BigInt numerator, BigInt denominator});
_Number? _number(DomainValue value) {
  BigInt? numerator;
  var denominator = BigInt.one;
  switch (value) {
    case IntegerValue(:final digits):
      numerator = _integer(digits);
    case DecimalValue(:final digits):
      final dot = digits.indexOf('.');
      final a = dot < 0 ? digits : digits.substring(0, dot);
      final b = dot < 0 ? '' : digits.substring(dot + 1);
      if (b.length > 38) return null;
      denominator = BigInt.from(10).pow(b.length);
      numerator = _integer('$a$b');
    case RationalValue(:final numerator, :final denominator):
      final n = _integer(numerator), d = _integer(denominator);
      return n == null || d == null || d <= BigInt.zero
          ? null
          : (numerator: n, denominator: d);
    default:
      return null;
  }
  return numerator == null
      ? null
      : (numerator: numerator, denominator: denominator);
}

int? _ordering(DomainValue left, DomainValue right) {
  final a = _number(left), b = _number(right);
  if (a != null && b != null) {
    final x = _product(a.numerator, b.denominator);
    final y = _product(b.numerator, a.denominator);
    return x == null || y == null ? null : x.compareTo(y);
  }
  switch ((left, right)) {
    case (TextValue(text: final a), TextValue(text: final b)):
      // Rust string ordering is UTF-8 byte ordering, not UTF-16 code units.
      final x = utf8.encode(a), y = utf8.encode(b);
      for (var i = 0; i < x.length && i < y.length; i++) {
        final order = x[i].compareTo(y[i]);
        if (order != 0) return order;
      }
      return x.length.compareTo(y.length);
    case (BooleanValue(value: final a), BooleanValue(value: final b)):
      return (a ? 1 : 0).compareTo(b ? 1 : 0);
    case (
          QuantityValue(value: final a, unit: final u),
          QuantityValue(value: final b, unit: final v),
        )
        when u == v:
      return _ordering(a, b);
    default:
      return null;
  }
}

/// Null means unsupported or unresolved, never a convenient false comparison.
bool? compareValues(DomainValue left, Comparator op, DomainValue right) {
  if (left is RangeValue || right is RangeValue) {
    return _ranges(left, op, right);
  }
  final order = _ordering(left, right);
  if (order == null) return null;
  return switch (op) {
    Comparator.eq => order == 0,
    Comparator.neq => order != 0,
    Comparator.lt => order < 0,
    Comparator.ltEq => order <= 0,
    Comparator.gt => order > 0,
    Comparator.gtEq => order >= 0,
  };
}

typedef _Bounds = ({
  DomainValue lower,
  DomainValue upper,
  bool lowerInclusive,
  bool upperInclusive,
  UnitId? unit,
});
_Bounds? _bounds(DomainValue value) {
  final b = switch (value) {
    RangeValue(
      :final lower,
      :final upper,
      :final lowerInclusive,
      :final upperInclusive,
      :final unit,
    ) =>
      (
        lower: lower,
        upper: upper,
        lowerInclusive: lowerInclusive,
        upperInclusive: upperInclusive,
        unit: unit,
      ),
    QuantityValue(:final value, :final unit) => (
      lower: value,
      upper: value,
      lowerInclusive: true,
      upperInclusive: true,
      unit: unit,
    ),
    _ => (
      lower: value,
      upper: value,
      lowerInclusive: true,
      upperInclusive: true,
      unit: null,
    ),
  };
  if (_number(b.lower) == null || _number(b.upper) == null) return null;
  final order = _ordering(b.lower, b.upper);
  if (order == null ||
      order > 0 ||
      order == 0 && (!b.lowerInclusive || !b.upperInclusive)) {
    return null;
  }
  return b;
}

bool? _ranges(DomainValue left, Comparator op, DomainValue right) {
  final x = _bounds(left), y = _bounds(right);
  if (x == null || y == null || x.unit != y.unit) return null;
  final bc = _ordering(x.upper, y.lower), ad = _ordering(x.lower, y.upper);
  if (bc == null || ad == null) return null;
  final disjoint =
      bc < 0 ||
      ad > 0 ||
      bc == 0 && !(x.upperInclusive && y.lowerInclusive) ||
      ad == 0 && !(x.lowerInclusive && y.upperInclusive);
  switch (op) {
    case Comparator.eq || Comparator.neq:
      bool? equal;
      if (_ordering(x.lower, x.upper) == 0 &&
          _ordering(y.lower, y.upper) == 0) {
        final order = _ordering(x.lower, y.lower);
        if (order == null) return null;
        equal = order == 0;
      } else if (disjoint) {
        equal = false;
      }
      return equal == null
          ? null
          : op == Comparator.eq
          ? equal
          : !equal;
    case Comparator.lt:
      if (bc < 0 || bc == 0 && !(x.upperInclusive && y.lowerInclusive)) {
        return true;
      }
      if (ad >= 0) return false;
      return null;
    case Comparator.ltEq:
      if (bc <= 0) return true;
      if (ad > 0 || ad == 0 && !(x.lowerInclusive && y.upperInclusive)) {
        return false;
      }
      return null;
    case Comparator.gt:
      return _ranges(right, Comparator.lt, left);
    case Comparator.gtEq:
      return _ranges(right, Comparator.ltEq, left);
  }
}
