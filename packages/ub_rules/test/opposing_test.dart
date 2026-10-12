import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
Validity interval(int a, int b) =>
    CalendarIntervalValidity(calendar, ExactBound('$a'), ExactBound('$b'));
RecordVersion record(int n, RecordPayload payload, {int? v}) =>
    RecordVersion.build(
      recordVersionId: version(v ?? n),
      identity: RecordIdentity(
        universeId: universe,
        recordId: id(n),
        recordKind: payload.recordKind,
      ),
      payload: payload,
    );
RecordVersion entity(int n) => record(
  n,
  EntityRecord(
    names: [],
    classificationResolution: ClassificationResolution.unclassified,
    worldAssociations: [],
    labels: {},
    metadata: {},
  ),
);
RecordVersion represented(int n) => record(
  n,
  RepresentedContextRecord(
    universe: universe,
    kind: const ObjectiveContext(),
    labels: {},
  ),
);
RecordVersion prop(
  int n, {
  RecordRef? subject,
  RecordRef? context,
  List<PropositionRole> roles = const [],
  DomainValue? value = const BooleanValue(true),
  Quantification quantification = Quantification.particular,
}) => record(
  n,
  PropositionRecord(
    subject: subject ?? ref(1),
    predicate: ref(10),
    context: context ?? ref(3),
    roles: roles,
    value: value,
    quantification: quantification,
  ),
);
RecordVersion assertion(
  int n, {
  int target = 20,
  Polarity? polarity,
  Validity? validity,
  Applicability applicability = const UniverseApplicability(),
  RecordRef? context,
  RecordRef? realm,
  Precision precision = Precision.exact,
  List<DomainValue> alternatives = const [],
  PersistenceSemantics persistence = PersistenceSemantics.explicitInterval,
  EvidenceBasis basis = const AuthorDecisionBasis('opposition fixture'),
}) => record(
  n,
  AssertionRecord(
    attributeMode: AttributeMode.instance,
    proposition: ref(target),
    polarity: polarity ?? (n == 30 ? Polarity.support : Polarity.refutation),
    validity: validity ?? interval(10, 20),
    scope: Scope(
      applicability: applicability,
      context: context ?? ref(3),
      realm: realm,
    ),
    precision: precision,
    alternatives: alternatives,
    persistence: persistence,
    basis: basis,
  ),
);
List<RecordVersion> base() => [
  entity(1),
  entity(2),
  represented(3),
  represented(4),
  entity(8),
  entity(9),
  record(
    10,
    PropertyRecord(
      namespace: 'test',
      key: 'open',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: Multiplicity.multiple,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  prop(20),
  prop(21),
  assertion(30),
  assertion(31),
];
void replace(List<RecordVersion> rows, RecordVersion next) =>
    rows[rows.indexWhere(
          (r) => r.identity.recordId == next.identity.recordId,
        )] =
        next;
OpposingScan scan(
  List<RecordVersion> rows, {
  bool indexed = true,
  int budget = 10000,
}) => detectOpposing(
  universe: universe,
  records: rows,
  indexed: indexed,
  budget: budget,
);
List<(RecordVersionId, RecordVersionId)> pairs(OpposingScan scan) => scan.pairs
    .map(
      (p) => (
        p.support.assertion.recordVersionId,
        p.refutation.assertion.recordVersionId,
      ),
    )
    .toList();
Frame frame({FrameTime? time}) => Frame(
  universe: universe,
  continuity: ContinuityId.parse('cont_${suffix(1)}'),
  revision: RevisionId.parse('rev_${suffix(1)}'),
  context: ref(3),
  time: time ?? AtFrameTime(ExactTime(calendar, '15')),
  perspective: const AuthorPerspective(),
);
(Evidence, bool) noOpposing(
  List<RecordVersion> rows, {
  bool indexed = true,
  List<RecordId>? worlds,
  Frame? selected,
  List<(RecordId, RecordVersion?)> changes = const [],
}) => evaluateExpression(
  NoOpposingEvidenceExpr(
    RecordOperand(ref(1)),
    'test:open',
    RecordOperand(ref(3)),
  ),
  EvaluationContext(
    frame: selected ?? frame(),
    baseSnapshot: rows,
    index: indexed ? EvaluationIndex(rows) : null,
    worldScope: worlds,
    candidateChanges: changes,
  ),
);
void main() {
  test('exact conflict retains serde comparison key, dependencies and deterministic ordering', () {
    final rows = base(), expected = scan(base());
    expect(expected.complete, isTrue);
    expect(expected.comparisons, 1);
    final p = expected.pairs.single;
    expect(p.definite, isTrue);
    expect((p.intersection as ExactIntersection).validity, interval(10, 20));
    expect(p.support.dependencies.map((r) => r.recordVersionId), [
      version(1),
      version(3),
      version(10),
    ]);
    expect(
      utf8.decode(p.comparisonKey),
      '[{"universe":"unv_${suffix(1)}","record":"rec_${suffix(1)}"},"ver_${suffix(10)}","particular",{"universe":"unv_${suffix(1)}","record":"rec_${suffix(3)}"},[]]',
    );
    expect(pairs(scan(rows, indexed: false)), pairs(expected));
    for (var shift = 0; shift < rows.length; shift++) {
      final reordered = [
        ...rows.skip(shift),
        ...rows.take(shift),
      ].reversed.toList();
      final actual = scan(reordered);
      expect(pairs(actual), pairs(expected));
      expect(actual.pairs.single.comparisonKey, p.comparisonKey);
      expect(
        actual.pairs.single.support.dependencies.map((r) => r.recordVersionId),
        p.support.dependencies.map((r) => r.recordVersionId),
      );
    }
    expect(() => p.gaps.clear(), throwsUnsupportedError);
    expect(() => p.comparisonKey.clear(), throwsUnsupportedError);
    expect(() => p.support.dependencies.clear(), throwsUnsupportedError);
  });
  test('distinct identity, context, quantification and unequal values are never grouped', () {
    for (final next in [
      prop(21, subject: ref(2)),
      prop(21, context: ref(4)),
      prop(21, quantification: Quantification.universal),
      prop(21, value: const BooleanValue(false)),
      prop(21, value: null),
    ]) {
      final rows = base();
      replace(rows, next);
      replace(rows, assertion(31, target: 21));
      expect(scan(rows).pairs, isEmpty);
      expect(scan(rows, indexed: false).pairs, isEmpty);
    }
    final rows = base();
    replace(
      rows,
      prop(
        21,
        subject: RecordRef(record: id(1)),
        context: RecordRef(record: id(3)),
      ),
    );
    replace(rows, assertion(31, target: 21));
    expect(scan(rows).pairs.single.definite, isTrue);
  });
  test(
    'world intersections and realm differences retain only overlapping scopes',
    () {
      final a = WorldId.parse('wld_${suffix(41)}'),
          b = WorldId.parse('wld_${suffix(42)}');
      final rows = base();
      replace(
        rows,
        assertion(30, applicability: WorldsApplicability([b, a, a])),
      );
      replace(rows, assertion(31, applicability: WorldsApplicability([a])));
      expect(
        (scan(rows).pairs.single.applicability as WorldsApplicability).worldIds,
        [a],
      );
      replace(
        rows,
        assertion(
          31,
          applicability: WorldsApplicability([
            WorldId.parse('wld_${suffix(43)}'),
          ]),
        ),
      );
      expect(scan(rows).pairs, isEmpty);
      replace(rows, assertion(31, applicability: WorldsApplicability([])));
      expect(scan(rows).pairs, isEmpty);
      replace(
        rows,
        assertion(31, applicability: const ConditionalApplicability()),
      );
      expect(scan(rows).pairs.single.gaps, contains(OpposingGap.worlds));
      replace(rows, assertion(30, realm: ref(8)));
      replace(rows, assertion(31, realm: ref(9)));
      expect(scan(rows).pairs, isEmpty);
      replace(rows, assertion(31));
      expect(scan(rows).pairs.single.gaps, contains(OpposingGap.realm));
      replace(rows, assertion(30, context: ref(4)));
      expect(scan(rows).pairs.single.gaps, contains(OpposingGap.context));
    },
  );
  test('half-open overlap matches the existing discrete interval cases', () {
    for (var start = -10; start <= 10; start++) {
      for (var end = start; end <= 10; end++) {
        final rows = base();
        replace(rows, assertion(30, validity: interval(-3, 4)));
        replace(rows, assertion(31, validity: interval(start, end)));
        final found = scan(rows).pairs;
        final ticks = [
          for (var n = start; n < end; n++)
            if (n >= -3 && n < 4) n,
        ];
        expect(found.isEmpty, ticks.isEmpty);
        if (ticks.isNotEmpty) {
          expect(
            (found.single.intersection as ExactIntersection).validity,
            interval(ticks.first, ticks.last + 1),
          );
        }
      }
    }
    final rows = base();
    replace(
      rows,
      assertion(31, validity: InstantValidity(ExactTime(calendar, '20'))),
    );
    expect(scan(rows).pairs, isEmpty);
    replace(
      rows,
      assertion(31, validity: InstantValidity(ExactTime(calendar, '19'))),
    );
    expect(
      (scan(rows).pairs.single.intersection as ExactIntersection).validity,
      InstantValidity(ExactTime(calendar, '19')),
    );
  });
  test(
    'uncertain, unknown and unqualified time retain their separate meanings',
    () {
      final rows = base();
      replace(
        rows,
        assertion(
          31,
          validity: CalendarIntervalValidity(
            calendar,
            const UncertainBound('12', '14'),
            const ExactBound('18'),
          ),
        ),
      );
      final p = scan(rows).pairs.single;
      expect(p.definite, isTrue);
      expect(scan(rows).complete, isFalse);
      expect(
        (p.intersection as UncertainIntersection).guaranteed,
        interval(14, 18),
      );
      for (final validity in [
        const UnknownValidity(),
        CalendarIntervalValidity(
          CalendarId.parse('cal_${suffix(2)}'),
          const ExactBound('10'),
          const ExactBound('20'),
        ),
        CalendarIntervalValidity(
          calendar,
          const UncertainBound('18', '22'),
          const ExactBound('30'),
        ),
        const IntervalValidity(ExactBound('10'), ExactBound('20')),
      ]) {
        replace(rows, assertion(31, validity: validity));
        expect(
          scan(rows).pairs.single.intersection,
          isA<UnresolvedIntersection>(),
        );
        expect(scan(rows).pairs.single.gaps, contains(OpposingGap.time));
      }
      replace(rows, assertion(30, validity: const UnspecifiedValidity()));
      replace(rows, assertion(31, validity: const UnspecifiedValidity()));
      expect(
        scan(rows).pairs.single.intersection,
        isA<UnqualifiedIntersection>(),
      );
      expect(scan(rows).complete, isTrue);
    },
  );
  test('precision, alternatives and persistent conditions never become exact conflicts', () {
    for (final a in [
      assertion(31, precision: Precision.approximate),
      assertion(31, alternatives: [const BooleanValue(false)]),
      assertion(31, persistence: PersistenceSemantics.persistentUntilChanged),
      assertion(31, persistence: PersistenceSemantics.conditionDependent),
    ]) {
      final rows = base();
      replace(rows, a);
      expect(scan(rows).pairs.single.definite, isFalse);
      expect(scan(rows).complete, isFalse);
    }
    final rows = base()..add(assertion(32, validity: const UnknownValidity()));
    expect(scan(rows).pairs.where((p) => p.definite).length, 1);
    expect(scan(rows).complete, isFalse);
  });
  test('provenance follows exact version links without substituting active replacements', () {
    final rows = base();
    replace(
      rows,
      assertion(
        31,
        basis: DerivationBasis([
          VersionRef(universe: universe, record: id(1), version: version(999)),
        ], 'fixture'),
      ),
    );
    final p = scan(rows).pairs.single;
    expect(p.definite, isTrue);
    expect(p.refutation.complete, isFalse);
    expect(p.gaps, {OpposingGap.provenance});
    expect(scan(rows).complete, isFalse);
    replace(
      rows,
      assertion(
        31,
        basis: DerivationBasis([
          VersionRef(universe: universe, record: id(1), version: version(1)),
        ], 'fixture'),
      ),
    );
    expect(scan(rows).complete, isTrue);
    replace(rows, assertion(31, basis: const ImportedClaimBasis()));
    expect(scan(rows).pairs.single.definite, isTrue);
    expect(scan(rows).complete, isFalse);
  });
  test('pairwise numeric equality, quantities and unresolved equality remain distinct', () {
    final rows = base();
    replace(rows, assertion(31, target: 21));
    replace(rows, prop(20, value: const IntegerValue('1')));
    replace(rows, prop(21, value: const RationalValue('2', '2')));
    expect(scan(rows).pairs.single.definite, isTrue);
    replace(rows, prop(21, value: const IntegerValue('2')));
    expect(scan(rows).pairs, isEmpty);
    replace(rows, prop(20, value: SequenceValue([const BooleanValue(true)])));
    replace(rows, prop(21, value: SequenceValue([const BooleanValue(false)])));
    expect(scan(rows).pairs.single.gaps, contains(OpposingGap.equality));
    final unit = UnitId.parse('unit_${suffix(1)}');
    replace(
      rows,
      prop(20, value: QuantityValue(const DecimalValue('1.0'), unit)),
    );
    replace(
      rows,
      prop(21, value: QuantityValue(const DecimalValue('1.00'), unit)),
    );
    expect(scan(rows).pairs.single.definite, isTrue);
  });
  test(
    'named role multisets preserve multiplicity and normalize references',
    () {
      final rows = base();
      replace(
        rows,
        record(
          10,
          RelationRecord(
            namespace: 'test',
            key: 'open',
            labels: {},
            roles: [
              RoleDefinition(
                name: 'from',
                multiplicity: Multiplicity.single,
                ordered: false,
              ),
              RoleDefinition(
                name: 'to',
                multiplicity: Multiplicity.single,
                ordered: false,
              ),
            ],
          ),
        ),
      );
      replace(
        rows,
        prop(
          20,
          roles: [
            PropositionRole('from', ref(8)),
            PropositionRole('to', ref(9)),
          ],
        ),
      );
      replace(
        rows,
        prop(
          21,
          roles: [
            PropositionRole('to', RecordRef(record: id(9))),
            PropositionRole('from', ref(8)),
          ],
        ),
      );
      replace(rows, assertion(31, target: 21));
      expect(scan(rows).pairs.single.definite, isTrue);
      replace(
        rows,
        prop(
          21,
          roles: [
            PropositionRole('from', ref(8)),
            PropositionRole('to', ref(9)),
            PropositionRole('to', ref(9)),
          ],
        ),
      );
      expect(scan(rows).pairs, isEmpty);
      replace(rows, prop(21, roles: [PropositionRole('invented', ref(8))]));
      expect(() => scan(rows), throwsA(isA<OpposingError>()));
    },
  );
  test('bounded detection rejects ambiguous or invalid active membership', () {
    final rows = base();
    expect(scan([...rows, ...base()]).comparisons, 1);
    expect(
      () => scan([...rows, record(1, entity(1).payload, v: 999)]),
      throwsA(isA<OpposingError>()),
    );
    expect(
      () => scan(rows.where((r) => r.identity.recordId != id(10)).toList()),
      throwsA(isA<OpposingError>()),
    );
    expect(
      () => scan(List.filled(10001, rows.first)),
      throwsA(isA<OpposingError>()),
    );
    final partial = scan(rows, budget: 0);
    expect(partial.complete, isFalse);
    expect(partial.gaps, {OpposingGap.budget});
    expect(partial.comparisons, 0);
    expect(
      scan(
        rows.where((r) => r.identity.recordId != id(31)).toList(),
        budget: 0,
      ).complete,
      isTrue,
    );
  });
  test('indexing preserves multiple pairs while charging only coarse meaning candidates', () {
    final rows = base()
      ..addAll([
        prop(22, subject: ref(2)),
        assertion(32, target: 22, polarity: Polarity.support),
        assertion(33, target: 22),
      ]);
    final indexed = scan(rows), reference = scan(rows, indexed: false);
    expect(pairs(indexed), [
      (version(30), version(31)),
      (version(32), version(33)),
    ]);
    expect(pairs(reference), pairs(indexed));
    expect(indexed.comparisons, 2);
    expect(reference.comparisons, 4);
    final partial = scan(rows, budget: 1);
    expect(pairs(partial), [(version(30), version(31))]);
    expect(partial.complete, isFalse);
    expect(partial.gaps, {OpposingGap.budget});
    expect(pairs(scan(rows.reversed.toList())), pairs(indexed));
  });
  test(
    'invalid namespaces and represented contexts reject admission to the scan',
    () {
      final rows = base();
      final other = UniverseId.parse('unv_${suffix(99)}');
      rows.add(
        RecordVersion(
          recordVersionId: version(99),
          identity: RecordIdentity(
            universeId: other,
            recordId: id(99),
            recordKind: RecordKind.entity,
          ),
          payload: entity(99).payload,
          payloadDigest: entity(99).payloadDigest,
        ),
      );
      expect(() => scan(rows), throwsA(isA<OpposingError>()));
      rows.removeLast();
      replace(
        rows,
        prop(
          21,
          subject: RecordRef(universe: other, record: id(1)),
        ),
      );
      replace(rows, assertion(31, target: 21));
      expect(() => scan(rows), throwsA(isA<OpposingError>()));
      replace(rows, prop(21));
      replace(rows, entity(3));
      expect(() => scan(rows), throwsA(isA<OpposingError>()));
      replace(rows, represented(3));
      replace(rows, assertion(31, target: 1));
      expect(() => scan(rows), throwsA(isA<OpposingError>()));
    },
  );
  test('no-opposing expression retains exact conflict evidence and candidate removals', () {
    for (final indexed in [false, true]) {
      final (e, c) = noOpposing(base(), indexed: indexed);
      expect(e.outcome, EvidenceOutcome.refuted);
      expect(c, isTrue);
      expect(e.refutation.sources, [
        version(30),
        version(20),
        version(1),
        version(3),
        version(10),
        version(31),
        version(20),
        version(1),
        version(3),
        version(10),
      ]);
      expect(
        noOpposing(
          base(),
          indexed: indexed,
          changes: [(id(31), null)],
        ).$1.outcome,
        EvidenceOutcome.supported,
      );
    }
    final rows = base();
    replace(rows, assertion(31, precision: Precision.approximate));
    expect(noOpposing(rows).$1.outcome, EvidenceOutcome.notEstablished);
    expect(noOpposing(rows).$2, isFalse);
    replace(rows, assertion(31, basis: const ImportedClaimBasis()));
    expect(noOpposing(rows).$1.outcome, EvidenceOutcome.refuted);
    expect(noOpposing(rows).$2, isFalse);
  });
  test('expression world/time filtering cannot turn an unresolved overlapping pair into a pass', () {
    final rows = base();
    final w = WorldId.parse('wld_${suffix(41)}');
    replace(rows, assertion(31, applicability: WorldsApplicability([w])));
    expect(noOpposing(rows).$2, isFalse);
    expect(noOpposing(rows).$1.outcome, EvidenceOutcome.notEstablished);
    expect(
      noOpposing(rows, worlds: [id(41)]).$1.outcome,
      EvidenceOutcome.refuted,
    );
    expect(
      noOpposing(rows, worlds: [id(42)]).$1.outcome,
      EvidenceOutcome.supported,
    );
    replace(rows, assertion(31, validity: interval(20, 30)));
    expect(noOpposing(rows).$1.outcome, EvidenceOutcome.supported);
    replace(rows, assertion(30, validity: const UnspecifiedValidity()));
    replace(rows, assertion(31, validity: const UnspecifiedValidity()));
    expect(noOpposing(rows).$1.outcome, EvidenceOutcome.refuted);
    expect(
      noOpposing(
        rows,
        selected: frame(time: const TimelessFrameTime()),
      ).$1.outcome,
      EvidenceOutcome.refuted,
    );
  });
}
