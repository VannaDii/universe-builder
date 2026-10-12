import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/knowledge_checks.dart';

import 'communication_checks_test.dart' as channels;
import 'operation_compilation_test.dart' as operations;
import 'rule_checks_test.dart' as facts;

RuleRecord policy({
  KnowledgeMode mode = KnowledgeMode.justified,
  RecordRef? context,
}) => RuleRecord(
  namespace: 'test',
  key: 'knowledge',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability: const UniverseApplicability(),
  targetPredicates: [],
  expression: const LiteralExpr(true),
  capabilities: [knowledgeAcquisitionCapability],
  executable: true,
  validity: const UnspecifiedValidity(),
  knowledgePolicy: KnowledgePolicy(
    context: context ?? facts.ref(99),
    mode: mode,
  ),
);

KnowledgeAcquisition acquisition({
  KnowledgeBasis? basis,
  TemporalExpression? time,
  RecordRef? context,
  RecordRef? world,
}) => KnowledgeAcquisition(
  truthContext: context ?? facts.ref(99),
  time: time ?? ExactTime(facts.calendar, '12'),
  world: world,
  basis:
      basis ??
      CommunicationKnowledge(
        communication: facts.ref(9),
        interpretation: facts.ref(2),
      ),
);

EpistemicAttitudeRecord attitude({
  KnowledgeAcquisition? declared,
  bool legacy = false,
  Validity? validity,
  EvidenceBasis basis = const AuthorDecisionBasis('Declared acquisition'),
  EpistemicAttitudeKind kind = EpistemicAttitudeKind.knows,
}) => EpistemicAttitudeRecord(
  holder: facts.ref(80),
  proposition: facts.ref(2),
  attitude: kind,
  validity: validity ?? InstantValidity(ExactTime(facts.calendar, '12')),
  basis: basis,
  acquisition: legacy ? null : declared ?? acquisition(),
);

CommunicationRecord message() => CommunicationRecord(
  sender: facts.ref(81),
  intendedRecipients: [facts.ref(80)],
  actualRecipients: [facts.ref(80)],
  content: [facts.ref(2)],
  channel: 'speech',
  sentAt: ExactTime(facts.calendar, '10'),
  receivedAt: ExactTime(facts.calendar, '11'),
  distorted: false,
);

List<RecordVersion> fixture() => [
  ...facts.fixture().where((r) => r.identity.recordId != facts.id(4)),
  facts.record(6, attitude()),
  facts.record(7, policy()),
  facts.record(8, channels.policy()),
  facts.record(9, message()),
];

RecordVersion get(List<RecordVersion> rows, int n) =>
    rows.firstWhere((r) => r.identity.recordId == facts.id(n));
void put(List<RecordVersion> rows, int n, RecordPayload payload) =>
    facts.replace(rows, facts.record(n, payload));
void edit(List<RecordVersion> rows, int n, Map<String, CanonicalValue> edits) =>
    put(rows, n, operations.patch(get(rows, n).payload, edits));
List<Finding> assess(List<RecordVersion> rows) =>
    assessKnowledgeAcquisition(rows, facts.frame());
void expectOutcome(
  List<RecordVersion> rows,
  EvidenceOutcome expected, {
  String? repair,
}) {
  final f = assess(rows).single;
  expect(f.outcome, expected);
  expect(
    f.coverage,
    expected == EvidenceOutcome.notEstablished
        ? Coverage.unsupported
        : Coverage.complete,
  );
  if (repair != null) expect(f.message, contains(repair));
}

