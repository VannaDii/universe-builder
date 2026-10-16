import 'package:ub_domain/ub_domain.dart';

import 'engine_request.dart';
import 'wire.dart';

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
    this.creationPending = false,
    this.realWorld = true,
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
  final bool creationPending;
  final bool realWorld;

  UniverseCreationForm withPending(bool pending) => UniverseCreationForm(
    name: name,
    date: date,
    time: time,
    offset: offset,
    calendarName: calendarName,
    initialTick: initialTick,
    tickLabel: tickLabel,
    ticksPerMonth: ticksPerMonth,
    calendar: calendar,
    creationPending: pending,
    realWorld: realWorld,
  );

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('date', CanonicalString(date)),
    MapEntry('time', CanonicalString(time)),
    MapEntry('offset', CanonicalString(offset)),
    MapEntry('calendarName', CanonicalString(calendarName)),
    MapEntry('initialTick', CanonicalString(initialTick)),
    MapEntry('tickLabel', CanonicalString(tickLabel)),
    MapEntry('ticksPerMonth', CanonicalString(ticksPerMonth)),
    MapEntry('calendar', CanonicalString(calendar.name)),
    MapEntry('creationPending', CanonicalBool(creationPending)),
    MapEntry('realWorld', CanonicalBool(realWorld)),
  ]);

  factory UniverseCreationForm.fromWire(CanonicalValue value) {
    final fields = WireFields(value, {
      'name',
      'date',
      'time',
      'offset',
      'calendarName',
      'initialTick',
      'tickLabel',
      'ticksPerMonth',
      'calendar',
      'creationPending',
      'realWorld',
    });
    return UniverseCreationForm(
      name: fields.string('name'),
      date: fields.string('date'),
      time: fields.string('time'),
      offset: fields.string('offset'),
      calendarName: fields.string('calendarName'),
      initialTick: fields.string('initialTick'),
      tickLabel: fields.string('tickLabel'),
      ticksPerMonth: fields.string('ticksPerMonth'),
      calendar: CreationCalendar.values.byName(fields.string('calendar')),
      creationPending: fields.boolean('creationPending'),
      realWorld: fields.boolean('realWorld'),
    );
  }

  String get timestamp => '${date.trim()}T${time.trim()}${offset.trim()}';

  CreateUniverseEngineRequest request() {
    if (creationPending) {
      throw const FormatException(
        'Check the library before another creation attempt.',
      );
    }
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
    return CreateUniverseEngineRequest(
      name: name,
      start: start,
      realWorld: realWorld,
    );
  }
}

final class SavedUniverseCreationForm {
  SavedUniverseCreationForm({required this.form, required this.generation}) {
    if (generation < BigInt.zero || generation >= BigInt.one << 64) {
      throw const FormatException('Invalid creation form generation');
    }
  }
  final UniverseCreationForm form;
  final BigInt generation;
}
