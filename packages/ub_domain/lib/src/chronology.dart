part of 'records.dart';

final _clockWhitespace = RegExp(
  r'^[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+|[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+$',
);
String _clockTrim(String s) => s.replaceAll(_clockWhitespace, '');
BigInt _clockInteger(String s, int bits, String error) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(s)) {
    throw FormatException(error);
  }
  final n = BigInt.parse(s), limit = BigInt.one << (bits - 1);
  if (n < -limit || n >= limit) {
    throw FormatException(error);
  }
  return n;
}

final _minClockSecond = DateTime.utc(-262143).millisecondsSinceEpoch ~/ 1000;
final _maxClockSecond = DateTime.utc(262143).millisecondsSinceEpoch ~/ 1000 - 1;
int _clockOffset(int offset, String error) {
  if (offset <= -86400 || offset >= 86400) {
    throw FormatException(error);
  }
  return offset;
}

DateTime _clockDate(String value, String error, {String? parseError}) {
  final n = _clockInteger(value, 64, parseError ?? error);
  if (n < BigInt.from(_minClockSecond) || n > BigInt.from(_maxClockSecond)) {
    throw FormatException(error);
  }
  return DateTime.fromMillisecondsSinceEpoch(n.toInt() * 1000, isUtc: true);
}

/// Parse the existing RFC3339 contract, without Dart's date-overflow normalizing.
/// Nanoseconds beyond the source parser's first nine digits are discarded.
(int seconds, int offset) _clockTimestamp(String value) {
  const error =
      'Enter an RFC3339 fictional timestamp with an explicit offset, such as 2042-06-01T12:00:00+00:00';
  final m = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?([Zz]|[+−-][0-9]{2}:[0-9]{2})$',
  ).firstMatch(value);
  if (m == null) {
    throw const FormatException(error);
  }
  final year = int.parse(m[1]!),
      month = int.parse(m[2]!),
      day = int.parse(m[3]!),
      hour = int.parse(m[4]!),
      minute = int.parse(m[5]!),
      second = int.parse(m[6]!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 60) {
    throw const FormatException(error);
  }
  final date = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second == 60 ? 59 : second,
  );
  if (date.year != year || date.month != month || date.day != day) {
    throw const FormatException(error);
  }
  final zone = m[8]!;
  var offset = 0;
  if (zone != 'Z' && zone != 'z') {
    final hours = int.parse(zone.substring(1, 3)),
        minutes = int.parse(zone.substring(4, 6));
    if (hours > 23 || minutes > 59) {
      throw const FormatException(error);
    }
    offset = (hours * 60 + minutes) * 60 * (zone.startsWith('+') ? 1 : -1);
  }
  final fraction = m[7];
  if (second == 60 ||
      fraction != null &&
          fraction
              .substring(0, fraction.length > 9 ? 9 : fraction.length)
              .contains(RegExp('[1-9]'))) {
    throw const FormatException(
      'This clock requires whole seconds; fractional and leap seconds are unsupported.',
    );
  }
  return (date.millisecondsSinceEpoch ~/ 1000 - offset, offset);
}

extension AuthoredUniverseStart on UniverseStart {
  /// Returns a starting chronology and its authored calendar definition.
  (Chronology, CalendarRecord) build(CalendarId calendar) {
    final String name, current;
    final ClockSystem system;
    switch (this) {
      case GregorianUniverseStart(:final timestamp):
        final (seconds, offset) = _clockTimestamp(timestamp);
        name = 'Gregorian';
        current = '$seconds';
        system = GregorianClock(offset);
      case FictionalUniverseStart(
        :final calendarName,
        :final initialTick,
        :final tickLabel,
        :final ticksPerMonth,
      ):
        if (_clockTrim(calendarName).isEmpty ||
            _clockTrim(tickLabel).isEmpty ||
            utf8.encode(calendarName).length > 200 ||
            utf8.encode(tickLabel).length > 80 ||
            ticksPerMonth == 0) {
          throw const FormatException(
            'Name the fictional calendar and tick unit; a declared month must contain positive ticks.',
          );
        }
        name = _clockTrim(calendarName);
        current = _clockInteger(
          initialTick,
          128,
          'Enter the first fictional-time coordinate explicitly as a whole number.',
        ).toString();
        system = FictionalClock(_clockTrim(tickLabel), ticksPerMonth);
    }
    final chronology = Chronology(
      calendar: calendar,
      system: system,
      firstInteraction: current,
      current: current,
    );
    return (
      chronology,
      CalendarRecord(
        namespace: 'chronology',
        key: 'universe_clock',
        labels: {'en': name},
        epoch: chronology.display(current),
        unitStructure: {
          'coordinate': system is GregorianClock
              ? 'whole Unix seconds in the authored Gregorian calendar'
              : 'authored integer ticks',
        },
      ),
    );
  }
}