void main() {
  test(
    'justified receipt requires truth and retains sorted unique dependencies',
    () {
      final rows = fixture();
      expectOutcome(rows, EvidenceOutcome.supported);
      final f = assess(rows).single;
      expect(f.ruleId, facts.id(7));
      expect(f.records, isEmpty);
      expect(f.fingerprint, FindingFingerprint(''));
      expect(
        f.evidence,
        containsAll([1, 2, 3, 6, 7, 8, 9, 99].map(facts.version)),
      );
      expect(f.evidence.toSet().length, f.evidence.length);
      final sorted = f.evidence.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      expect(f.evidence, sorted);
    },
  );

  test('legacy knowledge is constrained only by a matching context policy', () {
    final rows = fixture();
    put(rows, 6, attitude(legacy: true));
    expectOutcome(
      rows,
      EvidenceOutcome.notEstablished,
      repair: 'explicit acquisition',
    );
    put(rows, 7, policy(context: facts.ref(98)));
    expect(assess(rows), isEmpty);
    rows.removeWhere((r) => r.identity.recordId == facts.id(7));
    expect(assess(rows), isEmpty);
    put(rows, 6, attitude());
    expectOutcome(
      rows,
      EvidenceOutcome.notEstablished,
      repair: 'No matching knowledge policy',
    );
    expect(assess(rows).single.evidence, [facts.version(6)]);
  });

  test('belief, suspicion, rejection and memory never become knowledge', () {
    for (final kind in EpistemicAttitudeKind.values.where(
      (v) => v != EpistemicAttitudeKind.knows,
    )) {
      final rows = fixture();
      put(rows, 6, attitude(kind: kind));
      expect(assess(rows), isEmpty);
    }
  });

  test(
    'author establishment needs the matching policy and author decision basis',
    () {
      final rows = fixture();
      put(rows, 7, policy(mode: KnowledgeMode.authorEstablished));
      put(
        rows,
        6,
        attitude(
          declared: acquisition(basis: const AuthorEstablishedKnowledge()),
        ),
      );
      // This mode does not require asserted truth or a delivery.
      rows.removeWhere(
        (r) => [3, 8, 9].map(facts.id).contains(r.identity.recordId),
      );
      expectOutcome(rows, EvidenceOutcome.supported);
      edit(rows, 6, {'basis': const ImportedClaimBasis().toWire()});
      expectOutcome(
        rows,
        EvidenceOutcome.notEstablished,
        repair: 'acquisition basis',
      );
    },
  );

  test('policy modes cannot substitute for one another', () {
    final rows = fixture();
    put(
      rows,
      6,
      attitude(
        declared: acquisition(basis: const AuthorEstablishedKnowledge()),
      ),
    );
    expectOutcome(rows, EvidenceOutcome.refuted, repair: 'acquisition basis');
    put(rows, 6, attitude());
    put(rows, 7, policy(mode: KnowledgeMode.authorEstablished));
    expectOutcome(rows, EvidenceOutcome.refuted, repair: 'acquisition basis');
  });

  test(
    'acquisition at onset is inclusive for instant and interval validity',
    () {
      final rows = fixture();
      put(
        rows,
        6,
        attitude(
          validity: CalendarIntervalValidity(
            facts.calendar,
            const ExactBound('12'),
            const UnboundedBound(),
          ),
        ),
      );
      expectOutcome(rows, EvidenceOutcome.supported);
      put(
        rows,
        6,
        attitude(validity: InstantValidity(ExactTime(facts.calendar, '11'))),
      );
      expectOutcome(rows, EvidenceOutcome.refuted, repair: 'knowledge onset');
      for (final validity in [
        const UnspecifiedValidity(),
        CalendarIntervalValidity(
          facts.calendar,
          const UnboundedBound(),
          const UnboundedBound(),
        ),
        InstantValidity(ExactTime(channels.otherCal, '12')),
      ]) {
        put(rows, 6, attitude(validity: validity));
        expectOutcome(
          rows,
          EvidenceOutcome.notEstablished,
          repair: 'knowledge onset',
        );
      }
    },
  );

  test('acquisition clock accepts only exact signed i128 ticks', () {
    for (final time in [
      const UnspecifiedTime(),
      ExactTime(facts.calendar, '12\n'),
      ExactTime(facts.calendar, '${BigInt.one << 127}'),
      ExactTime(channels.otherCal, '12'),
    ]) {
      final rows = fixture();
      put(rows, 6, attitude(declared: acquisition(time: time)));
      expectOutcome(rows, EvidenceOutcome.notEstablished);
    }
    final rows = fixture();
    put(rows, 7, policy(mode: KnowledgeMode.authorEstablished));
    final coordinate = BigInt.parse('9007199254740993');
    put(
      rows,
      6,
      attitude(
        declared: acquisition(
          basis: const AuthorEstablishedKnowledge(),
          time: ExactTime(facts.calendar, '+0$coordinate'),
        ),
        validity: InstantValidity(ExactTime(facts.calendar, '$coordinate')),
      ),
    );
    expectOutcome(rows, EvidenceOutcome.supported);
    put(
      rows,
      6,
      attitude(
        declared: acquisition(
          basis: const AuthorEstablishedKnowledge(),
          time: ExactTime(facts.calendar, '${coordinate + BigInt.one}'),
        ),
        validity: InstantValidity(ExactTime(facts.calendar, '$coordinate')),
      ),
    );
    expectOutcome(rows, EvidenceOutcome.refuted);
  });

  test('receipt needs an actual holder rather than intended delivery', () {
    final rows = fixture();
    edit(rows, 9, {'actualRecipients': CanonicalArray([])});
    expectOutcome(
      rows,
      EvidenceOutcome.notEstablished,
      repair: 'actual recipient',
    );
    edit(rows, 9, {
      'actualRecipients': CanonicalArray([facts.ref(81).toCanonical()]),
    });
    expectOutcome(rows, EvidenceOutcome.refuted, repair: 'holder');
  });

  test(
    'receipt needs an explicit exact interpretation in the message content',
    () {
      final rows = fixture();
      put(
        rows,
        6,
        attitude(
          declared: acquisition(
            basis: CommunicationKnowledge(communication: facts.ref(9)),
          ),
        ),
      );
      expectOutcome(
        rows,
        EvidenceOutcome.notEstablished,
        repair: 'interpretation',
      );
      put(
        rows,
        6,
        attitude(
          declared: acquisition(
            basis: CommunicationKnowledge(
              communication: facts.ref(9),
              interpretation: facts.ref(1),
            ),
          ),
        ),
      );
      expectOutcome(rows, EvidenceOutcome.refuted, repair: 'interpretation');
      put(rows, 6, attitude());
      edit(rows, 9, {'content': CanonicalArray([])});
      expectOutcome(rows, EvidenceOutcome.refuted, repair: 'interpretation');
    },
  );

  test('distortion and missing or late receipt cannot establish knowledge', () {
    final rows = fixture();
    edit(rows, 9, {'distorted': const CanonicalBool(true)});
    expectOutcome(rows, EvidenceOutcome.notEstablished, repair: 'Distorted');
    put(rows, 9, message());
    edit(rows, 9, {'receivedAt': const CanonicalNull()});
    expectOutcome(rows, EvidenceOutcome.notEstablished, repair: 'Receipt');
    edit(rows, 9, {
      'receivedAt': ExactTime(facts.calendar, '13').encode(canonical: false),
    });
    expectOutcome(rows, EvidenceOutcome.refuted, repair: 'Receipt');
    edit(rows, 9, {
      'receivedAt': ExactTime(facts.calendar, '12').encode(canonical: false),
    });
    expectOutcome(rows, EvidenceOutcome.supported);
  });

  test('authored transmission contract is required and corrections reassess knowledge', () {
    final rows = fixture();
    expectOutcome(rows, EvidenceOutcome.supported);
    put(rows, 8, channels.policy(maximum: '0'));
    expectOutcome(rows, EvidenceOutcome.refuted, repair: 'chronology');
    put(rows, 8, channels.policy(channel: 'mail'));
    expectOutcome(rows, EvidenceOutcome.notEstablished, repair: 'chronology');
    rows.removeWhere((r) => r.identity.recordId == facts.id(8));
    expectOutcome(rows, EvidenceOutcome.notEstablished, repair: 'chronology');
  });

  test(
    'authored reverse channels can support acquisition in declared order',
    () {
      final rows = fixture();
      edit(rows, 9, {
        'sentAt': ExactTime(facts.calendar, '13').encode(canonical: false),
      });
      expectOutcome(rows, EvidenceOutcome.refuted);
      put(
        rows,
        8,
        channels.policy(forward: false, minimum: '-2', maximum: '-2'),
      );
      expectOutcome(rows, EvidenceOutcome.supported);
    },
  );

  test('truth is evaluated at acquisition rather than query time', () {
    final rows = fixture();
    edit(rows, 3, {'validity': facts.interval(13, 20).toWire()});
    expectOutcome(
      rows,
      EvidenceOutcome.notEstablished,
      repair: 'supporting truth',
    );
    edit(rows, 3, {
      'validity': facts.interval(10, 20).toWire(),
      'polarity': Polarity.refutation.toWire(),
    });
    expectOutcome(rows, EvidenceOutcome.refuted);
    rows.add(facts.record(10, facts.assertion().payload));
    expectOutcome(rows, EvidenceOutcome.refuted);
    expect(
      assess(rows).single.evidence,
      containsAll([facts.version(3), facts.version(10)]),
    );
  });

  test(
    'omitted world does not use a convenient world for supporting truth',
    () {
      final rows = fixture();
      rows.add(facts.record(11, WorldRecord(selector: 'Earth')));
      final scope = Scope(
        context: facts.ref(99),
        applicability: WorldsApplicability([
          WorldId.parse('wld_${facts.suffix(11)}'),
        ]),
      );
      edit(rows, 3, {'scope': scope.toWire()});
      expectOutcome(rows, EvidenceOutcome.notEstablished);
      put(rows, 6, attitude(declared: acquisition(world: facts.ref(11))));
      expectOutcome(rows, EvidenceOutcome.supported);
      expect(assess(rows).single.evidence, contains(facts.version(11)));
      put(rows, 6, attitude(declared: acquisition(world: facts.ref(80))));
      expectOutcome(rows, EvidenceOutcome.notEstablished);
    },
  );

  test('truth context, missing dependencies and unsupported quantification stay explicit', () {
    final rows = fixture();
    put(rows, 6, attitude(declared: acquisition(context: facts.ref(98))));
    expectOutcome(rows, EvidenceOutcome.refuted, repair: 'truth context');
    put(rows, 6, attitude());
    edit(rows, 2, {'quantification': CanonicalString('universal')});
    expectOutcome(rows, EvidenceOutcome.notEstablished, repair: 'particular');
    edit(rows, 2, {'quantification': CanonicalString('particular')});
    rows.removeWhere((r) => r.identity.recordId == facts.id(99));
    expectOutcome(rows, EvidenceOutcome.notEstablished);
  });

  test(
    'justified relational knowledge preserves authored role participants',
    () {
      final rows = fixture();
      put(
        rows,
        1,
        RelationRecord(
          namespace: 'test',
          key: 'related',
          labels: {},
          roles: [
            RoleDefinition(
              name: 'target',
              multiplicity: Multiplicity.single,
              ordered: false,
            ),
          ],
        ),
      );
      edit(rows, 2, {
        'value': const CanonicalNull(),
        'roles': CanonicalArray([
          PropositionRole('target', facts.ref(80)).toWire(),
        ]),
      });
      expectOutcome(rows, EvidenceOutcome.supported);
    },
  );

  test('every matching policy is assessed independently', () {
    final rows = fixture();
    rows.add(facts.record(12, policy(mode: KnowledgeMode.authorEstablished)));
    final findings = assess(rows);
    expect(findings.map((f) => f.ruleId), [facts.id(7), facts.id(12)]);
    expect(findings.map((f) => f.outcome), [
      EvidenceOutcome.supported,
      EvidenceOutcome.refuted,
    ]);
  });

  test('foreign references cannot retrieve same-id local evidence', () {
    final rows = fixture();
    final foreign = RecordRef(
      universe: UniverseId.parse('unv_${facts.suffix(2)}'),
      record: facts.id(9),
    );
    put(
      rows,
      6,
      attitude(
        declared: acquisition(
          basis: CommunicationKnowledge(
            communication: foreign,
            interpretation: facts.ref(2),
          ),
        ),
      ),
    );
    expectOutcome(rows, EvidenceOutcome.notEstablished);
    expect(assess(rows).single.evidence, isNot(contains(facts.version(9))));
    // Omitted namespace is allowed for lookup, preserving the authored receipt.
    put(
      rows,
      6,
      attitude(
        declared: acquisition(
          basis: CommunicationKnowledge(
            communication: RecordRef(record: facts.id(9)),
            interpretation: facts.ref(2),
          ),
        ),
      ),
    );
    expectOutcome(rows, EvidenceOutcome.supported);
  });

  test(
    'context and recipient matching retain full authored reference identity',
    () {
      final rows = fixture();
      put(
        rows,
        6,
        attitude(
          declared: acquisition(context: RecordRef(record: facts.id(99))),
        ),
      );
      expectOutcome(rows, EvidenceOutcome.refuted, repair: 'truth context');
      put(rows, 6, attitude());
      edit(rows, 9, {
        'actualRecipients': CanonicalArray([
          RecordRef(record: facts.id(80)).toCanonical(),
        ]),
      });
      expectOutcome(rows, EvidenceOutcome.refuted, repair: 'holder');
    },
  );

  test(
    'missing or wrong kinds do not resolve required factual dependencies',
    () {
      for (final n in [1, 2, 9, 99]) {
        final rows = fixture();
        rows.removeWhere((r) => r.identity.recordId == facts.id(n));
        expectOutcome(rows, EvidenceOutcome.notEstablished);
      }
      for (final n in [1, 9, 99]) {
        final rows = fixture();
        put(rows, n, operations.entity());
        expectOutcome(rows, EvidenceOutcome.notEstablished);
      }
    },
  );

  test(
    'policy admission rejects capability without contract and bypass shapes',
    () {
      final rule = policy();
      validateKnowledgeRule(rule);
      for (final change in <Map<String, CanonicalValue>>[
        {'knowledgePolicy': const CanonicalNull()},
        {'executable': const CanonicalBool(false)},
        {'expression': const LiteralExpr(false).encode(canonical: false)},
        {'kind': CanonicalString('law')},
        for (final p in [
          'advisory',
          'record_finding',
          'block_unless_exception',
        ])
          {'commitPolicy': CanonicalString(p)},
        {'channelChronology': channels.policy().channelChronology!.toWire()},
        {
          'knowledgeBoundary': KnowledgeBoundary(
            holder: facts.ref(80),
            proposition: facts.ref(2),
            context: facts.ref(99),
          ).toWire(),
        },
        {'capabilities': CanonicalArray([])},
        {
          'capabilities': CanonicalArray([
            CanonicalString(knowledgeAcquisitionCapability),
            CanonicalString('other'),
          ]),
        },
        {
          'targetPredicates': CanonicalArray([CanonicalString('test:open')]),
        },
        {
          'subjectTypes': CanonicalArray([CanonicalString(facts.id(80).value)]),
        },
        {'validity': InstantValidity(ExactTime(facts.calendar, '12')).toWire()},
        {
          'applicability': WorldsApplicability([
            WorldId.parse('wld_${facts.suffix(11)}'),
          ]).encode(canonical: false),
        },
      ]) {
        expect(
          () => validateKnowledgeRule(operations.patch(rule, change)),
          throwsA(isA<InvalidArgumentError>()),
        );
      }
      validateKnowledgeRule(
        operations.patch(rule, {
          'knowledgePolicy': const CanonicalNull(),
          'capabilities': CanonicalArray([]),
        }),
      );
    },
  );
}
