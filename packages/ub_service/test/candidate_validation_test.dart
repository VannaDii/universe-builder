import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;
import 'package:ub_service/candidate_validation.dart';
import 'package:ub_service/src/universe_evidence_policy.dart';
import 'package:ub_service/proposal_authorization.dart';
import 'package:ub_service/resource_checks.dart';
import 'package:ub_store/ub_store.dart' show Assignment;

import 'boundary_checks_test.dart' as boundaries;
import 'cardinality_checks_test.dart' as cardinality;
import 'communication_checks_test.dart' as channels;
import 'operation_compilation_test.dart' as operations;
import 'event_compilation_test.dart' as events;
import 'knowledge_boundaries_test.dart' as knowledge;
import 'knowledge_checks_test.dart' as acquisitions;
import 'resource_checks_test.dart' as resources;
import 'rule_checks_test.dart' as f;
import 'structural_checks_test.dart' as structure;

final author = ProfileId.parse('prf_${f.suffix(1)}');
const digest = 'candidate-exact-digest';
List<RecordVersion> fixture() => [
  ...boundaries.fixture().take(4),
  structure.context(99),
];
final _fixtureRoot = initialUniversePolicyRecords(f.frame().universe, false);
List<RecordVersion> rootedFixture(List<RecordVersion> rows) =>
    rows.any(isUniversePolicyRecord) ? rows : [...rows, ..._fixtureRoot];
