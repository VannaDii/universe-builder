import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'rule_checks_test.dart' as f;

final gregorian = GregorianUniverseStart('1970-01-01T00:00:00+00:00')
    .build(f.calendar)
    .$1;
RecordVersion context(Chronology chronology) => f.record(
  99,
  RepresentedContextRecord(
    universe: f.universe,
    kind: const ObjectiveContext(),
    chronology: chronology,
    labels: {},
  ),
);
CanonicalValue json(String value) => CanonicalValue.parseWireJson(value);
CanonicalValue normalize(
  String value, {
  List<RecordVersion>? rows,
  Frame? frame,
}) => normalizeWritingDates(
  json(value),
  frame ?? f.frame(),
  rows ?? [context(gregorian)],
);
Matcher fails(String message) => throwsA(
  isA<FormatException>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

void main() {
  test('nested dates normalize with the pinned clock and preserve authored content', () {
    final result = normalize('''{
      "at_date":"1970-01-01T00:00:10+00:00", "at_tick":"00010",
      "messages":[{"sent_date":"1970-01-01T01:00:12+01:00",
        "received_date":"1970-01-01T00:00:20Z"}],
      "lifetime":{"kind":"until","end_date":"1970-01-01T00:00:30Z"},
      "participants":{"at_date":"Mara"}, "value":{"end_date":"authored phrase"},
      "claim":{"at_date":"not a timestamp"}, "content":{"end_tick":""},
      "metadata":{"at_date":false}, "labels":{"end_date":1}, "text":{"at_tick":""},
      "minimum_delay":"3", "exact_amount":9007199254740993
    }''');
    expect(
      result.toText(),
      json('''{
      "at_tick":"00010", "messages":[{"sent_tick":"12","received_tick":"20"}],
      "lifetime":{"kind":"until","end_tick":"30"},
      "participants":{"at_date":"Mara"}, "value":{"end_date":"authored phrase"},
      "claim":{"at_date":"not a timestamp"}, "content":{"end_tick":""},
      "metadata":{"at_date":false}, "labels":{"end_date":1}, "text":{"at_tick":""},
      "minimum_delay":"3", "exact_amount":9007199254740993
    }''').toText(),
    );
  });

  test('missing or incompatible clocks never infer dates', () {
    const input = '{"events":[{"at_date":"1970-01-01T00:00:10Z"}]}';
    expect(
      () => normalize(input, rows: []),
      fails('writing.events[0].at_date'),
    );
    final other = CalendarId.parse('cal_${f.suffix(11)}');
    expect(
      () => normalize(
        input,
        frame: f.frame(time: AtFrameTime(ExactTime(other, '10'))),
      ),
      fails('readable chronology'),
    );
    expect(
      () => normalize(
        input,
        frame: f.frame(time: const AtFrameTime(UnspecifiedTime())),
      ),
      fails('readable chronology'),
    );
    expect(
      normalize('{"at_tick":"10"}', rows: []).toText(),
      '{"at_tick":"10"}',
    );
    expect(normalize('null', rows: []).toText(), 'null');
  });

  test(
    'explicit coordinates must agree exactly and remain bounded to i128',
    () {
      expect(() => normalize('{"at_date":"tomorrow"}'), fails('RFC3339'));
      expect(() => normalize('{"at_date":10}'), fails('authored date string'));
      expect(
        () => normalize('{"at_date":"1970-01-01T00:00:10Z","at_tick":"11"}'),
        fails('disagree'),
      );
      expect(
        () => normalize('{"at_date":"1970-01-01T00:00:10Z","at_tick":" 10"}'),
        fails('disagree'),
      );
      expect(
        () => normalize('{"at_tick":""}'),
        fails('supply at_tick or at_date'),
      );
      expect(
        normalize('{"at_date":null,"at_tick":"10"}').toText(),
        '{"at_tick":"10"}',
      );
      expect(
        normalize('{"at_date":"1970-01-01T00:00:10Z","at_tick":""}').toText(),
        '{"at_tick":"10"}',
      );
      final clock = FictionalUniverseStart(
        calendarName: 'Ashen days',
        initialTick: '0',
        tickLabel: 'days',
      ).build(f.calendar).$1;
      expect(
        normalize(
          '{"at_date":"9007199254740993","at_tick":"+09007199254740993"}',
          rows: [context(clock)],
        ).toText(),
        '{"at_tick":"+09007199254740993"}',
      );
      final outOfRange = BigInt.one << 127;
      expect(
        () => normalize('{"at_date":"$outOfRange"}', rows: [context(clock)]),
        fails('exact fictional clock coordinate'),
      );
      expect(
        () => normalize(
          '{"at_date":"10","at_tick":"$outOfRange"}',
          rows: [context(clock)],
        ),
        fails('disagree'),
      );
    },
  );

  test('correction dates cannot reinterpret an original calendar or hidden record', () {
    final other = CalendarId.parse('cal_${f.suffix(11)}');
    final original = f.assertion(
      validity: CalendarIntervalValidity(
        other,
        const ExactBound('0'),
        const ExactBound('20'),
      ),
    );
    for (final handle in [
      original.identity.recordId.value,
      original.recordVersionId.value,
    ]) {
      expect(
        () => normalize(
          '{"fact_handle":"$handle","lifetime":{"end_date":"1970-01-01T00:00:10Z"}}',
          rows: [context(gregorian), original],
        ),
        fails('original authored calendar'),
      );
      expect(
        normalize(
          '{"fact_handle":"$handle","end_date":"1970-01-01T00:00:10Z"}',
          rows: [context(gregorian)],
        ).toText(),
        json('{"fact_handle":"$handle","end_tick":"10"}').toText(),
      );
      expect(
        () => normalize(
          '{"start":{"event_handle":"$handle"},"at_date":"1970-01-01T00:00:10Z"}',
          rows: [context(gregorian), original],
        ),
        fails('original authored calendar'),
      );
    }
  });

  test('typed change requests retain identities and participant names after normalization', () {
    final input = CheckChangesRequest(
      universe: const Selector('Ashen'),
      contextId: ContextId.generate(),
      events: [
        WritingEvent(
          action: 'Leave',
          participants: {'at_date': 'Mara'},
          atDate: '1970-01-01T00:00:10Z',
        ),
      ],
    );
    final normalized = normalizeWritingChangesDates(input, f.frame(), [
      context(gregorian),
    ]);
    expect(normalized.contextId, input.contextId);
    expect(normalized.universe, input.universe);
    expect(normalized.events.single.atTick, '10');
    expect(normalized.events.single.atDate, isNull);
    expect(normalized.events.single.participants, {'at_date': 'Mara'});
    expect(input.events.single.atDate, isNotNull);
    expect(input.events.single.atTick, isNull);
  });
}
