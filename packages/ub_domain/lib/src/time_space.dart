import 'dart:convert';

import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';
import 'references.dart';
import 'value.dart';

sealed class TemporalBound {
  const TemporalBound();
  bool get isKnown => this is! UnknownBound;
  CanonicalObject encode({required bool canonical});
  @override
  bool operator ==(Object other) =>
      other is TemporalBound &&
      runtimeType == other.runtimeType &&
      encode(canonical: false).toText() ==
          other.encode(canonical: false).toText();
  @override
  int get hashCode => encode(canonical: true).toText().hashCode;
  static TemporalBound fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) throw const FormatException('Temporal nesting limit');
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'unknown':
        f.allow({'kind'});
        return const UnknownBound();
      case 'unbounded':
        f.allow({'kind'});
        return const UnboundedBound();
      case 'exact':
        f.allow({'kind', 'value'});
        return ExactBound(f.string('value'));
      case 'approximate':
        f.allow({'kind', 'value', 'uncertainty'});
        return ApproximateBound(
          f.string('value'),
          DomainValue.fromWire(f.require('uncertainty'), depth: depth + 1),
        );
      case 'bounded_uncertainty':
        f.allow({'kind', 'lower', 'upper'});
        return UncertainBound(f.string('lower'), f.string('upper'));
      default:
        throw const FormatException('Unknown temporal bound');
    }
  }
}

final class UnknownBound extends TemporalBound {
  const UnknownBound();
  @override
  CanonicalObject encode({required bool canonical}) => tagged('unknown', []);
}

final class UnboundedBound extends TemporalBound {
  const UnboundedBound();
  @override
  CanonicalObject encode({required bool canonical}) => tagged('unbounded', []);
}

final class ExactBound extends TemporalBound {
  const ExactBound(this.value);
  final String value;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('exact', [MapEntry('value', CanonicalString(value))]);
}

final class ApproximateBound extends TemporalBound {
  const ApproximateBound(this.value, this.uncertainty);
  final String value;
  final DomainValue uncertainty;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('approximate', [
    MapEntry('value', CanonicalString(value)),
    MapEntry(
      'uncertainty',
      canonical ? uncertainty.toCanonical() : uncertainty.toWire(),
    ),
  ]);
}

final class UncertainBound extends TemporalBound {
  const UncertainBound(this.lower, this.upper);
  final String lower;
  final String upper;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('bounded_uncertainty', [
        MapEntry('lower', CanonicalString(lower)),
        MapEntry('upper', CanonicalString(upper)),
      ]);
}

enum TemporalRelation { before, after, during, overlaps, simultaneous }

sealed class TemporalExpression {
  const TemporalExpression();
  CanonicalObject encode({required bool canonical});
  @override
  bool operator ==(Object other) =>
      other is TemporalExpression &&
      runtimeType == other.runtimeType &&
      encode(canonical: false).toText() ==
          other.encode(canonical: false).toText();
  @override
  int get hashCode => encode(canonical: true).toText().hashCode;
  void validate() {}
  bool get isExact => this is ExactTime || this is DurationTime;
  static TemporalExpression fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) throw const FormatException('Temporal nesting limit');
    final f = Fields(value);
    CalendarId calendar() => CalendarId.parse(f.string('calendar'));
    switch (f.string('kind')) {
      case 'exact':
        f.allow({'kind', 'calendar', 'value'});
        return ExactTime(calendar(), f.string('value'));
      case 'interval':
        f.allow({'kind', 'calendar', 'start', 'end'});
        return IntervalTime(
          calendar(),
          TemporalBound.fromWire(f.require('start'), depth: depth + 1),
          TemporalBound.fromWire(f.require('end'), depth: depth + 1),
        );
      case 'approximate':
        f.allow({'kind', 'calendar', 'value', 'uncertainty'});
        return ApproximateTime(
          calendar(),
          f.string('value'),
          DomainValue.fromWire(f.require('uncertainty'), depth: depth + 1),
        );
      case 'duration':
        f.allow({'kind', 'calendar', 'amount'});
        return DurationTime(
          calendar(),
          DomainValue.fromWire(f.require('amount'), depth: depth + 1),
        );
      case 'relative':
        f.allow({'kind', 'calendar', 'relation', 'target'});
        final relation = TemporalRelation.values.firstWhere(
          (v) => v.name == f.string('relation'),
          orElse: () =>
              throw const FormatException('Unknown temporal relation'),
        );
        return RelativeTime(
          calendar(),
          relation,
          RecordRef.fromCanonical(f.require('target')),
        );
      case 'unspecified':
        f.allow({'kind'});
        return const UnspecifiedTime();
      default:
        throw const FormatException('Unknown temporal expression');
    }
  }
}

final class ExactTime extends TemporalExpression {
  const ExactTime(this.calendar, this.value);
  final CalendarId calendar;
  final String value;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('exact', [
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('value', CanonicalString(value)),
  ]);
  @override
  void validate() => _checkTime(value);
}

