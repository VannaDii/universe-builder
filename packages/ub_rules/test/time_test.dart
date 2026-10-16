import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String id(int n) => n.toRadixString(16).padLeft(24, '0');
final universe = UniverseId.parse('unv_${id(1)}');
CalendarId cal(int n) => CalendarId.parse('cal_${id(n)}');
RecordRef ref(int n) =>
    RecordRef(universe: universe, record: RecordId.parse('rec_${id(n)}'));
ExactTime at(int n, {int clock = 1}) => ExactTime(cal(clock), '$n');
RecordVersion record(int n, RecordPayload payload) => RecordVersion.build(
  recordVersionId: RecordVersionId.parse('ver_${id(n)}'),
  identity: RecordIdentity(
    universeId: universe,
    recordId: ref(n).record,
    recordKind: payload.recordKind,
  ),
  payload: payload,
);
List<RecordVersion> edge(
  int n,
  int from,
  int to, {
  int clock = 1,
  int context = 3,
  int predicate = 10,
  TemporalRelation relation = TemporalRelation.before,
  Polarity polarity = Polarity.support,
  Precision precision = Precision.exact,
  List<DomainValue> alternatives = const [],
  Validity validity = const UnspecifiedValidity(),
}) => [
  record(
    n,
    PropositionRecord(
      predicate: ref(predicate),
      subject: ref(from),
      value: TemporalValue(RelativeTime(cal(clock), relation, ref(to))),
      quantification: Quantification.particular,
      context: ref(context),
    ),
  ),
  record(
    n + 100000,
    AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: ref(n),
      polarity: polarity,
      scope: Scope(
        applicability: const UniverseApplicability(),
        context: ref(context),
      ),
      validity: validity,
      persistence: PersistenceSemantics.unspecified,
      precision: precision,
      alternatives: alternatives,
      basis: const AuthorDecisionBasis('order'),
    ),
  ),
];

