import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'rule_checks_test.dart' as f;
import 'operation_compilation_test.dart' as compiler;
import 'writing_units_test.dart' as units;
import 'writing_dates_test.dart' as dates;

EntityRecord entity({
  Map<String, String> labels = const {},
  List<ContextualName> names = const [],
}) => EntityRecord(
  names: names,
  labels: labels,
  metadata: {},
  worldAssociations: [],
  classificationResolution: ClassificationResolution.unclassified,
);
final cedar = f.record(80, entity(labels: {'en': 'Cedar'}));
Matcher fails(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  test('object binding preserves ambiguous and uncertain authored names', () {
    final frame = f.frame(time: AtFrameTime(ExactTime(f.calendar, '15')));
    final rows = [
      cedar,
      f.record(
        81,
        entity(
          names: [
            ContextualName(text: 'Past name', validity: f.interval(1, 5)),
            const ContextualName(
              text: 'Uncertain',
              validity: UnspecifiedValidity(),
            ),
            ContextualName(text: 'Current', validity: f.interval(10, 20)),
          ],
        ),
      ),
    ];
    expect(resolveWritingObject(rows, 'Cedar', frame), f.id(80));
    expect(resolveWritingObject(rows, 'Past name', frame), isNull);
    expect(resolveWritingObject(rows, 'Uncertain', frame), f.id(81));
    expect(resolveWritingObject(rows, 'Current', frame), f.id(81));
    expect(resolveWritingObject(rows, 'Current', f.frame()), f.id(81));
    final duplicate = f.record(82, entity(labels: {'en': 'Cedar'}));
    expect(resolveWritingObject([...rows, duplicate], 'Cedar', frame), isNull);
    expect(resolveWritingObject(rows, ' cedar ', frame), isNull);
  });

  test('values retain numeric kind and bind only exact visible references', () {
    final rows = [cedar, f.record(2, units.unit())];
    final frame = f.frame();
    DomainValue bind(FactValue value) =>
        bindWritingValue(f.universe, rows, frame, value);
    expect(
      bind(const FactTextValue('9007199254740993')),
      const TextValue('9007199254740993'),
    );
    expect(bind(const FactBooleanValue(true)), const BooleanValue(true));
    expect(
      bind(FactNumberValue(const CanonicalNumber('9007199254740993'))),
      const IntegerValue('9007199254740993'),
    );
    expect(
      bind(FactNumberValue(const CanonicalNumber('9007199254740993.25'))),
      const DecimalValue('9007199254740993.25'),
    );
    expect(
      bind(FactNumberValue(const CanonicalNumber('1e20'))),
      const DecimalValue('1e20'),
    );
    expect(
      bind(
        FactQuantityValue(
          amount: const CanonicalNumber('9007199254740993'),
          unit: 'm',
        ),
      ),
      QuantityValue(
        const IntegerValue('9007199254740993'),
        UnitId.fromRecordId(f.id(2)),
      ),
    );
    expect(
      bind(const FactObjectValue('Cedar')),
      ReferenceValue(ValueReferenceKind.entity, f.ref(80)),
    );
    expect(
      () => bind(const FactObjectValue('Hidden')),
      fails('Which exact object'),
    );
    expect(
      () => bind(
        FactQuantityValue(amount: const CanonicalNumber('1'), unit: 'feet'),
      ),
      fails('cannot imply conversion'),
    );
  });

  test(
    'claim binding reuses exact propositions and compiles explicit new ones',
    () {
      final property = f.fixture().first;
      final rows = [cedar, property];
      WritingClaim claim(String property) => WritingClaim(
        subject: 'Cedar',
        property: property,
        value: const FactBooleanValue(true),
      );
      final proposition = bindWritingClaim(
        f.universe,
        rows,
        f.frame(),
        claim('open'),
      );
      expect(proposition.subject, f.ref(80));
      expect(proposition.predicate, f.ref(1));
      expect(proposition.context, f.frame().context);
      expect(proposition.quantification, Quantification.particular);
      final operations = <DomainOperation>[];
      final reference = bindWritingProposition(
        operations,
        f.universe,
        proposition,
        rows,
      );
      final compiled = compiler
          .compile(rows, operations)
          .map(compiler.decode)
          .single;
      expect(compiled.identity.recordId, reference.record);
      expect(compiled.payload, proposition);
      operations.clear();
      expect(
        bindWritingProposition(operations, f.universe, proposition, [
          ...rows,
          compiled,
        ]),
        reference,
      );
      expect(operations, isEmpty);
      expect(
        () => bindWritingClaim(f.universe, rows, f.frame(), claim('missing')),
        fails('Which authored property'),
      );
      final duplicated = f.record(3, property.payload);
      expect(
        () => bindWritingClaim(
          f.universe,
          [...rows, duplicated],
          f.frame(),
          claim('open'),
        ),
        fails('Which authored property'),
      );
      expect(
        () =>
            bindWritingClaim(f.universe, [property], f.frame(), claim('open')),
        fails('in this claim'),
      );
    },
  );

  test('time and lifetime remain explicit frame-bound declarations', () {
    final exactFrame = f.frame(time: AtFrameTime(ExactTime(f.calendar, '15')));
    expect(bindWritingTime(exactFrame, [], null), ExactTime(f.calendar, '15'));
    expect(
      bindWritingTime(exactFrame, [], '9007199254740993'),
      ExactTime(f.calendar, '9007199254740993'),
    );
    final rows = [dates.context(dates.gregorian)];
    expect(bindWritingTime(f.frame(), rows, '20'), ExactTime(f.calendar, '20'));
    expect(
      () => bindWritingTime(f.frame(), rows, null),
      fails('exact authored calendar/story time'),
    );
    expect(
      () => bindWritingTime(f.frame(), [], '20'),
      fails('exact authored calendar/story time'),
    );
    expect(
      () => bindWritingTime(
        f.frame(time: const AtFrameTime(UnspecifiedTime())),
        rows,
        '20',
      ),
      fails('exact authored calendar/story time'),
    );
    final time = ExactTime(f.calendar, '15');
    expect(
      bindWritingLifetime(time, const FactUnspecifiedLifetime()),
      InstantValidity(time),
    );
    expect(
      bindWritingLifetime(time, const FactUntilChangedLifetime()),
      CalendarIntervalValidity(
        f.calendar,
        const ExactBound('15'),
        const UnboundedBound(),
      ),
    );
    expect(
      bindWritingLifetime(time, const FactUntilLifetime(endTick: '25')),
      CalendarIntervalValidity(
        f.calendar,
        const ExactBound('15'),
        const ExactBound('25'),
      ),
    );
    expect(
      bindWritingLifetime(
        const UnspecifiedTime(),
        const FactUnspecifiedLifetime(),
      ),
      const InstantValidity(UnspecifiedTime()),
    );
    expect(
      () => bindWritingLifetime(
        const UnspecifiedTime(),
        const FactUntilChangedLifetime(),
      ),
      fails('contract time/lifetime'),
    );
  });

  test(
    'fact corrections require pinned versions and reject generated causes',
    () {
      final authored = f.assertion();
      expect(
        bindWritingAuthoredFact([authored], authored.recordVersionId.value).$1,
        same(authored),
      );
      expect(
        () => bindWritingAuthoredFact([
          authored,
        ], authored.identity.recordId.value),
        fails('current pinned authored fact handle'),
      );
      expect(
        () => bindWritingAuthoredFact([], authored.recordVersionId.value),
        fails('current pinned authored fact handle'),
      );
      expect(
        () => bindWritingAuthoredFact([cedar], cedar.recordVersionId.value),
        fails('not an authored assertion'),
      );
      final generated = f.record(
        4,
        compiler.patch<AssertionRecord>(authored.payload as AssertionRecord, {
          'establishedBy': EventEffectRef(f.ref(50), 'spent').toWire(),
        }),
      );
      expect(
        () => bindWritingAuthoredFact([
          generated,
        ], generated.recordVersionId.value),
        fails('correct the authored cause'),
      );
    },
  );
}