extension AuthoredChronology on Chronology {
  void validate() {
    _clockInteger(
      firstInteraction,
      128,
      'Invalid first interaction coordinate',
    );
    _clockInteger(current, 128, 'Invalid current coordinate');
    display(firstInteraction);
    display(current);
    if (system case FictionalClock(:final tickLabel, :final ticksPerMonth)) {
      if (_clockTrim(tickLabel).isEmpty ||
          utf8.encode(tickLabel).length > 80 ||
          ticksPerMonth == 0) {
        throw const FormatException('Invalid fictional clock units');
      }
    }
  }

  String coordinate(String value) => system is GregorianClock
      ? _clockTimestamp(value).$1.toString()
      : _clockInteger(
          value,
          128,
          'Enter an exact fictional clock coordinate.',
        ).toString();

  String display(String value) {
    switch (system) {
      case GregorianClock(:final offsetSeconds):
        final date = _clockDate(value, 'Clock value out of range').add(
          Duration(
            seconds: _clockOffset(offsetSeconds, 'Invalid clock offset'),
          ),
        );
        String two(int n) => n.toString().padLeft(2, '0');
        final year = date.year >= 0 && date.year <= 9999
            ? date.year.toString().padLeft(4, '0')
            : '${date.year < 0 ? '-' : '+'}${date.year.abs().toString().padLeft(4, '0')}';
        // Preserve Chrono's RFC3339 rounding of historical sub-minute offsets.
        final roundedMinutes = (offsetSeconds.abs() + 30) ~/ 60;
        final zone =
            '${offsetSeconds < 0 ? '-' : '+'}${two(roundedMinutes ~/ 60)}:${two(roundedMinutes % 60)}';
        return '$year-${two(date.month)}-${two(date.day)}T${two(date.hour)}:${two(date.minute)}:${two(date.second)}$zone';
      case FictionalClock(:final tickLabel):
        _clockInteger(value, 128, 'Invalid fictional coordinate');
        return '$value $tickLabel';
    }
  }

  /// Returns a new chronology; the first interaction and source remain intact.
  Chronology change(String value, TimeChangeKind mode, String reason) {
    if (_clockTrim(reason).isEmpty) {
      throw const FormatException(
        'Explain the elapsed-time or time-travel transition.',
      );
    }
    final next = coordinate(value),
        n = _clockInteger(next, 128, 'Invalid next time'),
        old = _clockInteger(current, 128, 'Invalid current time');
    if (mode == TimeChangeKind.elapsed && n <= old) {
      throw const FormatException(
        'Elapsed time must move forward; backward travel requires an explicit time-travel transition.',
      );
    }
    if (n == old) {
      throw const FormatException('The authored time is unchanged.');
    }
    return Chronology(
      calendar: calendar,
      system: system,
      firstInteraction: firstInteraction,
      current: next,
    );
  }

  /// Resolves only against the supplied pinned coordinate, never wall-clock now.
  String monthsAgo(String from, int months) {
    _checkedU32(months);
    switch (system) {
      case GregorianClock(:final offsetSeconds):
        final utc = _clockDate(
          from,
          'Date out of range',
          parseError: 'Invalid date',
        );
        final offset = _clockOffset(offsetSeconds, 'Invalid offset');
        if (months == 0) {
          return (utc.millisecondsSinceEpoch ~/ 1000).toString();
        }
        final date = utc.add(Duration(seconds: offset));
        final target = date.year * 12 + date.month - 1 - months;
        final year = (target - target % 12) ~/ 12, month = target % 12 + 1;
        if (year < -262143 || year > 262142) {
          throw const FormatException('Month offset out of range');
        }
        final lastDay = DateTime.utc(year, month + 1, 0).day;
        if (date.day > lastDay) {
          throw const FormatException(
            'That day does not exist in the target month; choose an explicit date.',
          );
        }
        final seconds =
            DateTime.utc(
                  year,
                  month,
                  date.day,
                  date.hour,
                  date.minute,
                  date.second,
                ).millisecondsSinceEpoch ~/
                1000 -
            offset;
        if (seconds < _minClockSecond || seconds > _maxClockSecond) {
          throw const FormatException('Month offset out of range');
        }
        return '$seconds';
      case FictionalClock(:final ticksPerMonth):
        if (ticksPerMonth == null) {
          throw const FormatException(
            'This fictional calendar has no declared month length.',
          );
        }
        final earlier =
            _clockInteger(from, 128, 'Month offset out of range') -
            BigInt.from(months) * BigInt.from(ticksPerMonth);
        return _clockInteger(
          earlier.toString(),
          128,
          'Month offset out of range',
        ).toString();
    }
  }
}
