import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/cardinality_checks.dart';

import 'operation_compilation_test.dart' as fixture;

final cal = CalendarId.parse('cal_${fixture.suffix(1)}');
RecordRef ref(int n) => fixture.ref(n);
RecordVersion row(int n, RecordPayload p) => fixture.row(n, p);
Validity interval(int a, int b) =>
    CalendarIntervalValidity(cal, ExactBound('$a'), ExactBound('$b'));
Scope scope({Applicability? applies, int? realm, int context = 3}) => Scope(
  context: ref(context),
  realm: realm == null ? null : ref(realm),
  applicability: applies ?? const UniverseApplicability(),
);
Applicability world(int n) =>
    WorldsApplicability([WorldId.parse('wld_${fixture.suffix(n)}')]);
RelationRecord relation() => RelationRecord(
  namespace: 'test',
  key: 'successor',
  labels: {},
  roles: [
    for (final name in ['office', 'successor'])
      RoleDefinition(
        name: name,
        multiplicity: Multiplicity.single,
        ordered: false,
      ),
  ],
);
RuleRecord rule({
  int maximum = 1,
  CardinalityKey grouping = const SubjectCardinalityKey(),
  Scope? cell,
  Validity? validity,
}) => RuleRecord(
  namespace: 'test',
  key: 'successors',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability: const UniverseApplicability(),
  targetPredicates: [],
  expression: const LiteralExpr(true),
  capabilities: [relationCardinalityCapability],
  executable: true,
  validity: const UnspecifiedValidity(),
  relationCardinality: RelationCardinality(
    relation: ref(2),
    grouping: grouping,
    countedRole: 'successor',
    maximum: maximum,
    scope: cell ?? scope(),
    validity: validity ?? const UnspecifiedValidity(),
  ),
);
List<RecordVersion> base({RuleRecord? policy}) => [
  row(1, policy ?? rule()),
  row(2, relation()),
  row(
    3,
    RepresentedContextRecord(
      universe: fixture.u,
      kind: const ObjectiveContext(),
      labels: {},
    ),
  ),
];
List<RecordVersion> fact(
  int n,
  int participant,
  Validity validity, {
  Scope? cell,
  int subject = 10,
  int office = 10,
  Polarity polarity = Polarity.support,
}) => [
  row(
    n,
    PropositionRecord(
      predicate: ref(2),
      subject: ref(subject),
      context: ref(3),
      roles: [
        PropositionRole('office', ref(office)),
        PropositionRole('successor', ref(participant)),
      ],
      quantification: Quantification.particular,
    ),
  ),
  row(
    n + 1,
    AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: ref(n),
      polarity: polarity,
      scope: cell ?? scope(),
      validity: validity,
      persistence: PersistenceSemantics.explicitInterval,
      precision: Precision.exact,
      basis: const AuthorDecisionBasis('Test relation'),
    ),
  ),
];
RecordVersion get(List<RecordVersion> rows, int n) =>
    rows.firstWhere((r) => r.identity.recordId == fixture.id(n));
void put(List<RecordVersion> rows, int n, RecordPayload payload) =>
    rows[rows.indexOf(get(rows, n))] = row(n, payload);
void edit(List<RecordVersion> rows, int n, Map<String, CanonicalValue> edits) =>
    put(rows, n, fixture.patch(get(rows, n).payload, edits));
Finding assess(List<RecordVersion> rows) =>
    assessRelationCardinality(rows).single;
void expectOutcome(List<RecordVersion> rows, EvidenceOutcome outcome) {
  final f = assess(rows);
  expect(f.outcome, outcome);
  expect(
    f.coverage,
    outcome == EvidenceOutcome.notEstablished
        ? Coverage.unsupported
        : Coverage.complete,
  );
}