void main() {
  test(
    'half-open validity, timeless selection and unqualified unknown clocks',
    () {
      final v = CalendarIntervalValidity(
        cal(1),
        const ExactBound('10'),
        const ExactBound('20'),
      );
      for (final (n, expected) in [
        (9, false),
        (10, true),
        (19, true),
        (20, false),
      ]) {
        expect(temporalApplies(v, AtFrameTime(at(n))), expected);
      }
      expect(
        temporalApplies(const UnspecifiedValidity(), AtFrameTime(at(10))),
        isNull,
      );
      expect(
        temporalApplies(const UnknownValidity(), AtFrameTime(at(10))),
        isNull,
      );
      expect(temporalApplies(v, AtFrameTime(at(10, clock: 2))), isNull);
      expect(
        temporalApplies(const UnknownValidity(), const TimelessFrameTime()),
        isTrue,
      );
      expect(
        temporalApplies(v, AtEventFrameTime(ref(1), EventTimeSide.before)),
        isNull,
      );
      expect(
        temporalOverlaps(
          const UnspecifiedValidity(),
          const UnspecifiedValidity(),
        ),
        isTrue,
      );
      expect(temporalOverlaps(const UnknownValidity(), v), isNull);
      expect(
        temporalApplies(
          const IntervalValidity(ExactBound('10'), ExactBound('20')),
          AtFrameTime(at(15)),
        ),
        isNull,
      );
    },
  );

  test(
    'uncertain boundaries never select a convenient date or become infinity',
    () {
      final v = CalendarIntervalValidity(
        cal(1),
        const UncertainBound('10', '12'),
        const ExactBound('20'),
      );
      expect(temporalApplies(v, AtFrameTime(at(9))), isFalse);
      expect(temporalApplies(v, AtFrameTime(at(11))), isNull);
      expect(temporalApplies(v, AtFrameTime(at(12))), isTrue);
      final unknown = CalendarIntervalValidity(
        cal(1),
        const UnknownBound(),
        const UnboundedBound(),
      );
      expect(temporalApplies(unknown, AtFrameTime(at(12))), isNull);
      final forever = CalendarIntervalValidity(
        cal(1),
        const UnboundedBound(),
        const UnboundedBound(),
      );
      expect(temporalApplies(forever, AtFrameTime(at(-42))), isTrue);
      final crossing = IntervalTime(
        cal(1),
        const UncertainBound('10', '20'),
        const UncertainBound('15', '25'),
      );
      expect(
        temporalRelation(at(16), TemporalRelation.during, crossing),
        isNull,
      );
    },
  );

  test(
    'point and interval boundaries preserve strict and non-strict relations',
    () {
      final range = IntervalTime(
        cal(1),
        const ExactBound('10'),
        const ExactBound('20'),
      );
      final next = IntervalTime(
        cal(1),
        const ExactBound('20'),
        const ExactBound('30'),
      );
      expect(temporalRelation(range, TemporalRelation.before, at(20)), isTrue);
      expect(
        temporalRelation(at(20), TemporalRelation.before, at(20)),
        isFalse,
      );
      expect(temporalRelation(at(20), TemporalRelation.after, range), isTrue);
      expect(temporalRelation(range, TemporalRelation.overlaps, next), isFalse);
      expect(temporalRelation(range, TemporalRelation.during, range), isTrue);
      expect(
        temporalRelation(range, TemporalRelation.simultaneous, range),
        isFalse,
      );
      expect(
        temporalRelation(at(10), TemporalRelation.simultaneous, at(10)),
        isTrue,
      );
      expect(
        temporalOverlaps(InstantValidity(at(10)), InstantValidity(at(10))),
        isTrue,
      );
      expect(
        temporalRelation(at(20), TemporalRelation.overlaps, range),
        isFalse,
      );
      expect(
        temporalRelation(range, TemporalRelation.overlaps, at(10)),
        isTrue,
      );
      final empty = IntervalTime(
        cal(1),
        const ExactBound('10'),
        const ExactBound('10'),
      );
      expect(
        temporalRelation(empty, TemporalRelation.overlaps, range),
        isFalse,
      );
      expect(temporalRelation(empty, TemporalRelation.during, range), isTrue);
    },
  );

  test('signed i128 values stay exact on all platforms and sentinel endpoints are reserved', () {
    final max = (BigInt.one << 127) - BigInt.one;
    final min = -(BigInt.one << 127);
    ExactTime text(String s) => ExactTime(cal(1), s);
    for (final invalid in [
      '$min',
      '$max',
      '${max + BigInt.one}',
      '0x10',
      ' 10',
      '10\n',
      '1_000',
      '1.0',
      '',
    ]) {
      expect(
        temporalRelation(
          text(invalid),
          TemporalRelation.simultaneous,
          text(invalid),
        ),
        isNull,
      );
    }
    final nearMax = text('${max - BigInt.one}');
    expect(
      temporalRelation(nearMax, TemporalRelation.simultaneous, nearMax),
      isTrue,
    );
    final large = text('9007199254740993');
    expect(
      temporalRelation(
        text('9007199254740992'),
        TemporalRelation.before,
        large,
      ),
      isTrue,
    );
    expect(
      temporalRelation(text('+00010'), TemporalRelation.simultaneous, at(10)),
      isTrue,
    );
    expect(
      temporalRelation(
        ApproximateTime(cal(1), '10', const IntegerValue('1')),
        TemporalRelation.before,
        at(20),
      ),
      isNull,
    );
  });

  test(
    'strict cycles require exact positive evidence within the same partition',
    () {
      final records = edge(20, 1, 2);
      checkTemporalOrderings(records);
      records.addAll(edge(21, 2, 1, polarity: Polarity.refutation));
      records.addAll(edge(22, 2, 1, clock: 2));
      records.addAll(edge(23, 2, 1, context: 4));
      records.addAll(edge(24, 2, 1, predicate: 11));
      records.addAll(edge(25, 2, 1, precision: Precision.approximate));
      records.addAll(edge(26, 2, 1, alternatives: [const IntegerValue('1')]));
      records.addAll(edge(27, 2, 1, validity: const UnknownValidity()));
      checkTemporalOrderings(records);
      records.addAll(edge(28, 2, 1));
      expect(
        () => checkTemporalOrderings(records),
        throwsA(isA<TemporalOrderingError>()),
      );
      records.removeWhere((r) => r.payload is AssertionRecord);
      checkTemporalOrderings(records);
      expect(
        () => checkTemporalOrderings(edge(29, 1, 1)),
        throwsA(isA<TemporalOrderingError>()),
      );
    },
  );

  test(
    'after reverses ordering and duplicate edges do not manufacture cycles',
    () {
      checkTemporalOrderings([
        ...edge(20, 1, 2),
        ...edge(21, 2, 1, relation: TemporalRelation.after),
      ]);
      expect(
        () => checkTemporalOrderings([
          ...edge(20, 1, 2),
          ...edge(21, 1, 2, relation: TemporalRelation.after),
        ]),
        throwsA(isA<TemporalOrderingError>()),
      );
      checkTemporalOrderings([
        ...edge(20, 1, 2),
        ...edge(21, 2, 1, relation: TemporalRelation.during),
      ]);
    },
  );

  test(
    'relative-order node budget is bounded at 10000 declared partition nodes',
    () {
      final records = <RecordVersion>[];
      for (var n = 0; n < 9999; n++) {
        records.addAll(edge(20000 + n, n + 1, n + 2));
      }
      checkTemporalOrderings(records);
      records.addAll(edge(40000, 10000, 10001));
      expect(
        () => checkTemporalOrderings(records),
        throwsA(
          isA<TemporalOrderingError>().having(
            (e) => e.message,
            'budget',
            'relative-order work budget exhausted',
          ),
        ),
      );
    },
  );
}
