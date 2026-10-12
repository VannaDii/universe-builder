import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart'
    show EvaluationLimitReachedError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/consequence_execution.dart';

import 'consequence_execution_test.dart' as c;
import 'operation_compilation_test.dart' as f;
import 'action_checks_test.dart' as a;
import 'effective_objects_test.dart' as o;

List<RecordVersion> fixture({EffectChange? change, DomainValue? value}) {
  final rows = c.fixture();
  o.put(
    rows,
    5,
    c.action(change ?? const SetEffect(Polarity.support, BooleanValue(true))),
  );
  rows.add(
    f.row(
      7,
      PropositionRecord(
        subject: f.ref(1),
        predicate: f.ref(2),
        value: value ?? const BooleanValue(true),
        context: f.ref(10),
        quantification: Quantification.particular,
      ),
    ),
  );
  rows.add(
    f.row(
      6,
      f.patch(c.event(), {
        'effects': CanonicalArray([
          EntityEffect(
            slot: 'change',
            proposition: f.ref(7),
            polarity: Polarity.support,
            scope: a.scope,
            validity: CalendarIntervalValidity(
              a.cal,
              const ExactBound('11'),
              const UnboundedBound(),
            ),
            order: BigInt.zero,
          ).toWire(),
        ]),
      }),
    ),
  );
  return rows;
}

List<String> validate(
  List<RecordVersion> rows, {
  List<RecordVersion> base = const [],
  Set<RecordId>? changed,
}) => validateActionConsequences(
  records: rows,
  base: base,
  changed: changed ?? {f.id(6)},
  frame: a.frame,
);

void main() {
  test('declared assignment admits only exact value polarity scope order and lifetime', () {
    expect(validate(fixture()), isEmpty);
    for (final edit in <Map<String, CanonicalValue>>[
      {'order': const CanonicalNumber('1')},
      {'slot': CanonicalString('not_declared')},
      {'polarity': CanonicalString('refutation')},
      {
        'scope': Scope(
          context: f.ref(10),
          realm: f.ref(1),
          applicability: const UniverseApplicability(),
        ).toWire(),
      },
      {
        'validity': CalendarIntervalValidity(
          a.cal,
          const ExactBound('11'),
          const ExactBound('15'),
        ).toWire(),
      },
    ]) {
      final rows = fixture();
      final event = o.get(rows, 6).payload as EventRecord;
      final fields = event.effects.single.toWire().fields.toList();
      final effect = CanonicalObject([
        ...fields.where((e) => !edit.containsKey(e.key)),
        ...edit.entries,
      ]);
      o.edit(rows, 6, {
        'effects': CanonicalArray([effect]),
      });
      expect(() => validate(rows), c.invalid(''));
    }
    final exact = fixture(
      change: SetEffect(Polarity.support, IntegerValue('1')),
      value: DecimalValue('1.0'),
    );
    expect(() => validate(exact), c.invalid('declared assignment'));
  });
  test('delta post-value must equal exact pre-value plus contract delta', () {
    final rows = fixture(change: c.delta('-1'), value: IntegerValue('4'));
    c.numeric(rows, IntegerValue('5'));
    expect(validate(rows), isEmpty);
    o.edit(rows, 7, {'value': IntegerValue('3').toWire()});
    expect(() => validate(rows), c.invalid('pre-value plus'));
  });
  test('mandatory effects cannot disappear on unchanged events while plans do not execute', () {
    final rows = fixture();
    o.edit(rows, 6, {'effects': CanonicalArray([])});
    expect(() => validate(rows, changed: {}), c.invalid('missing mandatory'));
    o.edit(rows, 6, {
      'occurrence': const SimpleOccurrence(OccurrenceKind.planned).toWire(),
    });
    expect(validate(rows), isEmpty);
  });
  test(
    'historical exclusions stay explicit and changed contractless records fail',
    () {
      final rows = a.fixture();
      expect(validate(rows, changed: {}), [
        'event:${f.id(6).value}: historical undeclared consequences excluded',
      ]);
      expect(() => validate(rows), c.invalid('contract-bearing action'));
      expect(
        () => validate(rows, changed: {f.id(5)}),
        c.invalid('declare a consequence contract'),
      );
      final contracted = fixture();
      final current = c.fixture();
      expect(
        () => validate(current, base: contracted, changed: {}),
        c.invalid('cannot discard its contract'),
      );
    },
  );
  test(
    'dependent delta and set uses require distinct same-clock event times',
    () {
      final rows = fixture(change: c.delta('-1'), value: IntegerValue('4'));
      c.numeric(rows, IntegerValue('5'));
      rows.add(
        f.row(9, c.action(SetEffect(Polarity.support, IntegerValue('4')))),
      );
      rows.add(
        f.row(
          10,
          f.patch(o.get(rows, 6).payload, {'action': f.ref(9).toCanonical()}),
        ),
      );
      expect(() => validate(rows), c.invalid('distinct times'));
      o.edit(rows, 10, {
        'occurrence': const SimpleOccurrence(OccurrenceKind.planned).toWire(),
      });
      expect(validate(rows), isEmpty);
    },
  );
  test(
    'supplied conditional effect requires true condition in every event world',
    () {
      final rows = fixture();
      o.put(
        rows,
        5,
        c.action(
          const SetEffect(Polarity.support, BooleanValue(true)),
          condition: AttributeEqualsEffect(
            'actor',
            f.ref(2),
            const BooleanValue(false),
          ),
        ),
      );
      expect(() => validate(rows), c.invalid('false condition'));
      o.edit(rows, 6, {'effects': CanonicalArray([])});
      expect(validate(rows), isEmpty);
    },
  );
  test(
    'duplicate event worlds and aliased slot targets fail before publication',
    () {
      final rows = fixture();
      o.edit(rows, 6, {
        'worlds': CanonicalArray([
          CanonicalString('wld_${f.suffix(21)}'),
          CanonicalString('wld_${f.suffix(21)}'),
        ]),
      });
      expect(() => validate(rows), c.invalid('unique worlds'));
      final alias = fixture();
      final action = o.get(alias, 5).payload as ActionDefinitionRecord;
      final slot = action.consequenceContract!.slots.single;
      o.edit(alias, 5, {
        'consequenceContract': ConsequenceContract([
          slot,
          EffectSlot(
            slot: 'second',
            order: 1,
            presence: EffectPresence.optional,
            target: EffectTarget('other', slot.target.predicate),
            condition: slot.condition,
            change: slot.change,
            lifetime: slot.lifetime,
          ),
        ]).toWire(),
      });
      o.edit(alias, 6, {
        'participants': CanonicalArray([
          EventParticipant(f.ref(1), 'actor').toWire(),
          EventParticipant(f.ref(1), 'other').toWire(),
        ]),
      });
      expect(() => validate(alias), c.invalid('same owner/property'));
    },
  );
  test('consequence work limit reports a bounded evaluation failure', () {
    final rows = fixture();
    // A large candidate with repeated rows consumes the shared candidate budget.
    final repeated = List<RecordVersion>.filled(1000001, rows.first);
    expect(
      () => validate(repeated, changed: {}),
      throwsA(isA<EvaluationLimitReachedError>()),
    );
  });
}
