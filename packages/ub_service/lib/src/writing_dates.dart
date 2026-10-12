import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Normalize writer dates using only the admitted pinned context and rows.
/// No current date, calendar conversion or hidden clock is inferred.
CheckChangesRequest normalizeWritingChangesDates(
  CheckChangesRequest input,
  Frame frame,
  List<RecordVersion> rows,
) => CheckChangesRequest.fromWire(
  normalizeWritingDates(input.toArgs(), frame, rows),
);

/// Also supports temporal fields in the other ordinary writer DTOs.
CanonicalValue normalizeWritingDates(
  CanonicalValue input,
  Frame frame,
  List<RecordVersion> rows,
) {
  Chronology? clock;
  for (final row in rows) {
    if (row.identity.recordId == frame.context.record) {
      if (row.payload case RepresentedContextRecord(:final chronology)) {
        clock = chronology;
      }
      break;
    }
  }
  final selected = clock;
  if (selected != null) {
    final compatible = switch (frame.time) {
      TimelessFrameTime() => true,
      AtFrameTime(time: ExactTime(:final calendar)) =>
        calendar == selected.calendar,
      _ => false,
    };
    if (!compatible) clock = null;
  }
  return _visit(input, clock, rows, 'writing');
}

String? _string(CanonicalValue? value) =>
    value is CanonicalString ? value.value : null;

CanonicalValue? _field(CanonicalValue? value, String name) =>
    value is CanonicalObject
    ? {for (final entry in value.fields) entry.key: entry.value}[name]
    : null;

bool _present(CanonicalValue? value) =>
    value != null && value is! CanonicalNull;

BigInt? _coordinate(String value) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) return null;
  final parsed = BigInt.parse(value), limit = BigInt.one << 127;
  return parsed >= -limit && parsed < limit ? parsed : null;
}

CanonicalValue _visit(
  CanonicalValue value,
  Chronology? clock,
  List<RecordVersion> rows,
  String path,
) {
  if (value is CanonicalArray) {
    return CanonicalArray([
      for (var i = 0; i < value.items.length; i++)
        _visit(value.items[i], clock, rows, '$path[$i]'),
    ]);
  }
  if (value is! CanonicalObject) return value;
  final fields = Map<String, CanonicalValue>.fromEntries(value.fields);
  final dated =
      fields.entries.any(
        (entry) => entry.key.endsWith('_date') && _present(entry.value),
      ) ||
      _present(_field(fields['lifetime'], 'end_date'));
  if (dated && clock != null) {
    String? handle;
    for (final entry in fields.entries) {
      if (entry.key.endsWith('_handle')) {
        handle = _string(entry.value);
        if (handle != null) break;
      }
    }
    handle ??= _string(_field(fields['start'], 'event_handle'));
    if (handle != null) {
      for (final row in rows) {
        if (row.identity.recordId.value != handle &&
            row.recordVersionId.value != handle) {
          continue;
        }
        final original = row.payload.toWire();
        for (final name in ['validity', 'time', 'sent_at', 'received_at']) {
          final calendar = _string(_field(_field(original, name), 'calendar'));
          if (calendar != null && calendar != clock.calendar.value) {
            throw FormatException(
              '$path: the selected date calendar differs from the original authored calendar; no conversion was performed.',
            );
          }
        }
        break;
      }
    }
  }
  for (final (tick, date) in const [
    ('at_tick', 'at_date'),
    ('sent_tick', 'sent_date'),
    ('received_tick', 'received_date'),
    ('end_tick', 'end_date'),
  ]) {
    final dateValue = fields.remove(date);
    if (_present(dateValue)) {
      final authored = _string(dateValue);
      if (authored == null) {
        throw FormatException('$path.$date: enter an authored date string.');
      }
      if (clock == null) {
        throw FormatException(
          '$path.$date: select an authored calendar with a readable chronology; no calendar or current date was inferred.',
        );
      }
      final String coordinate;
      try {
        coordinate = clock.coordinate(authored);
      } on FormatException catch (error) {
        throw FormatException('$path.$date: ${error.message}');
      }
      final supplied = _string(fields[tick]);
      if (supplied != null && supplied.isNotEmpty) {
        final a = _coordinate(supplied), b = _coordinate(coordinate);
        if (a == null || b == null || a != b) {
          throw FormatException(
            '$path: $date and $tick disagree; explicitly correct the date or coordinate.',
          );
        }
      } else {
        fields[tick] = CanonicalString(coordinate);
      }
    }
    if (_string(fields[tick]) == '') {
      throw FormatException('$path: supply $tick or $date explicitly.');
    }
  }
  // Authored values, role maps and prose are not temporal DTOs.
  const untouched = {
    'value',
    'participants',
    'claim',
    'content',
    'metadata',
    'labels',
    'text',
  };
  return CanonicalObject([
    for (final entry in fields.entries)
      MapEntry(
        entry.key,
        untouched.contains(entry.key)
            ? entry.value
            : _visit(entry.value, clock, rows, '$path.${entry.key}'),
      ),
  ]);
}
