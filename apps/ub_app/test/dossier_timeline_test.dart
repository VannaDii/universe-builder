import 'package:test/test.dart';
import 'package:ub_app/dossier_timeline.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('ordering keeps independent calendars, equal points and unsupported placements separate', () {
    final universe = UniverseId.generate(),
        calendar = CalendarId.generate(),
        other = CalendarId.generate();
    RecordVersion event(TemporalExpression time) => RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.event,
      ),
      payload: EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.reported),
        time: time,
        participants: [],
        labels: {},
      ),
    );
    final late = event(ExactTime(calendar, '9007199254740994'));
    final first = event(ExactTime(calendar, '9007199254740993'));
    final equal = event(ExactTime(calendar, '9007199254740993'));
    final elsewhere = event(ExactTime(other, '-2'));
    final unknown = event(const UnspecifiedTime());
    final dateToken = event(ExactTime(calendar, '2040-01-01'));
    final limit = event(ExactTime(calendar, (BigInt.one << 127).toString()));
    final order = dossierEventOrder([
      late,
      first,
      equal,
      elsewhere,
      unknown,
      dateToken,
      limit,
    ]);
    expect(order.points[calendar], [first, equal, late]);
    expect(order.points[other], [elsewhere]);
    expect(order.other, [unknown, dateToken, limit]);
  });

  test('time descriptions retain uncertain boundaries, authored clocks and relative references', () {
    final calendar = CalendarId.generate();
    final target = RecordRef(record: RecordId.generate());
    String name(RecordRef ref) => ref == target ? 'Departure' : 'Unavailable';
    expect(
      eventTimeText(
        IntervalTime(calendar, const UnknownBound(), const UnboundedBound()),
        name,
      ),
      'Interval: unknown boundary → unbounded',
    );
    expect(
      eventTimeText(
        IntervalTime(
          calendar,
          const UncertainBound('10', '20'),
          const ApproximateBound('30', TextValue('two days')),
        ),
        name,
      ),
      contains('between 10 and 20 → approximately 30'),
    );
    expect(
      eventTimeText(
        RelativeTime(calendar, TemporalRelation.before, target),
        name,
      ),
      'before: Departure',
    );
    expect(
      eventTimeText(
        DurationTime(calendar, const TextValue('three days')),
        name,
      ),
      'Duration only; no absolute placement',
    );
    final clock = Chronology(
      calendar: calendar,
      system: FictionalClock('ticks', null),
      firstInteraction: '0',
      current: '20',
    );
    expect(
      eventTimeText(ExactTime(calendar, '12'), name, chronology: clock),
      'Point: 12 ticks',
    );
    expect(
      eventTimeText(
        ExactTime(calendar, 'authored date'),
        name,
        chronology: clock,
      ),
      'Point: authored date',
    );
    expect(
      eventTimeText(
        ExactTime(CalendarId.generate(), '12'),
        name,
        chronology: clock,
      ),
      'Point: 12',
    );
  });
}
