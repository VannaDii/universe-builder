import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/resource_checks.dart';

import 'operation_compilation_test.dart' as f;

final cal = CalendarId.parse('cal_${f.suffix(6)}');
final frame = Frame(
  universe: f.u,
  continuity: ContinuityId.parse('cont_${f.suffix(1)}'),
  revision: f.revision,
  context: f.ref(5),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);
PropositionRecord proposition(String value) => PropositionRecord(
  subject: f.ref(3),
  predicate: f.ref(4),
  value: IntegerValue(value),
  quantification: Quantification.particular,
  context: f.ref(5),
);
AssertionRecord assertion(int p, int start, int end) => AssertionRecord(
  attributeMode: AttributeMode.instance,
  proposition: f.ref(p),
  polarity: Polarity.support,
  scope: Scope(context: f.ref(5), applicability: const UniverseApplicability()),
  validity: CalendarIntervalValidity(
    cal,
    ExactBound('$start'),
    ExactBound('$end'),
  ),
  persistence: PersistenceSemantics.explicitInterval,
  precision: Precision.exact,
  basis: const AuthorDecisionBasis('Stock evidence'),
);
RuleRecord rule() => RuleRecord(
  namespace: 'resource',
  key: 'accounting',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: CommitPolicy.blockUnlessException,
  applicability: const UniverseApplicability(),
  targetPredicates: ['resource:rounds'],
  expression: const LiteralExpr(true),
  capabilities: [resourceAccountingCapability],
  executable: true,
  validity: const UnspecifiedValidity(),
);
List<RecordVersion> fixture() => [
  f.row(3, f.entity()),
  f.row(
    4,
    PropertyRecord(
      namespace: 'resource',
      key: 'rounds',
      labels: {},
      subjectTypes: [],
      value: const SimpleValueShape(SimpleShapeKind.integer),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  f.row(9, rule()),
  f.row(10, proposition('1')),
  f.row(11, assertion(10, 0, 5)),
  f.row(12, proposition('2')),
  f.row(13, assertion(12, 5, 20)),
];
IssueDecisionRecord accept(ResourceGap gap, {String? rationale}) =>
    IssueDecisionRecord(
      fingerprints: [gap.fingerprint],
      mode: IssueDecisionMode.accept,
      scope: 'resource:${gap.proposition.value}',
      rationale: rationale ?? 'Author accepts the exact unexplained arrival',
      principal: PrincipalId.parse('prn_${f.suffix(1)}'),
    );
List<ResourceGap> assess(List<RecordVersion> records) =>
    assessResourceAccounting(records, frame);
RecordVersion get(List<RecordVersion> records, int n) =>
    records.firstWhere((r) => r.identity.recordId == f.id(n));
void put(List<RecordVersion> records, int n, RecordPayload p) =>
    records[records.indexOf(get(records, n))] = f.row(n, p);
void edit(
  List<RecordVersion> records,
  int n,
  Map<String, CanonicalValue> changes,
) => put(records, n, f.patch(get(records, n).payload, changes));

void main() {
  test('unexplained arrival needs separate exact acceptance and preserves evidence', () {
    final records = fixture();
    final gap = assess(records).single;
    expect(
      gap.fingerprint.value,
      'a83f2bb1814718261840609516169513da91564bf89abc07f184996f32f67074',
    );
    expect(gap.rule, f.id(9));
    expect(gap.assertion, f.id(13));
    expect(gap.proposition, f.id(12));
    expect(gap.evidence, [4, 9, 11, 13].map(f.ver));
    expect(gap.acceptance, isNull);
    records.add(f.row(14, accept(gap)));
    final accepted = assess(records).single;
    expect(accepted.fingerprint, gap.fingerprint);
    expect(accepted.acceptance, f.id(14));
    expect(accepted.evidence, [4, 9, 11, 13, 14].map(f.ver));
    put(records, 12, proposition('3'));
    expect(assess(records).single.acceptance, isNull);
  });

  test(
    'coherent earlier correction removes the jump without inventing an event',
    () {
      final records = fixture();
      put(records, 10, proposition('2'));
      expect(assess(records), isEmpty);
    },
  );

  test(
    'generated versions do not change reviewed contents or exact acceptance',
    () {
      final records = fixture();
      final gap = assess(records).single;
      records.add(f.row(14, accept(gap)));
      final regenerated = [
        for (var i = 0; i < records.length; i++)
          RecordVersion.build(
            recordVersionId: f.ver(100 + i),
            identity: records[i].identity,
            payload: records[i].payload,
          ),
      ];
      expect(assess(regenerated).single.fingerprint, gap.fingerprint);
      expect(assess(regenerated).single.acceptance, f.id(14));
      expect(assess(regenerated).single.evidence, isNot(contains(f.ver(13))));
    },
  );

  test(
    'acceptance becomes stale after time predecessor or policy corrections',
    () {
      for (final target in [10, 13, 9, 4]) {
        final records = fixture();
        records.add(f.row(14, accept(assess(records).single)));
        switch (target) {
          case 10:
            put(records, 10, proposition('0'));
          case 13:
            put(records, 13, assertion(12, 6, 20));
          case 9:
            edit(records, 9, {
              'labels': CanonicalObject([
                MapEntry('en', CanonicalString('Changed policy')),
              ]),
            });
          case 4:
            edit(records, 4, {
              'labels': CanonicalObject([
                MapEntry('en', CanonicalString('Changed property')),
              ]),
            });
        }
        expect(assess(records).single.acceptance, isNull);
      }
    },
  );

  test('opt-in required and uncertain stock fails closed', () {
    final records = fixture();
    records.removeWhere((r) => r.identity.recordId == f.id(9));
    expect(assess(records), isEmpty);
    for (final changes in <Map<String, CanonicalValue>>[
      {'precision': CanonicalString('unresolved')},
      {
        'alternatives': CanonicalArray([IntegerValue('2').toWire()]),
      },
      {'validity': const UnspecifiedValidity().toWire()},
      {
        'validity': CalendarIntervalValidity(
          cal,
          const UnknownBound(),
          const UnboundedBound(),
        ).toWire(),
      },
      {
        'validity': CalendarIntervalValidity(
          cal,
          const ExactBound('5\n'),
          const UnboundedBound(),
        ).toWire(),
      },
      {
        'scope': Scope(
          context: f.ref(5),
          realm: f.ref(80),
          applicability: const UniverseApplicability(),
        ).toWire(),
      },
      {
        'scope': Scope(
          context: f.ref(5),
          applicability: const UnspecifiedApplicability(),
        ).toWire(),
      },
    ]) {
      final rows = fixture();
      edit(rows, 13, changes);
      expect(() => assess(rows), throwsA(isA<InvalidArgumentError>()));
    }
  });

  test(
    'acceptance must match one fingerprint scope mode and nonblank rationale',
    () {
      for (final changes in <Map<String, CanonicalValue>>[
        {'fingerprints': CanonicalArray([])},
        {'mode': CanonicalString('defer')},
        {'scope': CanonicalString('other')},
        {'rationale': CanonicalString(' \u0085\u3000')},
      ]) {
        final records = fixture();
        final decision = f.patch(accept(assess(records).single), changes);
        records.add(f.row(14, decision));
        expect(assess(records).single.acceptance, isNull);
      }
      final records = fixture();
      records.add(
        f.row(14, accept(assess(records).single, rationale: '\ufeff')),
      );
      expect(assess(records).single.acceptance, f.id(14));
    },
  );

  test(
    'last preceding stock is used rather than oldest history or query time',
    () {
      final records = fixture();
      records.addAll([
        f.row(15, proposition('1')),
        f.row(16, assertion(15, 21, 30)),
      ]);
      final gaps = assess(records);
      expect(gaps.length, 2);
      expect(gaps.last.evidence, contains(f.ver(13)));
      expect(gaps.last.evidence, isNot(contains(f.ver(11))));
      put(records, 15, proposition('2'));
      expect(assess(records).length, 1);
    },
  );

  test(
    'independent clocks subjects and contexts do not become predecessors',
    () {
      for (final change in <Map<String, CanonicalValue>>[
        {'subject': f.ref(80).toCanonical()},
        {'context': f.ref(80).toCanonical()},
      ]) {
        final records = fixture();
        edit(records, 10, change);
        expect(assess(records), isEmpty);
      }
      final records = fixture();
      edit(records, 11, {
        'validity': CalendarIntervalValidity(
          CalendarId.parse('cal_${f.suffix(7)}'),
          const ExactBound('0'),
          const ExactBound('5'),
        ).toWire(),
      });
      expect(assess(records), isEmpty);
    },
  );

  test(
    'only an explicitly linked delta consequence accounts for an arrival',
    () {
      final records = fixture();
      final scope = Scope(
        context: f.ref(5),
        applicability: const UniverseApplicability(),
      );
      ActionDefinitionRecord action(EffectChange change) =>
          ActionDefinitionRecord(
            namespace: 'resource',
            key: 'load',
            labels: {},
            requirements: [],
            scope: scope,
            validity: const UnspecifiedValidity(),
            consequenceContract: ConsequenceContract([
              EffectSlot(
                slot: 'rounds',
                order: 0,
                presence: EffectPresence.required,
                target: EffectTarget('actor', f.ref(4)),
                condition: const AlwaysEffect(),
                change: change,
                lifetime: const UntilChangedEffect(),
              ),
            ]),
          );
      records.add(
        f.row(
          80,
          action(
            DeltaEffect(
              delta: ConsequenceDecimal('1'),
              minimum: ConsequenceDecimal('0'),
              maximum: ConsequenceDecimal('10'),
              unit: null,
            ),
          ),
        ),
      );
      records.add(
        f.row(
          81,
          EventRecord(
            occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
            action: f.ref(80),
            time: ExactTime(cal, '5'),
            participants: [EventParticipant(f.ref(3), 'actor')],
            labels: {},
          ),
        ),
      );
      edit(records, 13, {
        'establishedBy': EventEffectRef(f.ref(81), 'rounds').toWire(),
      });
      expect(assess(records), isEmpty);
      edit(records, 13, {
        'establishedBy': EventEffectRef(f.ref(81), 'other').toWire(),
      });
      expect(assess(records).length, 1);
      edit(records, 13, {
        'establishedBy': EventEffectRef(f.ref(81), 'rounds').toWire(),
      });
      put(records, 80, action(SetEffect(Polarity.support, IntegerValue('2'))));
      expect(assess(records).length, 1);
    },
  );

  test('worlds preserve separate baselines and policy applicability', () {
    final records = fixture();
    Scope scoped(int n) => Scope(
      context: f.ref(5),
      applicability: WorldsApplicability([WorldId.parse('wld_${f.suffix(n)}')]),
    );
    edit(records, 11, {'scope': scoped(80).toWire()});
    edit(records, 13, {'scope': scoped(81).toWire()});
    expect(assess(records), isEmpty);
    edit(records, 13, {'scope': scoped(80).toWire()});
    expect(assess(records).length, 1);
    edit(records, 9, {
      'applicability': scoped(81).applicability.encode(canonical: false),
    });
    expect(assess(records), isEmpty);
  });

  test('universe-wide stock creates separately bound gaps for each world', () {
    final records = fixture();
    records.addAll([
      f.row(80, WorldRecord(selector: 'A')),
      f.row(81, WorldRecord(selector: 'B')),
    ]);
    final gaps = assess(records);
    expect(gaps.length, 2);
    expect(gaps[0].fingerprint, isNot(gaps[1].fingerprint));
    records.add(f.row(14, accept(gaps.first)));
    final accepted = assess(records);
    expect(accepted[0].acceptance, f.id(14));
    expect(accepted[1].acceptance, isNull);
  });

  test(
    'exact numeric equality corroborates a baseline across representations',
    () {
      final records = fixture();
      put(records, 10, proposition('2'));
      edit(records, 12, {'value': DecimalValue('2.0').toWire()});
      expect(assess(records), isEmpty);
      edit(records, 12, {'value': DecimalValue('2.1').toWire()});
      expect(assess(records).length, 1);
    },
  );

  test(
    'unknown rule timing fails closed and excluded rule timing skips gaps',
    () {
      final records = fixture();
      edit(records, 9, {'validity': const UnknownValidity().toWire()});
      expect(() => assess(records), throwsA(isA<InvalidArgumentError>()));
      edit(records, 9, {
        'validity': CalendarIntervalValidity(
          cal,
          const ExactBound('10'),
          const ExactBound('20'),
        ).toWire(),
      });
      expect(assess(records), isEmpty);
    },
  );

  test('bounded accounting work cannot return partially assessed gaps', () {
    final records = fixture();
    for (var i = 0; i < 800; i++) {
      final n = 100 + i * 2;
      records.addAll([
        f.row(n, proposition('${i % 2 + 1}')),
        f.row(n + 1, assertion(n, 30 + i, 31 + i)),
      ]);
    }
    expect(() => assess(records), throwsA(isA<InvalidArgumentError>()));
  });

  test('policy needs one numeric single property and explicit exception resolution', () {
    for (final changes in <Map<String, CanonicalValue>>[
      {'executable': const CanonicalBool(false)},
      {'commitPolicy': CanonicalString('always_block')},
      {'targetPredicates': CanonicalArray([])},
      {
        'targetPredicates': CanonicalArray([CanonicalString('missing:stock')]),
      },
    ]) {
      final records = fixture();
      edit(records, 9, changes);
      expect(() => assess(records), throwsA(isA<InvalidArgumentError>()));
    }
    final records = fixture();
    records.add(f.row(80, get(records, 4).payload));
    expect(() => assess(records), throwsA(isA<InvalidArgumentError>()));
    records.removeLast();
    edit(records, 4, {'multiplicity': CanonicalString('multiple')});
    expect(() => assess(records), throwsA(isA<InvalidArgumentError>()));
  });
}
