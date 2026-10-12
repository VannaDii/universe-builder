import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/consequence_execution.dart';

import 'operation_compilation_test.dart' as f;
import 'action_checks_test.dart' as a;

List<RecordVersion> fixture() =>
    a.fixture().where((r) => r.payload is! EventRecord).toList();
EventRecord event({
  List<EventParticipant>? participants,
  List<WorldId> worlds = const [],
  String tick = '11',
}) => EventRecord(
  occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
  time: ExactTime(a.cal, tick),
  participants: participants ?? [EventParticipant(f.ref(1), 'actor')],
  worlds: worlds,
  action: f.ref(5),
  labels: {},
);
ActionDefinitionRecord action(
  EffectChange change, {
  EffectPresence presence = EffectPresence.required,
  EffectCondition condition = const AlwaysEffect(),
  EffectLifetime lifetime = const UntilChangedEffect(),
}) => ActionDefinitionRecord(
  namespace: 'test',
  key: 'charged_action',
  labels: {},
  requirements: [],
  scope: a.scope,
  validity: const UnspecifiedValidity(),
  consequenceContract: ConsequenceContract([
    EffectSlot(
      slot: 'change',
      order: 0,
      presence: presence,
      target: EffectTarget('actor', f.ref(2)),
      condition: condition,
      change: change,
      lifetime: lifetime,
    ),
  ]),
);
DeltaEffect delta(
  String n, {
  UnitId? unit,
  String minimum = '0',
  String maximum = '10',
}) => DeltaEffect(
  delta: ConsequenceDecimal(n),
  minimum: ConsequenceDecimal(minimum),
  maximum: ConsequenceDecimal(maximum),
  unit: unit,
);
List<AuthoredConsequence> realize(
  List<RecordVersion> rows,
  ActionDefinitionRecord action, {
  EventRecord? occurrence,
}) => authorActionEffects(
  records: rows,
  eventId: f.id(6),
  event: occurrence ?? event(),
  action: action,
  frame: a.frame,
);
void numeric(List<RecordVersion> rows, DomainValue value) =>
    a.edit(rows, 3, {'value': value.toWire()});
Matcher invalid(String text) => throwsA(
  isA<InvalidArgumentError>()
      .having((e) => e.field, 'field', 'event.action.effects')
      .having((e) => e.message, 'message', contains(text)),
);

