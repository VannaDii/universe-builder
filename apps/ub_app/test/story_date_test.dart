import 'package:test/test.dart';
import 'package:ub_app/story_date.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('Gregorian month preview retains authored offset and rejects nonexistent dates', () {
    final clock = const GregorianUniverseStart('2042-03-31T12:00:00+05:30')
        .build(CalendarId.generate())
        .$1;
    final original = clock.toWire().toText();
    expect(resolveStoryMonthsAgo(clock, '0'), '2042-03-31T12:00:00+05:30');
    expect(resolveStoryMonthsAgo(clock, '+2'), '2042-01-31T12:00:00+05:30');
    expect(() => resolveStoryMonthsAgo(clock, '1'), throwsFormatException);
    expect(clock.toWire().toText(), original);
  });
  test('fictional month preview uses exact declared ticks beyond web safe integers', () {
    final clock = FictionalUniverseStart(
      calendarName: 'Days',
      initialTick: '9007199254740993',
      tickLabel: 'days',
      ticksPerMonth: 30,
    ).build(CalendarId.generate()).$1;
    expect(resolveStoryMonthsAgo(clock, '1'), '9007199254740963 days');
    expect(resolveStoryMonthsAgo(clock, '4294967295'), '9007070405722143 days');
    final independent = FictionalUniverseStart(
      calendarName: 'Cycles',
      initialTick: '100',
      tickLabel: 'cycles',
    ).build(CalendarId.generate()).$1;
    expect(
      () => resolveStoryMonthsAgo(independent, '1'),
      throwsFormatException,
    );
    for (final value in [
      '',
      '-1',
      '1.5',
      ' 1',
      '4294967296',
      '9007199254740993',
    ]) {
      expect(() => resolveStoryMonthsAgo(clock, value), throwsFormatException);
    }
    expect(clock.current, '9007199254740993');
  });
}
