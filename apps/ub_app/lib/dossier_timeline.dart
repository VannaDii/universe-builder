import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart'
    show exactEventTime, EventEvaluationError;

/// Uses only explicit participants in permission-filtered supporting records.
List<RecordVersion> dossierEvents(
  Records material,
  UniverseId universe,
  RecordId entity,
) => [
  for (final row in [...material.records, ...material.evidence])
    if (row.payload case EventRecord(:final participants)
        when row.identity.universeId == universe)
      if (participants.any(
        (p) =>
            p.record.record == entity &&
            (p.record.universe == null || p.record.universe == universe),
      ))
        row,
];

/// Exact coordinates use the same bounded integer interpretation as the rules.
/// Unknown placement never acquires a coordinate or crosses calendars.
({Map<CalendarId, List<RecordVersion>> points, List<RecordVersion> other})
dossierEventOrder(Iterable<RecordVersion> events) {
  final points = <CalendarId, List<RecordVersion>>{};
  final coordinates = <RecordId, BigInt>{};
  final other = <RecordVersion>[];
  for (final row in events) {
    final event = row.payload as EventRecord;
    try {
      final exact = exactEventTime(event.time);
      points.putIfAbsent(exact.calendar, () => []).add(row);
      coordinates[row.identity.recordId] = exact.coordinate;
    } on EventEvaluationError {
      other.add(row);
    }
  }
  for (final group in points.values) {
    // Preserve returned order for ties, without asserting an event sequence.
    final positions = {
      for (var i = 0; i < group.length; i++) group[i].identity.recordId: i,
    };
    group.sort((a, b) {
      final comparison = coordinates[a.identity.recordId]!.compareTo(
        coordinates[b.identity.recordId]!,
      );
      return comparison == 0
          ? positions[a.identity.recordId]!.compareTo(
              positions[b.identity.recordId]!,
            )
          : comparison;
    });
  }
  return (points: points, other: other);
}

CalendarId? eventCalendar(TemporalExpression time) => switch (time) {
  ExactTime(:final calendar) ||
  IntervalTime(:final calendar) ||
  ApproximateTime(:final calendar) ||
  DurationTime(:final calendar) ||
  RelativeTime(:final calendar) => calendar,
  UnspecifiedTime() => null,
};

String eventTimeText(
  TemporalExpression time,
  String Function(RecordRef) name, {
  Chronology? chronology,
}) {
  String coordinate(CalendarId calendar, String value) {
    if (chronology?.calendar == calendar) {
      try {
        return chronology!.display(value);
      } on FormatException {
        /* Retain authored token. */
      }
    }
    return value;
  }

  String bound(CalendarId calendar, TemporalBound value) => switch (value) {
    ExactBound(:final value) => coordinate(calendar, value),
    UnknownBound() => 'unknown boundary',
    UnboundedBound() => 'unbounded',
    ApproximateBound(:final value) =>
      'approximately ${coordinate(calendar, value)} (authored uncertainty)',
    UncertainBound(:final lower, :final upper) =>
      'between ${coordinate(calendar, lower)} and ${coordinate(calendar, upper)}',
  };
  return switch (time) {
    ExactTime(:final calendar, :final value) =>
      'Point: ${coordinate(calendar, value)}',
    IntervalTime(:final calendar, :final start, :final end) =>
      'Interval: ${bound(calendar, start)} → ${bound(calendar, end)}',
    ApproximateTime(:final calendar, :final value) =>
      'Approximately ${coordinate(calendar, value)} (authored uncertainty)',
    DurationTime() => 'Duration only; no absolute placement',
    RelativeTime(:final relation, :final target) =>
      '${relation.name}: ${name(target)}',
    UnspecifiedTime() => 'Time unspecified',
  };
}