void main() {
  test(
    'distinct simultaneous participants and half-open boundaries match Rust',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 12, interval(5, 15)),
      ];
      expectOutcome(rows, EvidenceOutcome.refuted);
      put(rows, 1, rule(maximum: 2));
      expectOutcome(rows, EvidenceOutcome.supported);
      rows.addAll(fact(40, 13, interval(10, 20)));
      // Three total but only two concurrent: pairwise transitive merging is wrong.
      expectOutcome(rows, EvidenceOutcome.supported);
      rows.addAll(fact(50, 13, interval(7, 9)));
      expectOutcome(rows, EvidenceOutcome.refuted);
      expectOutcome([
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 12, interval(10, 20)),
      ], EvidenceOutcome.supported);
    },
  );

  test(
    'repeated and overlapping evidence counts the same participant once',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 11, interval(5, 15)),
      ];
      expectOutcome(rows, EvidenceOutcome.supported);
      rows.addAll(fact(40, 12, const UnknownValidity()));
      expectOutcome(rows, EvidenceOutcome.notEstablished);
      rows.removeRange(7, 9);
      edit(rows, 31, {'polarity': Polarity.refutation.toWire()});
      expectOutcome(rows, EvidenceOutcome.notEstablished);
    },
  );

  test(
    'worlds partition counts and universe-wide facts overlap each world',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10), cell: scope(applies: world(1))),
        ...fact(30, 12, interval(0, 10), cell: scope(applies: world(2))),
      ];
      expectOutcome(rows, EvidenceOutcome.supported);
      edit(rows, 31, {'scope': scope().toWire()});
      expectOutcome(rows, EvidenceOutcome.refuted);
      put(rows, 1, rule(validity: interval(10, 20)));
      expectOutcome(rows, EvidenceOutcome.supported);
      put(rows, 1, rule(cell: scope(applies: world(2))));
      expectOutcome(rows, EvidenceOutcome.supported);
    },
  );

  test('subject and role grouping, contexts and rule windows retain scope', () {
    final rows = [
      ...base(),
      ...fact(20, 11, interval(0, 10)),
      ...fact(30, 12, interval(0, 10), subject: 99),
    ];
    expectOutcome(rows, EvidenceOutcome.supported);
    put(rows, 1, rule(grouping: const RoleCardinalityKey('office')));
    expectOutcome(rows, EvidenceOutcome.refuted);
    edit(rows, 31, {'scope': scope(context: 99).toWire()});
    expectOutcome(rows, EvidenceOutcome.supported);
  });

  test(
    'instant at exclusive end, empty intervals and unrelated clocks match Rust',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 12, InstantValidity(ExactTime(cal, '10'))),
      ];
      expectOutcome(rows, EvidenceOutcome.supported);
      edit(rows, 31, {
        'validity': InstantValidity(ExactTime(cal, '9')).toWire(),
      });
      expectOutcome(rows, EvidenceOutcome.refuted);
      edit(rows, 31, {'validity': interval(5, 5).toWire()});
      expectOutcome(rows, EvidenceOutcome.supported);
      edit(rows, 31, {
        'validity': CalendarIntervalValidity(
          CalendarId.parse('cal_${fixture.suffix(2)}'),
          const ExactBound('0'),
          const ExactBound('10'),
        ).toWire(),
      });
      expectOutcome(rows, EvidenceOutcome.notEstablished);
      edit(rows, 31, {'validity': const UnspecifiedValidity().toWire()});
      expectOutcome(rows, EvidenceOutcome.notEstablished);
      edit(rows, 31, {
        'validity': CalendarIntervalValidity(
          cal,
          const UncertainBound('4', '6'),
          const ExactBound('15'),
        ).toWire(),
      });
      expectOutcome(rows, EvidenceOutcome.notEstablished);
    },
  );

  test('realm partition preserves overlap with realm-unspecified facts', () {
    final rows = [
      ...base(),
      ...fact(20, 11, interval(0, 10), cell: scope(realm: 90)),
      ...fact(30, 12, interval(0, 10), cell: scope(realm: 91)),
    ];
    expectOutcome(rows, EvidenceOutcome.supported);
    edit(rows, 31, {'scope': scope().toWire()});
    expectOutcome(rows, EvidenceOutcome.refuted);
    edit(rows, 31, {
      'scope': scope(applies: const UnspecifiedApplicability()).toWire(),
    });
    expectOutcome(rows, EvidenceOutcome.notEstablished);
    put(rows, 1, rule(cell: scope(realm: 91)));
    expectOutcome(rows, EvidenceOutcome.notEstablished);
  });

  test('authored zero maximum enforces maxima without inventing a minimum', () {
    expectOutcome(base(policy: rule(maximum: 0)), EvidenceOutcome.supported);
    expectOutcome([
      ...base(policy: rule(maximum: 0)),
      ...fact(20, 11, interval(0, 10)),
    ], EvidenceOutcome.refuted);
    expect(assessRelationCardinality(fact(20, 11, interval(0, 10))), isEmpty);
  });

  test(
    'proved violation takes precedence over a separate unresolved count',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 12, interval(0, 10)),
        ...fact(40, 13, const UnknownValidity()),
      ];
      expectOutcome(rows, EvidenceOutcome.refuted);
    },
  );

  test('bounded rule clips evidence and empty rule windows select no time', () {
    final rows = [
      ...base(policy: rule(validity: interval(10, 20))),
      ...fact(20, 11, interval(0, 11)),
      ...fact(30, 12, interval(11, 25)),
    ];
    expectOutcome(rows, EvidenceOutcome.supported);
    put(rows, 1, rule(validity: interval(10, 12)));
    edit(rows, 31, {'validity': interval(10, 25).toWire()});
    expectOutcome(rows, EvidenceOutcome.refuted);
    put(rows, 1, rule(validity: interval(10, 10)));
    expectOutcome(rows, EvidenceOutcome.supported);
    put(rows, 1, rule(validity: const UnknownValidity()));
    expectOutcome(rows, EvidenceOutcome.notEstablished);
  });

  test(
    'unknown scope precision alternatives and role absence stay unresolved',
    () {
      for (final changes in <Map<String, CanonicalValue>>[
        {'precision': CanonicalString('approximate')},
        {
          'alternatives': CanonicalArray([const BooleanValue(true).toWire()]),
        },
        {'scope': scope(applies: const ConditionalApplicability()).toWire()},
        {'scope': scope(applies: const UnspecifiedApplicability()).toWire()},
      ]) {
        final rows = [...base(), ...fact(20, 11, interval(0, 10))];
        edit(rows, 21, changes);
        expectOutcome(rows, EvidenceOutcome.notEstablished);
      }
      final rows = [...base(), ...fact(20, 11, interval(0, 10))];
      edit(rows, 20, {'quantification': CanonicalString('universal')});
      expectOutcome(rows, EvidenceOutcome.notEstablished);
      edit(rows, 20, {
        'quantification': CanonicalString('particular'),
        'roles': CanonicalArray([]),
      });
      expectOutcome(rows, EvidenceOutcome.notEstablished);
    },
  );

  test(
    'refutation matches role sets ignoring order and duplicate role evidence',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 11, interval(0, 10), polarity: Polarity.refutation),
      ];
      edit(rows, 30, {
        'roles': CanonicalArray([
          PropositionRole('successor', ref(11)).toWire(),
          PropositionRole('office', ref(10)).toWire(),
          PropositionRole('successor', ref(11)).toWire(),
        ]),
      });
      expectOutcome(rows, EvidenceOutcome.notEstablished);
      expect(assess(rows).evidence, contains(fixture.ver(31)));
      edit(rows, 31, {'validity': interval(10, 20).toWire()});
      expectOutcome(rows, EvidenceOutcome.supported);
    },
  );

  test('evidence retains sorted exact versions for relevant facts only', () {
    final rows = [
      ...base(),
      ...fact(20, 11, interval(0, 10)),
      ...fact(30, 12, interval(10, 20)),
    ];
    final f = assess(rows);
    expect(f.evidence, [1, 2, 20, 21, 30, 31].map(fixture.ver));
    expect(f.ruleId, fixture.id(1));
    expect(f.records, isEmpty);
    expect(f.fingerprint, FindingFingerprint(''));
    put(rows, 1, rule(validity: interval(30, 40)));
    expect(assess(rows).evidence, [fixture.ver(1), fixture.ver(2)]);
  });

  test(
    'full authored participant namespaces are not normalized for counting',
    () {
      final rows = [
        ...base(),
        ...fact(20, 11, interval(0, 10)),
        ...fact(30, 11, interval(0, 10)),
      ];
      edit(rows, 30, {
        'roles': CanonicalArray([
          PropositionRole('office', ref(10)).toWire(),
          PropositionRole(
            'successor',
            RecordRef(record: fixture.id(11)),
          ).toWire(),
        ]),
      });
      expectOutcome(rows, EvidenceOutcome.refuted);
    },
  );

  test('signed i128 extrema and browser large ticks remain exact', () {
    final min = -(BigInt.one << 127), max = (BigInt.one << 127) - BigInt.one;
    for (final tick in [min, max, BigInt.parse('9007199254740993')]) {
      final at = InstantValidity(ExactTime(cal, '$tick'));
      expectOutcome([
        ...base(),
        ...fact(20, 11, at),
        ...fact(30, 12, at),
      ], EvidenceOutcome.refuted);
    }
    final all = CalendarIntervalValidity(
      cal,
      const UnboundedBound(),
      const UnboundedBound(),
    );
    expectOutcome([
      ...base(),
      ...fact(20, 11, all),
      ...fact(30, 12, InstantValidity(ExactTime(cal, '$max'))),
    ], EvidenceOutcome.refuted);
    final rows = [
      ...base(),
      ...fact(
        20,
        11,
        CalendarIntervalValidity(
          cal,
          const UnboundedBound(),
          ExactBound('$min'),
        ),
      ),
    ];
    expectOutcome(rows, EvidenceOutcome.notEstablished);
    edit(rows, 21, {
      'validity': InstantValidity(ExactTime(cal, '${max + BigInt.one}'))
          .toWire(),
    });
    expectOutcome(rows, EvidenceOutcome.notEstablished);
  });

  test('bounded work does not certify an unfinished count', () {
    final f = fact(20, 11, interval(0, 10));
    final rows = [...base(), f.first, ...List.filled(50001, f.last)];
    expectOutcome(rows, EvidenceOutcome.notEstablished);
    put(rows, 1, rule(maximum: 0));
    expectOutcome(rows, EvidenceOutcome.refuted);
  });

  test('admission requires supported wrapper and real relation roles', () {
    final records = base();
    final valid = rule();
    validateCardinalityRule(valid, records);
    for (final changes in <Map<String, CanonicalValue>>[
      {'relationCardinality': const CanonicalNull()},
      {'executable': const CanonicalBool(false)},
      {'expression': const LiteralExpr(false).encode(canonical: false)},
      {'kind': CanonicalString('law')},
      {'commitPolicy': CanonicalString('advisory')},
      {'validity': interval(0, 10).toWire()},
      {'applicability': world(90).encode(canonical: false)},
      {
        'targetPredicates': CanonicalArray([CanonicalString('test:successor')]),
      },
      {
        'subjectTypes': CanonicalArray([CanonicalString(fixture.id(10).value)]),
      },
      {'capabilities': CanonicalArray([])},
      {
        'capabilities': CanonicalArray([
          CanonicalString(relationCardinalityCapability),
          CanonicalString('other'),
        ]),
      },
      {
        'knowledgePolicy': KnowledgePolicy(
          context: ref(3),
          mode: KnowledgeMode.justified,
        ).toWire(),
      },
      {
        'knowledgeBoundary': KnowledgeBoundary(
          holder: ref(10),
          proposition: ref(20),
          context: ref(3),
        ).toWire(),
      },
      {
        'channelChronology': const ChannelChronology(
          channel: 'speech',
          forwardOnly: true,
        ).toWire(),
      },
    ]) {
      expect(
        () => validateCardinalityRule(fixture.patch(valid, changes), records),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    for (final grouping in [
      const SubjectCardinalityKey(),
      const RoleCardinalityKey('missing'),
    ]) {
      final bad = rule(grouping: grouping);
      final contract = bad.relationCardinality!.toWire();
      final changed = CanonicalObject([
        ...contract.fields.where((e) => e.key != 'countedRole'),
        MapEntry(
          'countedRole',
          CanonicalString(
            grouping is SubjectCardinalityKey ? 'missing' : 'successor',
          ),
        ),
      ]);
      expect(
        () => validateCardinalityRule(
          fixture.patch(bad, {'relationCardinality': changed}),
          records,
        ),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    validateCardinalityRule(
      fixture.patch(valid, {
        'relationCardinality': const CanonicalNull(),
        'capabilities': CanonicalArray([]),
      }),
      records,
    );
  });

  test(
    'admission requires context realm and every declared world to resolve',
    () {
      final rows = base();
      expect(
        () => validateCardinalityRule(rule(cell: scope(context: 4)), rows),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(
        () => validateCardinalityRule(rule(cell: scope(realm: 90)), rows),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(
        () => validateCardinalityRule(
          rule(cell: scope(applies: world(90))),
          rows,
        ),
        throwsA(isA<InvalidArgumentError>()),
      );
      rows.add(row(90, WorldRecord(selector: 'Earth')));
      validateCardinalityRule(rule(cell: scope(applies: world(90))), rows);
      rows.add(row(91, RealmRecord(labels: {}, metadata: {})));
      validateCardinalityRule(rule(cell: scope(realm: 91)), rows);
      put(rows, 2, fixture.entity());
      expect(
        () => validateCardinalityRule(rule(), rows),
        throwsA(isA<InvalidArgumentError>()),
      );
    },
  );
}
