import 'dart:collection';

import 'package:ub_domain/ub_domain.dart';

TemporalExpression? validityExpression(Validity validity) => switch (validity) {
  InstantValidity(:final at) => at,
  CalendarIntervalValidity(:final calendar, :final start, :final end) =>
    IntervalTime(calendar, start, end),
  _ => null,
};

/// Null is unresolved. Timeless explicitly includes all validities.
bool? temporalApplies(Validity validity, FrameTime frame) => switch (frame) {
  TimelessFrameTime() => true,
  AtFrameTime(:final time) =>
    validityExpression(validity) == null
        ? null
        : temporalRelation(
            time,
            TemporalRelation.during,
            validityExpression(validity)!,
          ),
  AtEventFrameTime() => null,
};

bool? temporalOverlaps(Validity a, Validity b) {
  if (a is UnspecifiedValidity && b is UnspecifiedValidity) return true;
  final left = validityExpression(a), right = validityExpression(b);
  return left == null || right == null
      ? null
      : temporalRelation(left, TemporalRelation.overlaps, right);
}

final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
final _integer = RegExp(r'^[+-]?[0-9]+$');
BigInt? _number(String value) {
  if (!_integer.hasMatch(value)) return null;
  final n = BigInt.tryParse(value, radix: 10);
  return n == null || n <= _min || n >= _max ? null : n;
}

typedef _Window = ({BigInt lo, BigInt hi});
_Window? _bound(TemporalBound bound, bool start) {
  switch (bound) {
    case ExactBound(:final value):
      final n = _number(value);
      return n == null ? null : (lo: n, hi: n);
    case UnboundedBound():
      final n = start ? _min : _max;
      return (lo: n, hi: n);
    case UncertainBound(:final lower, :final upper):
      final lo = _number(lower), hi = _number(upper);
      return lo == null || hi == null || lo > hi ? null : (lo: lo, hi: hi);
    default:
      // Approximation amounts require an authored unit interpretation.
      return null;
  }
}

typedef _Windows = ({
  CalendarId calendar,
  _Window start,
  _Window end,
  bool point,
});
_Windows? _windows(TemporalExpression time) {
  switch (time) {
    case ExactTime(:final calendar, :final value):
      final n = _number(value);
      if (n == null) return null;
      final w = (lo: n, hi: n);
      return (calendar: calendar, start: w, end: w, point: true);
    case IntervalTime(:final calendar, :final start, :final end):
      final a = _bound(start, true), b = _bound(end, false);
      if (a == null || b == null || a.hi > b.lo) return null;
      return (calendar: calendar, start: a, end: b, point: false);
    default:
      return null;
  }
}

/// All extremal interpretations must agree; no more than 16 cases are evaluated.
/// Independent calendars and unknown boundaries never acquire guessed values.
bool? temporalRelation(
  TemporalExpression left,
  TemporalRelation relation,
  TemporalExpression right,
) {
  final x = _windows(left), y = _windows(right);
  if (x == null || y == null || x.calendar != y.calendar) return null;
  bool? answer;
  for (final a in [x.start.lo, x.start.hi]) {
    for (final b in [x.end.lo, x.end.hi]) {
      for (final c in [y.start.lo, y.start.hi]) {
        for (final d in [y.end.lo, y.end.hi]) {
          if (x.point && a != b || y.point && c != d) continue;
          final v = switch (relation) {
            TemporalRelation.before => x.point ? b < c : b <= c,
            TemporalRelation.after => y.point ? d < a : d <= a,
            TemporalRelation.simultaneous => x.point && y.point && a == c,
            TemporalRelation.during =>
              y.point
                  ? x.point && a == c
                  : x.point
                  ? c <= a && a < d
                  : c <= a && b <= d,
            TemporalRelation.overlaps =>
              x.point && y.point
                  ? a == c
                  : x.point
                  ? c <= a && a < d
                  : y.point
                  ? a <= c && c < b
                  : a < b && c < d && a < d && c < b,
          };
          if (answer != null && answer != v) return null;
          answer = v;
        }
      }
    }
  }
  return answer;
}

final class TemporalOrderingError implements Exception {
  const TemporalOrderingError(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef _OrderingNode = (String, RecordId);

/// Only exact positive assertions constrain a declared clock's ordering graph.
/// Scope, validity and predicate partitions retain their wire distinctions.
void checkTemporalOrderings(List<RecordVersion> records) {
  final propositions = <RecordId, PropositionRecord>{
    for (final record in records)
      if (record.payload case final PropositionRecord p)
        record.identity.recordId: p,
  };
  final edges = <_OrderingNode, Set<_OrderingNode>>{};
  final degree = <_OrderingNode, int>{};
  for (final record in records) {
    final assertion = record.payload;
    if (assertion is! AssertionRecord ||
        assertion.polarity != Polarity.support ||
        assertion.precision != Precision.exact ||
        assertion.alternatives.isNotEmpty) {
      continue;
    }
    final p = propositions[assertion.proposition.record];
    if (p == null || p.value is! TemporalValue) continue;
    final time = (p.value! as TemporalValue).temporal;
    if (time is! RelativeTime ||
        (time.relation != TemporalRelation.before &&
            time.relation != TemporalRelation.after)) {
      continue;
    }
    final partition = CanonicalArray([
      CanonicalString(time.calendar.value),
      assertion.scope.toWire(),
      assertion.validity.toWire(),
      p.predicate.toCanonical(),
    ]).toText();
    var from = (partition, p.subject.record),
        to = (partition, time.target.record);
    if (time.relation == TemporalRelation.after) (from, to) = (to, from);
    degree.putIfAbsent(from, () => 0);
    degree.putIfAbsent(to, () => 0);
    if (degree.length > 10000) {
      throw const TemporalOrderingError('relative-order work budget exhausted');
    }
    if (edges.putIfAbsent(from, () => <_OrderingNode>{}).add(to)) {
      degree[to] = degree[to]! + 1;
    }
  }
  final ready = Queue<_OrderingNode>.of(
    degree.keys.where((node) => degree[node] == 0),
  );
  var visited = 0;
  while (ready.isNotEmpty) {
    final node = ready.removeFirst();
    visited++;
    for (final next in edges[node] ?? const <_OrderingNode>{}) {
      degree[next] = degree[next]! - 1;
      if (degree[next] == 0) ready.add(next);
    }
  }
  if (visited != degree.length) {
    throw const TemporalOrderingError(
      'strict relative ordering contains a cycle in one calendar',
    );
  }
}