final class IntervalTime extends TemporalExpression {
  const IntervalTime(this.calendar, this.start, this.end);
  final CalendarId calendar;
  final TemporalBound start;
  final TemporalBound end;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('interval', [
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('start', start.encode(canonical: canonical)),
    MapEntry('end', end.encode(canonical: canonical)),
  ]);
  @override
  void validate() {
    // Preserve the existing structural check. Ordering/uncertainty algebra
    // needs the authored calendar capabilities, not guessed date arithmetic.
    if (start case ExactBound(:final value)) {
      _checkTime(value);
    }
    if (end case ExactBound(:final value)) {
      _checkTime(value);
    }
  }
}

final class ApproximateTime extends TemporalExpression {
  const ApproximateTime(this.calendar, this.value, this.uncertainty);
  final CalendarId calendar;
  final String value;
  final DomainValue uncertainty;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('approximate', [
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('value', CanonicalString(value)),
    MapEntry(
      'uncertainty',
      canonical ? uncertainty.toCanonical() : uncertainty.toWire(),
    ),
  ]);
  @override
  void validate() {
    _checkTime(value);
    uncertainty.validate();
  }
}

final class DurationTime extends TemporalExpression {
  const DurationTime(this.calendar, this.amount);
  final CalendarId calendar;
  final DomainValue amount;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('duration', [
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('amount', canonical ? amount.toCanonical() : amount.toWire()),
  ]);
  @override
  void validate() => amount.validate();
}

final class RelativeTime extends TemporalExpression {
  const RelativeTime(this.calendar, this.relation, this.target);
  final CalendarId calendar;
  final TemporalRelation relation;
  final RecordRef target;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('relative', [
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('relation', CanonicalString(relation.name)),
    MapEntry('target', target.toCanonical()),
  ]);
}

final class UnspecifiedTime extends TemporalExpression {
  const UnspecifiedTime();
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('unspecified', []);
}

void _checkTime(String value) {
  if (value.isEmpty ||
      utf8.encode(value).length > 640 ||
      value.runes.any((v) => v < 32 || (v >= 127 && v <= 159))) {
    throw const FormatException(
      'Empty, oversized or control-containing calendar value',
    );
  }
}

enum SpatialRelation {
  containedIn('contained_in'),
  adjacentTo('adjacent_to'),
  connectedTo('connected_to');

  const SpatialRelation(this.wireName);
  final String wireName;
}

sealed class SpatialExpression {
  const SpatialExpression();
  CanonicalObject encode({required bool canonical});
  @override
  bool operator ==(Object other) =>
      other is SpatialExpression &&
      runtimeType == other.runtimeType &&
      encode(canonical: false).toText() ==
          other.encode(canonical: false).toText();
  @override
  int get hashCode => encode(canonical: true).toText().hashCode;
  static SpatialExpression fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) throw const FormatException('Spatial nesting limit');
    final f = Fields(value);
    final kind = f.string('kind');
    switch (kind) {
      case 'contained_in':
      case 'adjacent_to':
      case 'connected_to':
        f.allow({'kind', 'target'});
        return SpatialLink(
          SpatialRelation.values.firstWhere((v) => v.wireName == kind),
          RecordRef.fromCanonical(f.require('target')),
        );
      case 'coordinates':
        f.allow({'kind', 'reference', 'values'});
        return SpatialCoordinates(
          f.string('reference'),
          f
              .array('values')
              .map((v) => DomainValue.fromWire(v, depth: depth + 1)),
        );
      case 'distance':
        f.allow({'kind', 'from', 'value', 'unit'});
        return SpatialDistance(
          RecordRef.fromCanonical(f.require('from')),
          DomainValue.fromWire(f.require('value'), depth: depth + 1),
          UnitId.parse(f.string('unit')),
        );
      case 'unspecified':
        f.allow({'kind'});
        return const UnspecifiedSpace();
      default:
        throw const FormatException('Unknown spatial expression');
    }
  }
}

final class SpatialLink extends SpatialExpression {
  const SpatialLink(this.relation, this.target);
  final SpatialRelation relation;
  final RecordRef target;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged(relation.wireName, [MapEntry('target', target.toCanonical())]);
}

final class SpatialCoordinates extends SpatialExpression {
  SpatialCoordinates(this.reference, Iterable<DomainValue> values)
    : values = List.unmodifiable(values);
  final String reference;
  final List<DomainValue> values;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('coordinates', [
    MapEntry('reference', CanonicalString(reference)),
    MapEntry(
      'values',
      CanonicalArray(
        values.map((v) => canonical ? v.toCanonical() : v.toWire()),
      ),
    ),
  ]);
}

final class SpatialDistance extends SpatialExpression {
  const SpatialDistance(this.from, this.value, this.unit);
  final RecordRef from;
  final DomainValue value;
  final UnitId unit;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('distance', [
    MapEntry('from', from.toCanonical()),
    MapEntry('unit', CanonicalString(unit.value)),
    MapEntry('value', canonical ? value.toCanonical() : value.toWire()),
  ]);
}

final class UnspecifiedSpace extends SpatialExpression {
  const UnspecifiedSpace();
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('unspecified', []);
}
