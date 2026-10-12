import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
final scope = Scope(
  applicability: const UniverseApplicability(),
  context: ref(3),
);
RecordVersion record(int n, RecordPayload payload, {RecordId? identity}) =>
    RecordVersion.build(
      recordVersionId: RecordVersionId.parse('ver_${suffix(n)}'),
      identity: RecordIdentity(
        universeId: universe,
        recordId: identity ?? id(n),
        recordKind: payload.recordKind,
      ),
      payload: payload,
    );
PropositionRecord proposition({DomainValue value = const BooleanValue(true)}) =>
    PropositionRecord(
      subject: ref(1),
      predicate: ref(2),
      value: value,
      quantification: Quantification.particular,
      context: ref(3),
    );
EntityEffect effect(
  int time, {
  String slot = 'active',
  int target = 4,
  BigInt? order,
  Polarity polarity = Polarity.support,
  Scope? cell,
  Validity? validity,
}) => EntityEffect(
  slot: slot,
  proposition: ref(target),
  polarity: polarity,
  scope: cell ?? scope,
  validity:
      validity ??
      CalendarIntervalValidity(
        calendar,
        ExactBound('$time'),
        const UnboundedBound(),
      ),
  order: order ?? BigInt.zero,
);
EventRecord event(
  int time, {
  Polarity polarity = Polarity.support,
  OccurrenceKind mode = OccurrenceKind.occurred,
  List<EntityEffect>? effects,
  String? version = eventExpansionVersion,
}) => EventRecord(
  occurrence: SimpleOccurrence(mode),
  time: ExactTime(calendar, '$time'),
  participants: [],
  labels: {},
  expansionVersion: version,
  effects: effects ?? [effect(time, polarity: polarity)],
);
List<RecordVersion> fixture() => [
  record(4, proposition()),
  record(5, event(10)),
  record(6, event(20, polarity: Polarity.refutation)),
];
Matcher fails([String? message]) => throwsA(
  message == null
      ? isA<EventEvaluationError>()
      : isA<EventEvaluationError>().having(
          (e) => e.message,
          'failure',
          message,
        ),
);