void main() {
  test(
    'realization requires a contract exact event clock and bounded lifetime',
    () {
      final rows = fixture();
      final legacy =
          rows.firstWhere((r) => r.identity.recordId == f.id(5)).payload
              as ActionDefinitionRecord;
      expect(
        () => realize(rows, legacy),
        invalid('no authored consequence contract'),
      );
      final set = const SetEffect(Polarity.support, BooleanValue(true));
      expect(
        () => realize(rows, action(set), occurrence: event(tick: '1.5')),
        invalid('exact integer coordinate'),
      );
      expect(
        () => realize(
          rows,
          action(set, lifetime: TicksEffect(ConsequenceInteger('2'))),
          occurrence: event(
            tick: (ExactAmount.maximum - BigInt.one).toString(),
          ),
        ),
        invalid('lifetime overflow'),
      );
    },
  );
  test(
    'set realization binds original owner exact context and authored lifetime',
    () {
      final result = realize(
        fixture(),
        action(
          const SetEffect(Polarity.refutation, BooleanValue(false)),
          lifetime: TicksEffect(ConsequenceInteger('4')),
        ),
      ).single;
      expect(result.$2.subject, f.ref(1));
      expect(result.$2.predicate, f.ref(2));
      expect(result.$2.value, const BooleanValue(false));
      expect(result.$2.context, f.ref(10));
      expect(result.$3.proposition.record, result.$1);
      expect(result.$3.proposition.universe, f.u);
      expect(result.$3.polarity, Polarity.refutation);
      expect(
        result.$3.validity,
        CalendarIntervalValidity(
          a.cal,
          const ExactBound('11'),
          const ExactBound('15'),
        ),
      );
    },
  );
  test('mandatory delta uses explicit exact pre-value and preserves decimal property shape', () {
    final rows = fixture();
    numeric(rows, IntegerValue('5'));
    final result = realize(rows, action(delta('-2'))).single;
    expect(result.$2.value, IntegerValue('3'));
    a.edit(rows, 2, {
      'value': const SimpleValueShape(SimpleShapeKind.decimal).toWire(),
    });
    expect(
      realize(rows, action(delta('-2'))).single.$2.value,
      DecimalValue('3'),
    );
    numeric(rows, DecimalValue('5.50'));
    expect(
      realize(rows, action(delta('-0.25'))).single.$2.value,
      DecimalValue('5.25'),
    );
  });
  test('quantity delta requires the exact unit without conversion', () {
    final rows = fixture();
    final unit = UnitId.fromRecordId(f.id(80));
    numeric(rows, QuantityValue(IntegerValue('5'), unit));
    expect(
      realize(rows, action(delta('-1', unit: unit))).single.$2.value,
      QuantityValue(IntegerValue('4'), unit),
    );
    expect(
      () => realize(
        rows,
        action(delta('-1', unit: UnitId.fromRecordId(f.id(81)))),
      ),
      invalid('declared unit'),
    );
  });
  test('unasserted missing conflicting and uncertain resource balances cannot be spent', () {
    final rows = fixture();
    numeric(rows, IntegerValue('5'));
    rows.removeWhere((r) => r.identity.recordId == f.id(4));
    expect(
      () => realize(rows, action(delta('-1'))),
      invalid('balance missing'),
    );
    final conflict = fixture();
    numeric(conflict, IntegerValue('5'));
    conflict.add(
      f.row(
        80,
        f.patch(
          conflict.firstWhere((r) => r.identity.recordId == f.id(4)).payload,
          {'polarity': CanonicalString('refutation')},
        ),
      ),
    );
    expect(
      () => realize(conflict, action(delta('-1'))),
      invalid('conflicting'),
    );
    final uncertain = fixture();
    numeric(uncertain, IntegerValue('5'));
    a.edit(uncertain, 4, {'precision': CanonicalString('approximate')});
    expect(() => realize(uncertain, action(delta('-1'))), invalid('uncertain'));
  });
  test(
    'resource transitions cannot underflow overflow or bypass pre-event time',
    () {
      final rows = fixture();
      numeric(rows, IntegerValue('1'));
      expect(
        () => realize(rows, action(delta('-2'))),
        invalid('transition underflow'),
      );
      expect(
        () => realize(rows, action(delta('10'))),
        invalid('transition underflow'),
      );
      numeric(rows, IntegerValue('11'));
      expect(
        () => realize(rows, action(delta('-1'))),
        invalid('pre-event balance outside'),
      );
      numeric(rows, IntegerValue('1'));
      a.edit(rows, 4, {
        'validity': CalendarIntervalValidity(
          a.cal,
          const ExactBound('11'),
          const UnboundedBound(),
        ).toWire(),
      });
      expect(
        () => realize(rows, action(delta('-1'))),
        invalid('balance missing'),
      );
    },
  );
  test('condition needs established pre-event truth and false conditions omit effects', () {
    final rows = fixture();
    final contract = action(
      const SetEffect(Polarity.support, BooleanValue(false)),
      condition: AttributeEqualsEffect(
        'actor',
        f.ref(2),
        const BooleanValue(true),
      ),
    );
    expect(realize(rows, contract), hasLength(1));
    numeric(rows, const BooleanValue(false));
    expect(realize(rows, contract), isEmpty);
    rows.removeWhere((r) => r.identity.recordId == f.id(4));
    expect(
      () => realize(rows, contract),
      invalid('no established pre-event truth'),
    );
  });
  test('optional enabled effects require author choice and owners are exact namespace-bound entities', () {
    final rows = fixture(),
        contract = action(
          const SetEffect(Polarity.support, BooleanValue(true)),
        );
    expect(
      () => realize(
        rows,
        action(
          const SetEffect(Polarity.support, BooleanValue(true)),
          presence: EffectPresence.optional,
        ),
      ),
      invalid('optional'),
    );
    expect(
      () => realize(rows, contract, occurrence: event(participants: [])),
      invalid('no owner'),
    );
    expect(
      () => realize(
        rows,
        contract,
        occurrence: event(
          participants: [EventParticipant(RecordRef(record: f.id(1)), 'actor')],
        ),
      ),
      invalid('owning entity'),
    );
    expect(
      () => realize(
        rows,
        contract,
        occurrence: event(
          participants: [
            EventParticipant(f.ref(1), 'actor'),
            EventParticipant(f.ref(1), 'actor'),
          ],
        ),
      ),
      invalid('owning entity'),
    );
  });
  test('every event world must agree on the delta balance', () {
    final rows = fixture();
    numeric(rows, IntegerValue('5'));
    final w1 = WorldId.parse('wld_${f.suffix(21)}'),
        w2 = WorldId.parse('wld_${f.suffix(22)}');
    a.edit(rows, 4, {
      'scope': Scope(
        context: f.ref(10),
        applicability: WorldsApplicability([w1]),
      ).toWire(),
    });
    rows.add(
      f.row(
        81,
        f.patch(
          rows.firstWhere((r) => r.identity.recordId == f.id(3)).payload,
          {'value': IntegerValue('6').toWire()},
        ),
      ),
    );
    rows.add(
      f.row(
        82,
        f.patch(
          rows.firstWhere((r) => r.identity.recordId == f.id(4)).payload,
          {
            'proposition': f.ref(81).toCanonical(),
            'scope': Scope(
              context: f.ref(10),
              applicability: WorldsApplicability([w2]),
            ).toWire(),
          },
        ),
      ),
    );
    expect(
      () => realize(
        rows,
        action(delta('-1')),
        occurrence: event(worlds: [w1, w2]),
      ),
      invalid('differs across'),
    );
    numeric(rows, const BooleanValue(true));
    final at = rows.indexWhere((r) => r.identity.recordId == f.id(81));
    rows[at] = f.row(
      81,
      f.patch(rows[at].payload, {'value': const BooleanValue(false).toWire()}),
    );
    expect(
      () => realize(
        rows,
        action(
          const SetEffect(Polarity.support, BooleanValue(true)),
          condition: AttributeEqualsEffect(
            'actor',
            f.ref(2),
            const BooleanValue(true),
          ),
        ),
        occurrence: event(worlds: [w1, w2]),
      ),
      invalid('condition differs across'),
    );
  });
}
