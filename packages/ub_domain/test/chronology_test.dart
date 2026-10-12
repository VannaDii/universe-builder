import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

final calendar = CalendarId.parse('cal_000000000000000000000001');
Chronology fictional({String start = '90', int? month}) =>
    FictionalUniverseStart(
      calendarName: 'Orbital',
      initialTick: start,
      tickLabel: 'days',
      ticksPerMonth: month,
    ).build(calendar).$1;
Chronology gregorian() =>
    const GregorianUniverseStart('2040-03-15T12:30:00+02:00')
        .build(calendar)
        .$1;
Matcher fails(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  test('explicit Gregorian start creates a pinned calendar and display', () {
    final (clock, definition) = const GregorianUniverseStart(
      '2040-03-15T12:30:00+02:00',
    ).build(calendar);
    clock.validate();
    expect(clock.display(clock.current), '2040-03-15T12:30:00+02:00');
    expect(clock.firstInteraction, clock.current);
    expect(
      clock.system,
      isA<GregorianClock>().having((s) => s.offsetSeconds, 'offset', 7200),
    );
    expect(definition.namespace, 'chronology');
    expect(definition.key, 'universe_clock');
    expect(definition.labels, {'en': 'Gregorian'});
    expect(definition.epoch, clock.display(clock.firstInteraction));
    expect(definition.conversions, isEmpty);
    expect(
      Chronology.fromWire(clock.toWire()).toWire().toText(),
      clock.toWire().toText(),
    );
  });

  test(
    'elapsed and time travel are explicit and preserve the first interaction',
    () {
      final initial = gregorian();
      expect(
        () => initial.change(
          '2040-03-14T12:30:00+02:00',
          TimeChangeKind.elapsed,
          'Back',
        ),
        fails('must move forward'),
      );
      final back = initial.change(
        '2040-03-14T12:30:00+02:00',
        TimeChangeKind.timeTravel,
        'Time machine',
      );
      final forward = back.change(
        '2040-03-16T12:30:00+02:00',
        TimeChangeKind.elapsed,
        'Two days pass',
      );
      expect(back.firstInteraction, initial.firstInteraction);
      expect(forward.firstInteraction, initial.firstInteraction);
      expect(initial.current, initial.firstInteraction);
      expect(forward.display(forward.current), '2040-03-16T12:30:00+02:00');
      expect(
        () => initial.change(
          '2040-03-15T10:30:00Z',
          TimeChangeKind.timeTravel,
          'Same',
        ),
        fails('unchanged'),
      );
      expect(
        () => initial.change(
          '2041-03-15T12:30:00+02:00',
          TimeChangeKind.elapsed,
          '\u0085\u2007',
        ),
        fails('Explain'),
      );
      expect(
        initial
            .change(
              '2041-03-15T12:30:00+02:00',
              TimeChangeKind.elapsed,
              '\ufeff',
            )
            .current,
        isNot(initial.current),
      );
    },
  );

  test('timestamp grammar rejects overflow dates and unsupported seconds', () {
    final c = gregorian();
    for (final value in [
      '2040-02-30T00:00:00Z',
      '2041-02-29T00:00:00Z',
      '2040-00-01T00:00:00Z',
      '2040-01-00T00:00:00Z',
      '2040-01-01T24:00:00Z',
      '2040-01-01T00:60:00Z',
      '2040-01-01T00:00:00',
      '2040-01-01T00:00:00+24:00',
      '2040-01-01T00:00:00+02:60',
      '2040-01-01T00:00:00+0200',
      ' 2040-01-01T00:00:00Z',
      '2040-01-01T00:00:00Z\n',
    ]) {
      expect(() => c.coordinate(value), throwsFormatException, reason: value);
    }
    for (final value in [
      '2040-01-01T00:00:60Z',
      '2040-01-01T00:00:00.1Z',
      '2040-01-01T00:00:00.000000001Z',
    ]) {
      expect(() => c.coordinate(value), fails('whole seconds'));
    }
    final expected = c.coordinate('2040-01-01T00:00:00Z');
    for (final value in [
      '2040-01-01t00:00:00z',
      '2040-01-01 00:00:00.000Z',
      '2040-01-01T00:00:00.0000000001Z',
      '2040-01-01T01:00:00+01:00',
      '2039-12-31T23:00:00−01:00',
    ]) {
      expect(c.coordinate(value), expected);
    }
  });

  test(
    'Gregorian months use pinned time and reject nonexistent month days',
    () {
      final c = gregorian();
      expect(c.display(c.monthsAgo(c.current, 1)), '2040-02-15T12:30:00+02:00');
      final end = c.coordinate('2040-03-31T12:30:00+02:00');
      expect(() => c.monthsAgo(end, 1), fails('day does not exist'));
      final leap = c.coordinate('2040-02-29T12:30:00+02:00');
      expect(() => c.monthsAgo(leap, 12), fails('day does not exist'));
      expect(c.monthsAgo(c.current, 0), c.current);
      expect(c.current, c.firstInteraction);
      final crossing = c.coordinate('0000-01-15T00:00:00Z');
      expect(c.display(c.monthsAgo(crossing, 1)), '-0001-12-15T02:00:00+02:00');
    },
  );

  test('fictional starts normalize exact i128 and preserve authored units', () {
    final (c, definition) = FictionalUniverseStart(
      calendarName: '\u0085 Orbital \u2007',
      initialTick: '+00090',
      tickLabel: ' days ',
      ticksPerMonth: 30,
    ).build(calendar);
    c.validate();
    expect(c.current, '90');
    expect(c.display('+00090'), '+00090 days');
    expect(definition.labels, {'en': 'Orbital'});
    expect(definition.epoch, '90 days');
    expect(c.monthsAgo(c.current, 2), '30');
    expect(c.current, '90');
    expect(
      c.change('-1', TimeChangeKind.timeTravel, 'Flashback').current,
      '-1',
    );
    expect(
      c.change('91', TimeChangeKind.elapsed, 'Next day').firstInteraction,
      '90',
    );
    expect(() => fictional().monthsAgo('90', 1), fails('no declared month'));
  });

  test('fictional coordinates retain exact extremes on native and web', () {
    final low = -(BigInt.one << 127), high = (BigInt.one << 127) - BigInt.one;
    for (final n in [low, high, BigInt.parse('9007199254740993')]) {
      final c = fictional(start: '$n', month: 1);
      c.validate();
      expect(c.coordinate('$n'), '$n');
      expect(Chronology.fromWire(c.toWire()).current, '$n');
    }
    expect(
      () => fictional(start: '${high + BigInt.one}'),
      throwsFormatException,
    );
    expect(
      () => fictional(start: '${low - BigInt.one}'),
      throwsFormatException,
    );
    expect(
      () => fictional(start: '$low', month: 1).monthsAgo('$low', 1),
      fails('out of range'),
    );
    final c = fictional();
    for (final value in [' 90', '90 ', '90\n', '1.0', '1e2', '', '+', '−1']) {
      expect(() => c.coordinate(value), throwsFormatException);
    }
    expect(() => c.monthsAgo('90', -1), throwsFormatException);
    expect(() => c.monthsAgo('90', 4294967296), throwsFormatException);
  });

  test('fictional labels use source UTF8 limits and whitespace semantics', () {
    for (final (name, label, month) in [
      (' ', 'days', null),
      ('Orbit', '\u0085', null),
      ('Orbit', 'days', 0),
      ('é' * 101, 'days', null),
      ('Orbit', 'é' * 41, null),
    ]) {
      expect(
        () => FictionalUniverseStart(
          calendarName: name,
          initialTick: '0',
          tickLabel: label,
          ticksPerMonth: month,
        ).build(calendar),
        throwsFormatException,
      );
    }
    final (c, def) = FictionalUniverseStart(
      calendarName: 'é' * 100,
      initialTick: '0',
      tickLabel: 'é' * 40,
    ).build(calendar);
    c.validate();
    expect(utf8.encode(def.labels['en']!), hasLength(200));
    expect(
      () => Chronology(
        calendar: calendar,
        system: FictionalClock('', null),
        firstInteraction: '0',
        current: '0',
      ).validate(),
      fails('units'),
    );
  });

  test('Gregorian display preserves source bounds and offset behavior', () {
    final c = gregorian();
    final min = DateTime.utc(-262143).millisecondsSinceEpoch ~/ 1000;
    final max = DateTime.utc(262143).millisecondsSinceEpoch ~/ 1000 - 1;
    expect(c.display('$min'), startsWith('-262143-01-01T02:00:00'));
    expect(c.display('$max'), startsWith('+262143-01-01T01:59:59'));
    expect(c.monthsAgo('$max', 0), '$max');
    for (final value in [
      '${min - 1}',
      '${max + 1}',
      '9223372036854775808',
      '-9223372036854775809',
    ]) {
      expect(() => c.display(value), fails('out of range'));
    }
    final historical = Chronology(
      calendar: calendar,
      system: GregorianClock(-31),
      firstInteraction: '0',
      current: '0',
    );
    expect(historical.display('0'), '1969-12-31T23:59:29-00:01');
    expect(
      () => Chronology(
        calendar: calendar,
        system: GregorianClock(86400),
        firstInteraction: '0',
        current: '0',
      ).validate(),
      fails('offset'),
    );
  });
}