CandidateValidationResult check(
  List<RecordVersion> rows, {
  List<RecordVersion>? base,
  List<Assignment> changes = const [],
  Frame? frame,
  WriteFootprint? footprint,
  bool authorOrigin = true,
  ProfileId? approvalAuthor,
  void Function()? cancelled,
}) => evaluateCandidate(
  candidate: rootedFixture(rows),
  base: rootedFixture(base ?? rows),
  changes: changes,
  frame: frame ?? f.frame(),
  digest: digest,
  footprint: footprint ?? WriteFootprint(shared: true),
  authorOrigin: authorOrigin,
  approvalAuthor: approvalAuthor ?? author,
  checkCancelled: cancelled,
);
RuleRecord rule({
  CommitPolicy policy = CommitPolicy.alwaysBlock,
  Expr expression = const LiteralExpr(false),
  Applicability scope = const UniverseApplicability(),
  List<String> capabilities = const ['basic.v1'],
}) => RuleRecord(
  namespace: 'test',
  key: 'candidate-policy',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: policy,
  applicability: scope,
  targetPredicates: [],
  expression: expression,
  capabilities: capabilities,
  executable: true,
  validity: const UnspecifiedValidity(),
);
void main() {
  test(
    'valid candidate produces a bound execution without approval or writes',
    () {
      final rows = fixture();
      final first = check(rows), second = check(rows);
      expect(first.admissible, isTrue);
      expect(first.validation.coverage, protocol.Coverage.complete);
      expect(first.validation.findings, isEmpty);
      expect(first.validation.opposingEvidence, isEmpty);
      expect(first.validation.inputDigest, digest);
      expect(first.validation.evaluatorVersion, candidateEvaluatorVersion);
      expect(first.validation.operationId, isNull);
      expect(first.validation.runId, isNot(second.validation.runId));
      expect(
        protocol.Validation.fromWire(first.validation.toWire()).inputDigest,
        digest,
      );
      expect(rows.length, 5);
    },
  );
  test('blocking and advisory policies retain findings and exact bindings', () {
    final rows = [...fixture(), f.record(8, rule())];
    final blocked = check(rows);
    expect(blocked.admissible, isFalse);
    expect(blocked.validation.coverage, protocol.Coverage.complete);
    final finding = blocked.validation.findings.single;
    expect(finding.ruleId, f.id(8));
    expect(finding.outcome, protocol.EvidenceOutcome.refuted);
    expect(finding.fingerprint.value, hasLength(64));
    expect(
      finding.fingerprint,
      check(rows).validation.findings.single.fingerprint,
    );
    rows[5] = f.record(8, rule(policy: CommitPolicy.advisory));
    expect(check(rows).admissible, isTrue);
    expect(
      check(rows).validation.findings.single.outcome,
      protocol.EvidenceOutcome.refuted,
    );
    rows[5] = f.record(8, rule(capabilities: ['unimplemented.v1']));
    final partial = check(rows);
    expect(partial.admissible, isFalse);
    expect(partial.validation.coverage, protocol.Coverage.partial);
    expect(partial.validation.unsupportedCapabilities, [
      'rule:${f.id(8).value}',
    ]);
  });
  test(
    'disjoint ordinary rules are skipped but opposition uses all worlds',
    () {
      final a = WorldId.parse('wld_${f.suffix(20)}'),
          b = WorldId.parse('wld_${f.suffix(21)}');
      final rows = [
        ...fixture(),
        f.record(20, WorldRecord(selector: 'A')),
        f.record(21, WorldRecord(selector: 'B')),
        f.record(8, rule(scope: WorldsApplicability([b]))),
      ];
      final footprint = WriteFootprint(worlds: [a]);
      expect(check(rows, footprint: footprint).validation.findings, isEmpty);
      rows[7] = f.record(
        8,
        rule(
          scope: WorldsApplicability([b]),
          expression: NoOpposingEvidenceExpr(
            RecordOperand(f.ref(1)),
            'test:answer',
            RecordOperand(f.ref(99)),
          ),
          capabilities: ['opposing_evidence.v1'],
        ),
      );
      expect(
        check(rows, footprint: footprint).validation.findings,
        hasLength(1),
      );
    },
  );
  test(
    'boundary waiver preserves refutation and deletion checks old versions',
    () {
      final rows = [...boundaries.fixture(), structure.context(99)];
      final changes = [events.change(rows[3])];
      expect(check(rows, changes: changes).admissible, isFalse);
      rows.add(boundaries.exception(rows, 18));
      final waived = check(rows, changes: changes);
      expect(waived.admissible, isTrue);
      expect(
        waived.validation.findings.single.outcome,
        protocol.EvidenceOutcome.refuted,
      );
      expect(waived.validation.findings.single.records, [f.ref(5)]);
      final base = [...rows];
      rows.removeWhere((r) => r.identity.recordId == f.id(4));
      rows.removeWhere((r) => r.payload is ExceptionRecord);
      final removed = check(
        rows,
        base: base,
        changes: [Assignment(recordId: f.id(4), expected: f.version(4))],
      );
      expect(removed.admissible, isFalse);
    },
  );
  test('invalid unchanged exceptions reject the candidate with explicit gaps', () {
    final rows = [...boundaries.fixture(), structure.context(99)];
    rows.add(boundaries.exception(rows, 18, stale: true));
    final result = check(rows);
    expect(result.admissible, isFalse);
    expect(result.validation.coverage, protocol.Coverage.partial);
    expect(
      result.validation.unsupportedCapabilities.single,
      'exception:${f.id(7).value}: stale rule version, unsupported scope or missing acceptance',
    );
  });
  test('issue decisions require author origin and the installation author', () {
    final rows = [...boundaries.fixture(), structure.context(99)];
    final changes = [events.change(rows[5])];
    for (final options in [
      (false, author),
      (true, ProfileId.parse('prf_${f.suffix(2)}')),
    ]) {
      expect(
        () => check(
          rows,
          changes: changes,
          authorOrigin: options.$1,
          approvalAuthor: options.$2,
        ),
        throwsA(isA<protocol.PolicyDeniedError>()),
      );
    }
    expect(check(rows, changes: changes).admissible, isTrue);
    // A historical author decision is not reclassified as contributor authored.
    expect(check(rows, authorOrigin: false).admissible, isTrue);
  });
  test(
    'author-established knowledge cannot be manufactured by ordinary approval',
    () {
      final rows = fixture();
      rows.add(
        f.record(
          8,
          EpistemicAttitudeRecord(
            holder: f.ref(1),
            proposition: f.ref(3),
            attitude: EpistemicAttitudeKind.knows,
            validity: InstantValidity(ExactTime(f.calendar, '12')),
            basis: const AuthorDecisionBasis('Reviewed'),
            acquisition: KnowledgeAcquisition(
              truthContext: f.ref(99),
              time: ExactTime(f.calendar, '12'),
              basis: const AuthorEstablishedKnowledge(),
            ),
          ),
        ),
      );
      final changes = [events.change(rows.last)];
      rows.add(
        f.record(9, acquisitions.policy(mode: KnowledgeMode.authorEstablished)),
      );
      expect(
        () => check(rows, changes: changes, authorOrigin: false),
        throwsA(
          isA<protocol.PolicyDeniedError>().having(
            (e) => e.message,
            'message',
            contains('actual author-origin'),
          ),
        ),
      );
      expect(check(rows, changes: changes).admissible, isTrue);
      expect(check(rows, authorOrigin: false).admissible, isTrue);
    },
  );
  test(
    'asserted edits must use the proposal context including its namespace',
    () {
      final rows = fixture();
      rows.add(structure.context(98));
      final changed = boundaries.assertion(
        scope: Scope(
          context: f.ref(98),
          applicability: const UniverseApplicability(),
        ),
      );
      rows[3] = changed;
      expect(
        () => check(rows, changes: [events.change(changed)]),
        throwsA(
          isA<protocol.InvalidArgumentError>().having(
            (e) => e.field,
            'field',
            'operations',
          ),
        ),
      );
      // Full reference equality remains distinct from local record-ID equality.
      final local = boundaries.assertion(
        scope: Scope(
          context: RecordRef(record: f.id(99)),
          applicability: const UniverseApplicability(),
        ),
      );
      rows[3] = local;
      expect(
        () => check(rows, changes: [events.change(local)]),
        throwsA(isA<protocol.InvalidArgumentError>()),
      );
    },
  );
  test(
    'scalar conflicts and opposing diagnostics bind the complete candidate',
    () {
      final rows = fixture();
      rows.add(
        f.record(
          8,
          PropositionRecord(
            subject: f.ref(1),
            predicate: f.ref(2),
            value: const BooleanValue(false),
            context: f.ref(99),
            quantification: Quantification.particular,
          ),
        ),
      );
      rows.add(
        f.record(
          9,
          AssertionRecord(
            attributeMode: AttributeMode.instance,
            proposition: f.ref(8),
            polarity: Polarity.support,
            scope: f.scope,
            validity: f.interval(12, 18),
            persistence: PersistenceSemantics.explicitInterval,
            precision: Precision.exact,
            basis: const AuthorDecisionBasis('Conflict'),
          ),
        ),
      );
      final result = check(rows);
      expect(result.admissible, isFalse);
      final finding = result.validation.findings.single;
      expect(finding.outcome, protocol.EvidenceOutcome.conflicting);
      expect(finding.evidence, [f.version(4), f.version(9)]);
      expect(finding.records, [f.ref(4), f.ref(9)]);
      expect(result.validation.opposingEvidence, isEmpty);
      rows.add(
        f.record(
          10,
          AssertionRecord(
            attributeMode: AttributeMode.instance,
            proposition: f.ref(3),
            polarity: Polarity.refutation,
            scope: f.scope,
            validity: f.interval(12, 18),
            persistence: PersistenceSemantics.explicitInterval,
            precision: Precision.exact,
            basis: const AuthorDecisionBasis('Opposing evidence'),
          ),
        ),
      );
      expect(check(rows).validation.opposingEvidence, isNotEmpty);
    },
  );
  test('resource acceptance retains its authored fingerprint and unexplained arrival', () {
    final rows = [...resources.fixture(), structure.context(5)];
    final gap = assessResourceAccounting(rows, resources.frame).single;
    final result = check(rows, frame: resources.frame);
    expect(result.admissible, isFalse);
    final finding = result.validation.findings.firstWhere(
      (f) => f.message != null,
    );
    expect(finding.fingerprint, gap.fingerprint);
    expect(finding.records, [f.ref(12), f.ref(13)]);
    rows.add(f.record(14, resources.accept(gap)));
    final accepted = check(rows, frame: resources.frame);
    expect(accepted.admissible, isTrue);
    expect(
      accepted.validation.findings.firstWhere((f) => f.message != null).outcome,
      protocol.EvidenceOutcome.notEstablished,
    );
  });
  test('typed knowledge boundaries are assessed once after unchanged evidence edits', () {
    final rows = knowledge.fixture();
    // The fixture's equivalent decimal is changed to the property's integer shape.
    knowledge.edit(rows, 1, {'value': IntegerValue('1').toWire()});
    final result = check(rows);
    expect(result.admissible, isFalse);
    expect(result.validation.findings, hasLength(2));
    final boundaryFinding = result.validation.findings
        .where((f) => f.ruleId == knowledge.get(rows, 3).identity.recordId)
        .single;
    expect(result.validation.unsupportedCapabilities, [
      'knowledge.acquisition:${f.id(4).value}',
    ]);
    expect(boundaryFinding.outcome, protocol.EvidenceOutcome.refuted);
  });
  test('event prerequisites remain findings and historical undeclared effects remain gaps', () {
    final rows = fixture();
    rows.add(
      f.record(
        8,
        EventRecord(
          occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
          time: ExactTime(f.calendar, '11'),
          participants: [],
          labels: {},
          expansionVersion: rules.eventExpansionVersion,
          preconditions: [const LiteralExpr(false)],
        ),
      ),
    );
    final result = check(rows);
    expect(result.admissible, isFalse);
    expect(result.validation.findings.single.ruleId, f.id(8));
    expect(
      result.validation.findings.single.message,
      contains('prerequisite 1'),
    );
    expect(result.validation.coverage, protocol.Coverage.partial);
    expect(result.validation.unsupportedCapabilities, isNotEmpty);
  });
  test('communication coverage remains explicit and typed policies are not duplicated', () {
    final rows = [
      ...fixture(),
      f.record(10, operations.entity()),
      f.record(8, channels.policy()),
      f.record(
        9,
        CommunicationRecord(
          sender: f.ref(1),
          intendedRecipients: [f.ref(10)],
          actualRecipients: [],
          content: [f.ref(3)],
          channel: 'speech',
          sentAt: ExactTime(channels.cal, '10'),
          distorted: false,
        ),
      ),
    ];
    final result = check(rows);
    expect(result.admissible, isFalse);
    expect(result.validation.findings, hasLength(1));
    expect(result.validation.findings.single.ruleId, f.id(8));
    expect(result.validation.coverage, protocol.Coverage.partial);
    expect(result.validation.unsupportedCapabilities, [
      'communications.chronology:${f.id(8).value}',
    ]);
    expect(result.validation.findings.single.records, [f.ref(8), f.ref(9)]);
  });
  test('cardinality reassesses unchanged cross-instance participants once', () {
    final rows = [
      ...cardinality.base(),
      for (final n in [10, 11, 12]) f.record(n, operations.entity()),
      ...cardinality.fact(20, 11, cardinality.interval(0, 10)),
      ...cardinality.fact(30, 12, cardinality.interval(5, 15)),
    ];
    final result = check(rows);
    expect(result.admissible, isFalse);
    expect(result.validation.findings, hasLength(1));
    expect(result.validation.findings.single.ruleId, f.id(1));
    expect(
      result.validation.findings.single.outcome,
      protocol.EvidenceOutcome.refuted,
    );
    expect(result.validation.coverage, protocol.Coverage.complete);
  });
  test(
    'cancellation propagates at each phase without returning an execution',
    () {
      final rows = rootedFixture(fixture());
      final stopped = StateError('cancelled');
      for (final stopAt in [
        1,
        rows.length + 1,
        2 * rows.length + 1,
        3 * rows.length + 1,
      ]) {
        var calls = 0;
        expect(
          () => check(
            rows,
            cancelled: () {
              if (++calls == stopAt) throw stopped;
            },
          ),
          throwsA(same(stopped)),
        );
        expect(calls, stopAt);
      }
      var calls = 0;
      expect(check(rows, cancelled: () => calls++).admissible, isTrue);
      expect(calls, 3 * rows.length + 1);
    },
  );
}
