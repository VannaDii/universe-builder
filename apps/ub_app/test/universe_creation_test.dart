import 'package:test/test.dart';
import 'package:ub_app/universe_creation.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('recovered creation attempt cannot become another request before a library check', () {
    const form = UniverseCreationForm(
      name: 'History',
      calendar: CreationCalendar.gregorian,
      date: '2040-02-29',
      time: '12:30:00',
      offset: '-03:30',
    );
    final pending = UniverseCreationForm.fromWire(
      form.withPending(true).toWire(),
    );
    expect(pending.creationPending, isTrue);
    expect(pending.request, throwsFormatException);
    expect(pending.withPending(false).request().name, form.name);
  });

  test('creation requires an authored valid date, whole-second time and fixed offset', () {
    for (final parts in [
      ('', '', ''),
      ('2041-02-29', '12:00:00', '+00:00'),
      ('2040-01-01', '12:00:00', ''),
      ('2040-01-01', '12:00:00.5', 'Z'),
    ]) {
      final form = UniverseCreationForm(
        name: 'History',
        calendar: CreationCalendar.gregorian,
        date: parts.$1,
        time: parts.$2,
        offset: parts.$3,
      );
      expect(form.request, throwsFormatException);
    }
    final request = const UniverseCreationForm(
      name: 'History',
      calendar: CreationCalendar.gregorian,
      date: '2040-02-29',
      time: '12:30:00',
      offset: '-03:30',
    ).request();
    expect(
      (request.start as GregorianUniverseStart).timestamp,
      '2040-02-29T12:30:00-03:30',
    );
  });

  test('fictional creation retains exact ticks and does not invent a month conversion', () {
    final request = const UniverseCreationForm(
      name: 'Ages',
      calendar: CreationCalendar.fictional,
      calendarName: 'Before the dawn',
      initialTick: '-123456789012345678901234567890',
      tickLabel: 'beat',
    ).request();
    final start = request.start as FictionalUniverseStart;
    expect(start.initialTick, '-123456789012345678901234567890');
    expect(start.ticksPerMonth, isNull);
    expect(start.build(CalendarId.generate()).$1.current, start.initialTick);
    for (final month in ['0', '-1', '1.5', '4294967296']) {
      expect(
        UniverseCreationForm(
          name: 'Ages',
          calendar: CreationCalendar.fictional,
          calendarName: 'Before the dawn',
          initialTick: '0',
          tickLabel: 'beat',
          ticksPerMonth: month,
        ).request,
        throwsFormatException,
      );
    }
  });
}
