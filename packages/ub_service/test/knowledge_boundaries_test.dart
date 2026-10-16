import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/knowledge_boundaries.dart';

import 'operation_compilation_test.dart' as f;

final cal = CalendarId.parse('cal_${f.suffix(9)}');
Validity interval(String a, String b) =>
    CalendarIntervalValidity(cal, ExactBound(a), ExactBound(b));
RuleRecord rule({Applicability? scope, Validity? validity}) => RuleRecord(
  namespace: 'test',
  key: 'absent',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability:
      scope ?? WorldsApplicability([WorldId.parse('wld_${f.suffix(7)}')]),
  targetPredicates: [],
  expression: const LiteralExpr(true),
  capabilities: [knowledgeBoundaryCapability],
  executable: true,
  validity: validity ?? interval('10', '18'),
  knowledgeBoundary: KnowledgeBoundary(
    holder: f.ref(6),
    proposition: f.ref(1),
    context: f.ref(9),
  ),
);
KnowledgeAcquisition acquisition({RecordRef? world, RecordRef? context}) =>
    KnowledgeAcquisition(
      truthContext: context ?? f.ref(9),
      time: ExactTime(cal, '0'),
      world: world,
      basis: const AuthorEstablishedKnowledge(),
    );
PropositionRecord prop(
  DomainValue? value, {
  List<PropositionRole> roles = const [],
  RecordRef? predicate,
}) => PropositionRecord(
  predicate: predicate ?? f.ref(5),
  subject: f.ref(6),
  context: f.ref(9),
  value: value,
  roles: roles,
  quantification: Quantification.particular,
);
EpistemicAttitudeRecord attitude({
  KnowledgeAcquisition? receipt,
  bool unqualified = false,
  Validity? validity,
}) => EpistemicAttitudeRecord(
  holder: f.ref(6),
  proposition: f.ref(2),
  attitude: EpistemicAttitudeKind.knows,
  validity: validity ?? interval('0', '30'),
  basis: const AuthorDecisionBasis('explicit decision'),
  acquisition: unqualified ? null : receipt ?? acquisition(),
);
List<RecordVersion> fixture() => [
  f.row(1, prop(DecimalValue('1.0'))),
  f.row(2, prop(IntegerValue('1'))),
  f.row(3, rule()),
  f.row(4, attitude()),
  f.row(
    5,
    PropertyRecord(
      namespace: 'test',
      key: 'count',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.integer),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  f.row(6, f.entity()),
  f.row(7, WorldRecord(selector: 'World A')),
  f.row(
    9,
    RepresentedContextRecord(
      universe: f.u,
      kind: const ObjectiveContext(),
      labels: {},
    ),
  ),
];
RecordVersion get(List<RecordVersion> rows, int n) =>
    rows.firstWhere((r) => r.identity.recordId == f.id(n));
void put(List<RecordVersion> rows, int n, RecordPayload p) =>
    rows[rows.indexOf(get(rows, n))] = f.row(n, p);
void edit(
  List<RecordVersion> rows,
  int n,
  Map<String, CanonicalValue> changes,
) => put(rows, n, f.patch(get(rows, n).payload, changes));
List<Finding> assess(List<RecordVersion> rows) =>
    assessKnowledgeBoundaries(rows);

void main() {
  test(
    'overlapping author-established knowledge cannot bypass explicit absence',
    () {
      final rows = fixture();
      final finding = assess(rows).single;
      expect(finding.outcome, EvidenceOutcome.refuted);
      expect(finding.coverage, Coverage.complete);
      expect(finding.records, [f.ref(6), f.ref(1)]);
      expect(finding.ruleId, f.id(3));
      expect(finding.evidence, [f.ver(3), f.ver(4)]);
      expect(finding.fingerprint, FindingFingerprint(''));
      put(rows, 4, attitude(validity: interval('18', '30')));
      expect(assess(rows), isEmpty);
      put(rows, 4, attitude(receipt: acquisition(world: f.ref(8))));
      expect(assess(rows), isEmpty);
    },
  );
  test('missing knowing attitudes do not prove absence or generate a pass', () {
    final rows = fixture()..removeWhere((r) => r.identity.recordId == f.id(4));
    expect(assess(rows), isEmpty);
    for (final kind in ['believes', 'suspects', 'rejects', 'remembers']) {
      final rows = fixture();
      edit(rows, 4, {'attitude': CanonicalString(kind)});
      expect(assess(rows), isEmpty);
    }
  });
  test('holder context and acquisition truth context must match exactly', () {
    for (final change in <Map<String, CanonicalValue>>[
      {'holder': f.ref(8).toCanonical()},
      {'holder': RecordRef(record: f.id(6)).toCanonical()},
    ]) {
      final rows = fixture();
      edit(rows, 4, change);
      expect(assess(rows), isEmpty);
    }
    final rows = fixture();
    edit(rows, 2, {'context': f.ref(8).toCanonical()});
    expect(assess(rows), isEmpty);
    put(rows, 2, prop(IntegerValue('1')));
    put(rows, 4, attitude(receipt: acquisition(context: f.ref(8))));
    expect(assess(rows), isEmpty);
  });
  test('unknown time and unqualified world scope remain unresolved', () {
    final rows = fixture();
    put(rows, 4, attitude(validity: const UnspecifiedValidity()));
    expect(assess(rows).single.outcome, EvidenceOutcome.notEstablished);
    expect(assess(rows).single.coverage, Coverage.unsupported);
    put(rows, 4, attitude(unqualified: true));
    expect(assess(rows).single.outcome, EvidenceOutcome.notEstablished);
    put(rows, 3, rule(scope: const UniverseApplicability()));
    expect(assess(rows).single.outcome, EvidenceOutcome.refuted);
    put(
      rows,
      4,
      attitude(
        validity: CalendarIntervalValidity(
          CalendarId.parse('cal_${f.suffix(8)}'),
          const ExactBound('0'),
          const ExactBound('30'),
        ),
      ),
    );
    expect(assess(rows).single.outcome, EvidenceOutcome.notEstablished);
  });
  test(
    'explicit acquisition without a world does not evade a world prohibition',
    () {
      final rows = fixture();
      put(rows, 4, attitude(receipt: acquisition()));
      expect(assess(rows).single.outcome, EvidenceOutcome.refuted);
      put(rows, 4, attitude(receipt: acquisition(world: f.ref(7))));
      expect(assess(rows).single.outcome, EvidenceOutcome.refuted);
      put(rows, 4, attitude(receipt: acquisition(world: f.ref(8))));
      expect(assess(rows), isEmpty);
    },
  );
  test('claim equality resolves same-name predicate definitions and reordered roles', () {
    final rows = fixture();
    rows.add(f.row(10, get(rows, 5).payload));
    final roles = [
      PropositionRole('a', f.ref(6)),
      PropositionRole('b', f.ref(7)),
    ];
    put(rows, 1, prop(null, roles: roles));
    put(
      rows,
      2,
      prop(null, roles: roles.reversed.toList(), predicate: f.ref(10)),
    );
    expect(assess(rows).single.outcome, EvidenceOutcome.refuted);
    edit(rows, 10, {'key': CanonicalString('different')});
    expect(assess(rows), isEmpty);
  });
  test('different values quantification and roles are separate claims', () {
    for (final change in <Map<String, CanonicalValue>>[
      {'value': IntegerValue('2').toWire()},
      {'value': const CanonicalNull()},
      {'quantification': CanonicalString('universal')},
      {
        'roles': CanonicalArray([
          PropositionRole('witness', f.ref(7)).toWire(),
        ]),
      },
    ]) {
      final rows = fixture();
      edit(rows, 2, change);
      expect(assess(rows), isEmpty);
    }
  });
  test('empty finite boundary has no overlapping period', () {
    final rows = fixture();
    put(rows, 3, rule(validity: interval('+0018', '18')));
    validateKnowledgeBoundaryRule(get(rows, 3).payload as RuleRecord, rows);
    expect(assess(rows), isEmpty);
  });
  test(
    'admission requires finite exact clock and explicit nonempty world scope',
    () {
      final rows = fixture();
      final valid = rule();
      validateKnowledgeBoundaryRule(valid, rows);
      for (final validity in [
        const UnspecifiedValidity(),
        interval('20', '10'),
        interval('10 ', '18'),
        interval('10', '${BigInt.one << 127}'),
        CalendarIntervalValidity(
          cal,
          const UnboundedBound(),
          const ExactBound('18'),
        ),
      ]) {
        expect(
          () => validateKnowledgeBoundaryRule(rule(validity: validity), rows),
          throwsA(isA<InvalidArgumentError>()),
        );
      }
      for (final scope in [
        const UnspecifiedApplicability(),
        const ConditionalApplicability(),
        WorldsApplicability([]),
      ]) {
        expect(
          () => validateKnowledgeBoundaryRule(rule(scope: scope), rows),
          throwsA(isA<InvalidArgumentError>()),
        );
      }
    },
  );
  test('admission rejects mixed capabilities weakened wrappers or missing declarations', () {
    final rows = fixture();
    final valid = rule();
    for (final change in <Map<String, CanonicalValue>>[
      {'knowledgeBoundary': const CanonicalNull()},
      {'executable': const CanonicalBool(false)},
      {'kind': CanonicalString('law')},
      {'commitPolicy': CanonicalString('advisory')},
      {'expression': const LiteralExpr(false).encode(canonical: false)},
      {'capabilities': CanonicalArray([])},
      {
        'capabilities': CanonicalArray([
          CanonicalString(knowledgeBoundaryCapability),
          CanonicalString('other'),
        ]),
      },
      {
        'targetPredicates': CanonicalArray([CanonicalString('test:count')]),
      },
      {
        'subjectTypes': CanonicalArray([CanonicalString(f.id(6).value)]),
      },
      {
        'knowledgePolicy': KnowledgePolicy(
          context: f.ref(9),
          mode: KnowledgeMode.justified,
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
        () => validateKnowledgeBoundaryRule(f.patch(valid, change), rows),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    validateKnowledgeBoundaryRule(
      f.patch(valid, {
        'knowledgeBoundary': const CanonicalNull(),
        'capabilities': CanonicalArray([]),
      }),
      rows,
    );
  });
  test(
    'admission resolves each world holder proposition and represented context',
    () {
      for (final n in [1, 6, 7, 9]) {
        final rows = fixture()
          ..removeWhere((r) => r.identity.recordId == f.id(n));
        expect(
          () => validateKnowledgeBoundaryRule(rule(), rows),
          throwsA(isA<InvalidArgumentError>()),
        );
      }
      final rows = fixture();
      edit(rows, 1, {'context': f.ref(8).toCanonical()});
      expect(
        () => validateKnowledgeBoundaryRule(rule(), rows),
        throwsA(isA<InvalidArgumentError>()),
      );
      final foreign = RecordRef(
        universe: UniverseId.parse('unv_${f.suffix(2)}'),
        record: f.id(6),
      );
      final wrong = f.patch(rule(), {
        'knowledgeBoundary': KnowledgeBoundary(
          holder: foreign,
          proposition: f.ref(1),
          context: f.ref(9),
        ).toWire(),
      });
      expect(
        () => validateKnowledgeBoundaryRule(wrong, fixture()),
        throwsFormatException,
      );
    },
  );
}
