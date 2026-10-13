import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

enum CreationCalendar { gregorian, fictional }

final class UniverseCreationForm {
  const UniverseCreationForm({
    required this.name,
    required this.calendar,
    this.date = '',
    this.time = '',
    this.offset = '',
    this.calendarName = '',
    this.initialTick = '',
    this.tickLabel = '',
    this.ticksPerMonth = '',
  });
  final String name,
      date,
      time,
      offset,
      calendarName,
      initialTick,
      tickLabel,
      ticksPerMonth;
  final CreationCalendar calendar;

  String get timestamp => '${date.trim()}T${time.trim()}${offset.trim()}';

  CreateUniverseEngineRequest request() {
    if (name.trim().isEmpty) throw const FormatException('Name this universe.');
    selectorKey(name);
    final UniverseStart start;
    if (calendar == CreationCalendar.gregorian) {
      start = GregorianUniverseStart(timestamp);
      try {
        start.build(CalendarId.generate());
      } on FormatException {
        throw const FormatException(
          'Enter a valid date, whole-second time and explicit fixed UTC offset.',
        );
      }
    } else {
      final month = ticksPerMonth.trim();
      if (month.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(month)) {
        throw const FormatException(
          'Ticks per month must be a positive whole number, or left blank.',
        );
      }
      final count = month.isEmpty ? null : int.tryParse(month);
      if (month.isNotEmpty &&
          (count == null || count < 1 || count > 4294967295)) {
        throw const FormatException(
          'Ticks per month must be between 1 and 4294967295.',
        );
      }
      start = FictionalUniverseStart(
        calendarName: calendarName,
        initialTick: initialTick.trim(),
        tickLabel: tickLabel,
        ticksPerMonth: count,
      );
      start.build(CalendarId.generate());
    }
    return CreateUniverseEngineRequest(name: name, start: start);
  }
}

LibraryEntry createdUniverse(CanonicalValue value) {
  final fields = WireFields(value, {
    'universe_id',
    'continuity_id',
    'context_id',
    'revision',
    'name',
  });
  return LibraryEntry(
    UniverseId.parse(fields.string('universe_id')),
    fields.string('name'),
  );
}
