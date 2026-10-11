import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalObject replace(
  CanonicalObject object,
  Map<String, CanonicalValue> changes,
) => CanonicalObject(
  {for (final e in object.fields) e.key: e.value, ...changes}.entries,
);
void main() {
  RecordRef ref(int n) =>
      RecordRef(record: RecordId.parse('rec_${n.toString().padLeft(24, '0')}'));
  final scope = Scope(
    applicability: const UniverseApplicability(),
    context: ref(1),
  );
  final calendar = CalendarId.parse('cal_000000000000000000000001');
  const validity = UnknownValidity();
  EffectSlot slot({
    String name = 'authored',
    int order = 0,
    String role = 'actor',
    EffectChange? change,
    EffectLifetime? lifetime,
    EffectCondition? condition,
  }) => EffectSlot(
    slot: name,
    order: order,
    presence: EffectPresence.required,
    target: EffectTarget(role, ref(2)),
    condition: condition ?? const AlwaysEffect(),
    change: change ?? const SetEffect(Polarity.support, IntegerValue('1')),
    lifetime: lifetime ?? const UntilChangedEffect(),
  );
  DeltaEffect delta({
    String amount = '-1.00',
    String minimum = '0',
    String maximum = '6.00',
  }) => DeltaEffect(
    delta: ConsequenceDecimal(amount),
    minimum: ConsequenceDecimal(minimum),
    maximum: ConsequenceDecimal(maximum),
    unit: null,
  );
  ActionDefinitionRecord action(ConsequenceContract? contract) =>
      ActionDefinitionRecord(
        namespace: 'author',
        key: 'authored action',
        labels: {},
        requirements: [
          AttributeRequirement('actor', ref(2), const IntegerValue('1')),
        ],
        consequenceContract: contract,
        scope: scope,
        validity: validity,
      );
  test('all occurrence modes preserve reports and plans without promotion to objective state', () {
    for (final occurrence in <OccurrenceMode>[
      for (final kind in OccurrenceKind.values) SimpleOccurrence(kind),
      const DescriptiveOccurrence('rumored'),
    ]) {
      final event = EventRecord(
        occurrence: occurrence,
        time: const UnspecifiedTime(),
        participants: [EventParticipant(ref(3), 'actor')],
        labels: {},
      );
      expect(RecordPayload.fromWire(event.toWire()), event);
      expect(event.action, isNull);
      expect(event.effects, isEmpty);
      expect(event.toWire().toText(), contains('"worlds":[]'));
    }
    expect(
      const DescriptiveOccurrence('rumored').toWire().toText(),
      '{"descriptive":{"label":"rumored"}}',
    );
    expect(
      const DescriptiveOccurrence('rumored').toCanonical().toText(),
      '{"kind":"descriptive","label":"rumored"}',
    );
  });
  test(
    'event effects preserve explicit order and historical action omission',
    () {
      final order = BigInt.parse('18446744073709551615');
      final effects = [
        EntityEffect(
          slot: 'authored',
          proposition: ref(4),
          polarity: Polarity.refutation,
          validity: validity,
          scope: scope,
          order: order,
        ),
      ];
      final event = EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        action: ref(5),
        worlds: [WorldId.parse('wld_000000000000000000000001')],
        region: ref(6),
        time: ExactTime(calendar, '10'),
        sequence: 'explicit sequence',
        occurrenceId: 'loop-2',
        participants: [EventParticipant(ref(3), 'actor')],
        preconditions: [const LiteralExpr(false)],
        effects: effects,
        labels: {},
        expansionVersion: 'authored expansion',
      );
      effects.clear();
      expect(RecordPayload.fromWire(event.toWire()), event);
      expect(event.effects.single.order, order);
      expect(() => event.effects.clear(), throwsUnsupportedError);
      expect(
        () => EventRecord.fromWire(
          replace(event.toWire(), {'effects': const CanonicalNull()}),
        ),
        throwsFormatException,
      );
    },
  );
  test('historical absent contract differs from present empty contract and explicit null', () {
    final historical = action(null);
    final empty = action(ConsequenceContract([]));
    expect(RecordPayload.fromWire(historical.toWire()), historical);
    expect(RecordPayload.fromWire(empty.toWire()), empty);
    expect(historical.digest, isNot(empty.digest));
    expect(
      historical.toWire().toText(),
      isNot(contains('"consequenceContract"')),
    );
    expect(empty.consequenceContract!.slots, isEmpty);
    expect(
      () => ActionDefinitionRecord.fromWire(
        replace(historical.toWire(), {
          'consequenceContract': const CanonicalNull(),
        }),
      ),
      throwsFormatException,
    );
  });
  test('consequence decimals preserve authored digits within exact i128 arithmetic bounds', () {
    expect(
      ConsequenceInteger('-170141183460469231731687303715884105728').value,
      ExactAmount.minimum,
    );
    expect(ConsequenceDecimal('1.0000').digits, '1.0000');
    expect(ConsequenceDecimal('-0.000').amount.coefficient, BigInt.zero);
    for (final digits in [
      '01',
      '+1',
      '-0',
      '170141183460469231731687303715884105728',
    ]) {
      expect(() => ConsequenceInteger(digits), throwsFormatException);
    }
    for (final digits in [
      '01.2',
      '+1.0',
      '1e2',
      'NaN',
      '1.',
      '0.000000000000000000000000000000000000001',
    ]) {
      expect(() => ConsequenceDecimal(digits), throwsFormatException);
    }
  });
  test('delta declaration enforces nonzero bounded amount and required nullable unit', () {
    final contract = ConsequenceContract([slot(change: delta())]);
    expect(RecordPayload.fromWire(action(contract).toWire()), action(contract));
    expect(contract.toWire().toText(), contains('"delta":"-1.00"'));
    expect(contract.toWire().toText(), contains('"unit":null'));
    final missing = CanonicalObject(
      delta().toWire().fields.where((e) => e.key != 'unit'),
    );
    expect(() => EffectChange.fromWire(missing), throwsFormatException);
    for (final change in [
      delta(amount: '0.00'),
      delta(minimum: '7', maximum: '6'),
      delta(minimum: '170141183460469231731687303715884105727', maximum: '0.1'),
    ]) {
      expect(
        () => ConsequenceContract([slot(change: change)]),
        throwsFormatException,
      );
    }
    expect(
      () => ConsequenceContract([
        slot(change: delta(), lifetime: TicksEffect(ConsequenceInteger('1'))),
      ]),
      throwsFormatException,
    );
    ConsequenceContract([
      slot(
        change: delta(minimum: '6', maximum: '6'),
      ),
    ]);
  });
  test('contract slot names, orders, targets and positive lifetimes retain exact bounds', () {
    final valid = ConsequenceContract(
      List.generate(
        64,
        (n) => slot(name: 'slot-$n', order: n, role: 'role-$n'),
      ),
    );
    expect(valid.slots, hasLength(64));
    expect(() => valid.slots.clear(), throwsUnsupportedError);
    for (final slots in <List<EffectSlot>>[
      [slot(), slot(name: 'second', order: 1)],
      [slot(), slot(name: 'second', role: 'other')],
      [slot(), slot(order: 1, role: 'other')],
      [slot(order: 64)],
      [slot(name: '   ')],
      [slot(role: '🌲' * 31)],
      [slot(lifetime: TicksEffect(ConsequenceInteger('0')))],
      [
        slot(
          condition: AttributeEqualsEffect(
            ' ',
            ref(2),
            const IntegerValue('1'),
          ),
        ),
      ],
      List.generate(
        65,
        (n) => slot(name: 'slot-$n', order: n, role: 'role-$n'),
      ),
    ]) {
      expect(() => ConsequenceContract(slots), throwsFormatException);
    }
    ConsequenceContract([
      slot(name: '\uFEFF', lifetime: TicksEffect(ConsequenceInteger('1'))),
    ]);
    expect(
      () => ConsequenceContract([
        slot(change: const SetEffect(Polarity.support, DecimalValue('NaN'))),
      ]),
      throwsFormatException,
    );
  });
  test(
    'condition and set declarations retain typed values and closed branches',
    () {
      final contract = ConsequenceContract([
        slot(
          condition: AttributeEqualsEffect(
            'holder',
            ref(2),
            const BooleanValue(false),
          ),
          change: const SetEffect(Polarity.refutation, TextValue('authored')),
        ),
      ]);
      expect(
        RecordPayload.fromWire(action(contract).toWire()),
        action(contract),
      );
      expect(
        () => EffectCondition.fromWire(
          CanonicalValue.parseJson('{"kind":"always","invented":true}'),
        ),
        throwsFormatException,
      );
      expect(
        () => ConsequenceContract.fromWire(
          CanonicalValue.parseJson(
            '{"kind":"action_consequences","slots":null}',
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('item powers preserve ownership dependency without changing instance identity', () {
    final power = ItemPowerRecord(
      item: ref(3),
      holderPredicate: ref(2),
      powerPredicate: ref(4),
      value: const IntegerValue('1'),
      scope: scope,
      validity: validity,
    );
    expect(RecordPayload.fromWire(power.toWire()), power);
    expect(power.item, ref(3));
  });
  test('represented contexts retain authored clock coordinates and distinct perspectives', () {
    final universe = UniverseId.parse('unv_000000000000000000000001');
    for (final kind in <RepresentedContextKind>[
      const ObjectiveContext(),
      CharacterContext(ref(3)),
      SourceContext(ref(4)),
      NarratorContext(ref(5)),
      const AuthoredContext('dream'),
    ]) {
      final record = RepresentedContextRecord(
        universe: universe,
        kind: kind,
        parent: ref(1),
        chronology: Chronology(
          calendar: calendar,
          system: FictionalClock('tick', null),
          firstInteraction: '0001',
          current: '-10',
        ),
        labels: {},
      );
      expect(RecordPayload.fromWire(record.toWire()), record);
      expect(record.chronology!.firstInteraction, '0001');
      expect(record.chronology!.current, '-10');
      expect(
        record.chronology!.system.toWire().toText(),
        contains('"ticks_per_month":null'),
      );
    }
    for (final offset in [-2147483648, 2147483647]) {
      final clock = GregorianClock(offset);
      expect(
        (ClockSystem.fromWire(clock.toWire()) as GregorianClock).offsetSeconds,
        offset,
      );
    }
    expect(
      () => ClockSystem.fromWire(
        CanonicalValue.parseJson(
          '{"kind":"gregorian","offset_seconds":2147483648}',
        ),
      ),
      throwsFormatException,
    );
    expect(() => FictionalClock('tick', 4294967296), throwsFormatException);
  });
}