void main() {
  test('event-relative before and after retain exact half-open boundaries', () {
    final records = fixture(), index = RecordIndex(fixture());
    final validity = CalendarIntervalValidity(
      calendar,
      const ExactBound('10'),
      const ExactBound('20'),
    );
    for (final (n, side, expected) in [
      (5, EventTimeSide.before, false),
      (5, EventTimeSide.after, true),
      (6, EventTimeSide.before, true),
      (6, EventTimeSide.after, false),
    ]) {
      final time = AtEventFrameTime(ref(n), side);
      expect(eventApplies(validity, time, records), expected);
      expect(eventAppliesIndexed(validity, time, index), expected);
    }
    expect(
      eventApplies(
        InstantValidity(ExactTime(calendar, '10')),
        AtEventFrameTime(ref(5), EventTimeSide.before),
        records,
      ),
      isFalse,
    );
    expect(
      eventApplies(
        InstantValidity(ExactTime(calendar, '10')),
        AtEventFrameTime(ref(5), EventTimeSide.after),
        records,
      ),
      isTrue,
    );
  });

  test('missing namespaces, non-occurrences and unresolved boundaries never establish time', () {
    final records = [record(5, event(10, mode: OccurrenceKind.planned))];
    final v = CalendarIntervalValidity(
      calendar,
      const ExactBound('0'),
      const UnboundedBound(),
    );
    expect(
      eventApplies(v, AtEventFrameTime(ref(5), EventTimeSide.after), records),
      isNull,
    );
    expect(
      eventApplies(
        v,
        AtEventFrameTime(RecordRef(record: id(5)), EventTimeSide.after),
        fixture(),
      ),
      isNull,
    );
    expect(
      eventApplies(
        v,
        AtEventFrameTime(
          RecordRef(
            universe: UniverseId.parse('unv_${suffix(2)}'),
            record: id(5),
          ),
          EventTimeSide.after,
        ),
        fixture(),
      ),
      isNull,
    );
    expect(
      eventApplies(
        CalendarIntervalValidity(
          calendar,
          const UnknownBound(),
          const UnboundedBound(),
        ),
        AtEventFrameTime(ref(5), EventTimeSide.before),
        fixture(),
      ),
      isNull,
    );
    expect(
      eventApplies(
        const UnknownValidity(),
        const TimelessFrameTime(),
        fixture(),
      ),
      isTrue,
    );
    expect(() => exactEventTime(const UnspecifiedTime()), fails());
    expect(
      () => exactEventTime(
        ExactTime(calendar, '${(BigInt.one << 127) - BigInt.one}'),
      ),
      fails(),
    );
    expect(
      exactEventTime(ExactTime(calendar, '9007199254740993')).coordinate,
      BigInt.parse('9007199254740993'),
    );
  });

  test('effect identity, exact provenance and recompilation are input-order independent', () {
    final records = fixture();
    final expected = expandEvents(records);
    expect(
      eventEffectId(id(5), 'active').value,
      'rec_e9e0bee417329ec1513c96f4',
    );
    final old = expected[eventEffectId(id(5), 'active')]!;
    expect(
      old.validity,
      CalendarIntervalValidity(
        calendar,
        const ExactBound('10'),
        const ExactBound('20'),
      ),
    );
    expect(old.establishedBy, EventEffectRef(ref(5), 'active'));
    expect(
      old.basis,
      AuthorDecisionBasis('Compiled event ${id(5).value} slot active'),
    );
    expect(old.persistence, PersistenceSemantics.explicitInterval);
    for (final order in [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ]) {
      expect(expandEvents(order.map((i) => records[i]).toList()), expected);
    }
  });

  test(
    'verification rejects missing, forged and duplicate generated assertions',
    () {
      final records = fixture(), generated = expandEvents(fixture());
      final complete = [...records];
      var n = 20;
      for (final entry in generated.entries) {
        complete.add(record(n++, entry.value, identity: entry.key));
      }
      verifyEventEffects(complete);
      expect(() => verifyEventEffects(records), fails());
      expect(() => verifyEventEffects([...complete, complete.last]), fails());
      final a = complete.last.payload as AssertionRecord;
      final forged = AssertionRecord(
        attributeMode: a.attributeMode,
        proposition: a.proposition,
        polarity: a.polarity == Polarity.support
            ? Polarity.refutation
            : Polarity.support,
        scope: a.scope,
        validity: a.validity,
        persistence: a.persistence,
        precision: a.precision,
        basis: a.basis,
        establishedBy: a.establishedBy,
      );
      complete[complete.length - 1] = record(
        99,
        forged,
        identity: complete.last.identity.recordId,
      );
      expect(() => verifyEventEffects(complete), fails());
    },
  );

  test('plans, reports and predictions never expand objective effects', () {
    for (final mode in [
      OccurrenceKind.planned,
      OccurrenceKind.reported,
      OccurrenceKind.predicted,
      OccurrenceKind.hypothetical,
    ]) {
      expect(
        expandEvents([record(5, event(10, mode: mode, version: null))]),
        isEmpty,
      );
    }
    expect(() => expandEvents([record(5, event(10, version: null))]), fails());
    expect(
      () => expandEvents([record(5, event(10, version: 'future'))]),
      fails(),
    );
    expect(
      () => expandEvents([
        record(4, proposition()),
        record(5, event(10)),
        record(6, event(10, polarity: Polarity.refutation)),
      ]),
      fails(),
    );
  });

  test('effect slots, orders, contexts, scope and temporal boundaries must be explicit', () {
    final bad = <List<EntityEffect>>[
      [effect(10, slot: ' ')],
      [effect(10, slot: '\u0085\u3000')],
      [effect(10, slot: 'é' * 61)],
      [effect(10), effect(10, order: BigInt.one)],
      [effect(10), effect(10, slot: 'other')],
      [
        effect(
          10,
          cell: Scope(
            applicability: const UniverseApplicability(),
            context: ref(9),
          ),
        ),
      ],
      [
        effect(
          10,
          cell: Scope(
            applicability: const ConditionalApplicability(),
            context: ref(3),
          ),
        ),
      ],
      [effect(10, validity: const UnspecifiedValidity())],
      [
        effect(
          10,
          validity: CalendarIntervalValidity(
            calendar,
            const ExactBound('9'),
            const UnboundedBound(),
          ),
        ),
      ],
      [
        effect(
          10,
          validity: CalendarIntervalValidity(
            calendar,
            const ExactBound('10'),
            const ExactBound('10'),
          ),
        ),
      ],
    ];
    for (final effects in bad) {
      expect(
        () => expandEvents([
          record(4, proposition()),
          record(5, event(10, effects: effects)),
        ]),
        fails(),
      );
    }
    expect(
      expandEvents([
        record(4, proposition()),
        record(5, event(10, effects: [effect(10, slot: '\ufeff')])),
      ]).containsKey(eventEffectId(id(5), '\ufeff')),
      isTrue,
    );
    expect(
      () => expandEvents([record(5, event(10))]),
      fails('Event proposition unavailable'),
    );
    expect(
      () => expandEvents([
        record(4, WorldRecord(selector: 'world')),
        record(5, event(10)),
      ]),
      fails('Event effect target must be a proposition'),
    );
  });

  test('later single-valued effects end only earlier generated values', () {
    PropertyRecord property(Multiplicity m) => PropertyRecord(
      namespace: 'author',
      key: 'state',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: m,
      persistence: PersistenceSemantics.unspecified,
      exclusive: false,
      symmetric: false,
      transitive: false,
    );
    for (final m in Multiplicity.values) {
      final records = [
        record(2, property(m)),
        record(4, proposition()),
        record(7, proposition(value: const BooleanValue(false))),
        record(5, event(10)),
        record(6, event(20, effects: [effect(20, target: 7)])),
      ];
      final expected = expandEvents(records)[eventEffectId(id(5), 'active')]!;
      expect(
        (expected.validity as CalendarIntervalValidity).end,
        m == Multiplicity.single
            ? const ExactBound('20')
            : const UnboundedBound(),
      );
    }
  });

  test(
    'event budgets include non-occurrences without synthesizing their effects',
    () {
      final tooManyEffects = List<EntityEffect>.filled(101, effect(10));
      expect(
        () => expandEvents([
          record(
            5,
            event(10, mode: OccurrenceKind.planned, effects: tooManyEffects),
          ),
        ]),
        fails('Event work budget exceeded'),
      );
      final tooManyEvents = [
        for (var n = 0; n < 1001; n++)
          record(10000 + n, event(10, effects: [])),
      ];
      expect(
        () => expandEvents(tooManyEvents),
        fails('Event work budget exceeded'),
      );
    },
  );
}
