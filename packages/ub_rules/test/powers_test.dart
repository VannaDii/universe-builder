import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(9)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
final scope = Scope(
  applicability: const UniverseApplicability(),
  context: ref(10),
);
Validity interval(int start, [int? end]) => CalendarIntervalValidity(
  calendar,
  ExactBound('$start'),
  end == null ? const UnboundedBound() : ExactBound('$end'),
);
RecordVersion record(int n, RecordPayload payload) => RecordVersion.build(
  recordVersionId: version(n),
  identity: RecordIdentity(
    universeId: universe,
    recordId: id(n),
    recordKind: payload.recordKind,
  ),
  payload: payload,
);
RecordVersion custody(int n, int owner) => record(
  n,
  PropositionRecord(
    subject: ref(3),
    predicate: ref(4),
    value: ReferenceValue(ValueReferenceKind.entity, ref(owner)),
    context: ref(10),
    quantification: Quantification.particular,
  ),
);
RecordVersion assertion(
  int n,
  int proposition, {
  Polarity polarity = Polarity.support,
  Validity? validity,
  Precision precision = Precision.exact,
  List<DomainValue> alternatives = const [],
  Scope? cell,
}) => record(
  n,
  AssertionRecord(
    attributeMode: AttributeMode.instance,
    proposition: ref(proposition),
    polarity: polarity,
    scope: cell ?? scope,
    validity: validity ?? interval(10),
    persistence: PersistenceSemantics.explicitInterval,
    precision: precision,
    alternatives: alternatives,
    basis: const AuthorDecisionBasis('Power regression'),
  ),
);
RecordVersion power({Scope? cell, Validity? validity}) => record(
  6,
  ItemPowerRecord(
    item: ref(3),
    holderPredicate: ref(4),
    powerPredicate: ref(5),
    value: const BooleanValue(true),
    scope: cell ?? scope,
    validity: validity ?? interval(10),
  ),
);
List<RecordVersion> fixture() => [
  record(
    5,
    PropertyRecord(
      namespace: 'phase',
      key: 'wall_phase',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  power(),
  custody(7, 1),
  assertion(8, 7),
];
List<PowerFact> facts(
  List<RecordVersion> records, {
  int owner = 1,
  int day = 11,
  WorldId? world,
  List<RecordId> predicates = const [],
  FrameTime? time,
  RecordRef? context,
}) => derivePowers(
  records: records,
  subjects: [id(owner)],
  predicates: predicates,
  context: context ?? ref(10),
  time: time ?? AtFrameTime(ExactTime(calendar, '$day')),
  world: world,
);

void main() {
  test('only the actual holder receives a derived grant with its full evidence chain', () {
    final rows = fixture(), found = facts(fixture());
    expect(found.length, 1);
    expect(found.single.subject, ref(1));
    expect(found.single.predicate, ref(5));
    expect(found.single.value, const BooleanValue(true));
    expect(found.single.rule, id(6));
    expect(found.single.evidence, [version(6), version(7), version(8)]);
    expect(facts(rows, owner: 2), isEmpty);
    expect(facts(rows, owner: 3), isEmpty);
    expect(facts(rows, predicates: [id(99)]), isEmpty);
    expect(() => found.single.evidence.clear(), throwsUnsupportedError);
    expect(() => found.clear(), throwsUnsupportedError);
  });

  test('competing or uncertain custody blocks even when the other holder is not requested', () {
    final rows = fixture()
      ..add(custody(11, 2))
      ..add(assertion(12, 11));
    expect(facts(rows), isEmpty);
    expect(facts(rows, owner: 2), isEmpty);
    rows[rows.length - 1] = assertion(
      12,
      11,
      validity: const UnknownValidity(),
    );
    expect(facts(rows), isEmpty);
    rows[rows.length - 1] = assertion(12, 11, precision: Precision.approximate);
    expect(facts(rows), isEmpty);
    rows[rows.length - 1] = assertion(
      12,
      11,
      alternatives: [const IntegerValue('1')],
    );
    expect(facts(rows), isEmpty);
  });

  test('explicit transfer and expiry do not leak prior holder attributes', () {
    final rows = fixture();
    rows[3] = assertion(8, 7, validity: interval(10, 12));
    rows.addAll([
      custody(11, 2),
      assertion(12, 11, validity: interval(12, 15)),
    ]);
    expect(facts(rows, day: 11).length, 1);
    expect(facts(rows, day: 12), isEmpty);
    expect(facts(rows, owner: 2, day: 12).length, 1);
    expect(facts(rows, owner: 2, day: 15), isEmpty);
  });

  test('suspension, restoration and unknown suspension timing remain owner-specific', () {
    RecordVersion suspension(int holder, bool value) => record(
      11,
      PropositionRecord(
        subject: ref(holder),
        predicate: ref(5),
        value: BooleanValue(value),
        context: ref(10),
        quantification: Quantification.particular,
      ),
    );
    final rows = fixture()
      ..add(suspension(1, true))
      ..add(
        assertion(
          12,
          11,
          polarity: Polarity.refutation,
          validity: interval(12, 14),
        ),
      );
    expect(facts(rows, day: 11).length, 1);
    expect(facts(rows, day: 12), isEmpty);
    expect(facts(rows, day: 14).length, 1);
    rows[4] = suspension(2, true);
    expect(facts(rows, day: 12).length, 1);
    rows[4] = suspension(1, false);
    rows[5] = assertion(12, 11, validity: const UnknownValidity());
    expect(facts(rows), isEmpty);
  });

  test(
    'world, represented context and realm never widen a power or custody scope',
    () {
      final w = WorldId.parse('wld_${suffix(32)}'),
          other = WorldId.parse('wld_${suffix(33)}');
      final rows = fixture();
      rows[1] = power(
        cell: Scope(applicability: WorldsApplicability([w]), context: ref(10)),
      );
      expect(facts(rows), isEmpty);
      expect(facts(rows, world: w).length, 1);
      expect(facts(rows, world: other), isEmpty);
      expect(facts(rows, world: w, context: ref(99)), isEmpty);
      rows[1] = power(
        cell: Scope(
          applicability: const UniverseApplicability(),
          context: ref(10),
          realm: ref(99),
        ),
      );
      expect(facts(rows, world: w), isEmpty);
      rows[1] = power();
      rows[3] = assertion(
        8,
        7,
        cell: Scope(applicability: WorldsApplicability([w]), context: ref(10)),
      );
      expect(facts(rows), isEmpty);
      expect(facts(rows, world: w).length, 1);
    },
  );

  test('equivalent custody propositions retain positive chains and unresolved opposition', () {
    final rows = fixture()
      ..add(custody(11, 1))
      ..add(assertion(12, 11));
    expect(rows[2].payloadDigest, rows[4].payloadDigest);
    expect(facts(rows).single.evidence, [
      version(6),
      version(7),
      version(8),
      version(12),
    ]);
    rows.add(
      assertion(
        13,
        11,
        polarity: Polarity.refutation,
        validity: const UnknownValidity(),
      ),
    );
    expect(facts(rows), isEmpty);
    rows[6] = assertion(
      13,
      11,
      polarity: Polarity.refutation,
      validity: interval(20),
    );
    expect(facts(rows).length, 1);
  });

  test('timeless state never grants powers and event boundaries resolve exact custody', () {
    final rows = fixture()
      ..add(
        record(
          20,
          EventRecord(
            occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
            time: ExactTime(calendar, '10'),
            participants: [],
            labels: {},
          ),
        ),
      );
    expect(facts(rows, time: const TimelessFrameTime()), isEmpty);
    expect(
      facts(rows, time: AtEventFrameTime(ref(20), EventTimeSide.before)),
      isEmpty,
    );
    expect(
      facts(rows, time: AtEventFrameTime(ref(20), EventTimeSide.after)).length,
      1,
    );
    expect(
      facts(rows, time: AtEventFrameTime(ref(99), EventTimeSide.after)),
      isEmpty,
    );
  });

  test(
    'record traversal respects the existing possession-effect work bound',
    () {
      final filler = record(99, WorldRecord(selector: 'unused'));
      final rows = List<RecordVersion>.filled(1000001, filler);
      expect(() => facts(rows), throwsA(isA<PowerEvaluationError>()));
      expect(facts(rows, time: const TimelessFrameTime()), isEmpty);
    },
  );
}
