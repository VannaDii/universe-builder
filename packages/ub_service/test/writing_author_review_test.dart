import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'rule_checks_test.dart' as facts;
import 'writing_binding_test.dart' as binding;
import 'writing_contexts_test.dart' as contexts;
import 'writing_knowledge_corrections_test.dart' as knowledge;
import 'writing_relations_test.dart' as relations;
import 'writing_units_test.dart' as units;
import 'writing_powers_test.dart' as powers;
import 'consequence_execution_test.dart' as consequences;
import 'knowledge_checks_test.dart' as policies;
import 'communication_checks_test.dart' as channels;
import 'knowledge_boundaries_test.dart' as boundaries;

// Typed frozen review fixture; projection does not infer or compile these rows.
StoredProposal frozen(
  List<RecordVersion> after, {
  List<DomainOperation> operations = const [],
  String rationale = 'Review fixture',
}) {
  final seed = proposals.prepare();
  final p = seed.proposal;
  return StoredProposal(
    proposal: Proposal(
      baseFrame: p.baseFrame,
      proposalId: p.proposalId,
      version: p.version,
      digest: p.digest,
      submission: Submission.submitted,
      operations: operations,
      rationale: rationale,
      canonical: false,
      operationId: p.operationId,
      withdrawn: false,
    ),
    owner: seed.owner,
    authorOrigin: true,
    footprint: seed.footprint,
    changes: after.map(
      (r) => Assignment(
        recordId: r.identity.recordId,
        next: StoredVersion(
          versionId: r.recordVersionId,
          identity: r.identity,
          payload: r.payload.toWire(),
          digest: r.payloadDigest,
        ),
      ),
    ),
  );
}

List<String> summary(
  List<RecordVersion> after, {
  List<RecordVersion> before = const [],
  List<DomainOperation> operations = const [],
  String rationale = 'Review fixture',
}) => summarizeWritingAuthorReview(
  stored: frozen(after, operations: operations, rationale: rationale),
  originals: before,
);

void main() {
  test(
    'policy review states limits without implying truth or automatic absence',
    () {
      final lines = summary([
        f.row(100, policies.policy(mode: KnowledgeMode.authorEstablished)),
        f.row(101, channels.policy(minimum: '9007199254740993')),
        f.row(102, boundaries.rule()),
        f.row(103, facts.rule()),
        f.row(
          104,
          IssueDecisionRecord(
            fingerprints: [FindingFingerprint('a' * 64)],
            mode: IssueDecisionMode.accept,
            scope: 'resource:exact-claim',
            rationale: 'Explicit unexplained arrival',
            principal: PrincipalId.generate(),
          ),
        ),
      ]);
      expect(
        lines,
        contains(
          contains(
            'mode AuthorEstablished; no automatic understanding or objective truth',
          ),
        ),
      );
      expect(
        lines,
        contains(
          contains(
            'minimum delay Some("9007199254740993"); maximum delay None',
          ),
        ),
      );
      expect(
        lines,
        contains(
          contains(
            'no objective truth or automatic absence outside this period',
          ),
        ),
      );
      expect(lines, contains(startsWith('Author constraint declaration:')));
      expect(
        lines,
        contains(
          'Author creative acceptance: resource:exact-claim; reason Explicit unexplained arrival',
        ),
      );
    },
  );

  test('event withdrawal and item correction retain historical effects and possession distinctions', () {
    final base = [
      ...powers.rows(),
      f.row(
        5,
        consequences.action(
          const SetEffect(Polarity.support, IntegerValue('3')),
        ),
      ),
      f.row(6, consequences.event()),
      f.row(
        7,
        ItemPowerRecord(
          item: f.ref(1),
          holderPredicate: f.ref(3),
          powerPredicate: f.ref(4),
          value: const BooleanValue(true),
          scope: facts.scope,
          validity: const UnspecifiedValidity(),
        ),
      ),
    ];
    final replacement = f.patch<ItemPowerRecord>(
      base.last.payload as ItemPowerRecord,
      {'value': const BooleanValue(false).toWire()},
    );
    final lines = summary(
      [f.row(7, replacement)],
      before: base,
      operations: [
        ReviseItemPowerOperation(
          record: f.ref(7),
          expectedVersion: f.ver(7),
          replacement: replacement,
          rationale: 'Correct declared ability',
        ),
        WithdrawEventOperation(
          record: f.ref(6),
          expectedVersion: f.ver(6),
          rationale: 'Did not substantiate occurrence',
        ),
      ],
    );
    expect(
      lines.first,
      allOf(
        startsWith('Correct item grant:'),
        contains('original value true'),
        contains('proposed value false'),
      ),
    );
    expect(
      lines[1],
      contains('generated effects removed; no non-occurrence asserted'),
    );
    expect(
      lines.last,
      contains('Ownership relations do not establish possession'),
    );
    expect(
      summary([base[base.length - 2]], before: base).single,
      contains('no direct event anchor link'),
    );
  });

  test('review uses frozen labels and preserves exact numeric and relationship claims', () {
    final entity = f.row(
      80,
      binding.entity(labels: {'en': 'Iris', 'fr': 'Irène'}),
    );
    final property = f.row(
      1,
      powers.property('stock', const SimpleValueShape(SimpleShapeKind.integer)),
    );
    final proposition = f.row(
      2,
      f.patch<PropositionRecord>(
        facts
                .fixture()
                .singleWhere((r) => r.payload is PropositionRecord)
                .payload
            as PropositionRecord,
        {'value': const IntegerValue('9007199254740993').toWire()},
      ),
    );
    final assertion = facts.assertion();
    final lines = summary([entity, property, proposition, assertion]);
    expect(lines, contains(startsWith('Proposed identity: Iris;')));
    expect(
      lines,
      contains(
        allOf(
          contains('Iris — stock = 9007199254740993'),
          contains('mode Instance; polarity Support'),
        ),
      ),
    );
    final relationRows = relations.fixture();
    final relationLines = summary(relationRows);
    expect(
      relationLines,
      contains(
        allOf(
          startsWith('Proposed fact:'),
          contains('participants'),
          contains('person'),
          contains('Lena'),
        ),
      ),
    );
    expect(
      relationLines,
      contains(startsWith('Author relationship declaration: knows;')),
    );
    expect(
      relationLines,
      contains(
        allOf(startsWith('Author relationship limit:'), contains('maximum 1')),
      ),
    );
  });

  test('historical factual edits stay explicit without duplicate proposed facts or opposites', () {
    final before = [...contexts.rows(), ...facts.fixture().take(3)];
    final old = before.singleWhere((r) => r.payload is AssertionRecord);
    final oldAssertion = old.payload as AssertionRecord;
    final newClaim = f.row(
      20,
      f.patch<PropositionRecord>(
        facts
                .fixture()
                .singleWhere((r) => r.payload is PropositionRecord)
                .payload
            as PropositionRecord,
        {'value': const BooleanValue(false).toWire()},
      ),
    );
    final replacement = f.patch<AssertionRecord>(oldAssertion, {
      'proposition': f.ref(20).toCanonical(),
    });
    final changed = f.row(3, replacement);
    final correction = SupersedeAssertionOperation(
      record: f.ref(3),
      expectedVersion: f.ver(3),
      replacement: replacement,
      rationale: 'Correct recollection',
    );
    final corrected = summary(
      [newClaim, changed],
      before: before,
      operations: [correction],
    );
    expect(
      corrected.single,
      allOf(
        startsWith('Correct earlier fact:'),
        contains('true'),
        contains('false'),
        contains('Correct recollection'),
      ),
    );
    final ending = summary(
      [changed],
      before: before,
      operations: [
        EndAssertionAtOperation(
          record: f.ref(3),
          expectedVersion: f.ver(3),
          at: ExactTime(f.cal, '9007199254740993'),
          basis: const ImportedClaimBasis(),
        ),
      ],
      rationale:
          'Other text\nProposed fact ending reason: Later corrected memory',
    );
    expect(
      ending,
      contains(
        allOf(
          startsWith('End fact duration:'),
          contains('9007199254740993'),
          contains('earlier support remains'),
        ),
      ),
    );
    expect(
      ending,
      contains('Proposed fact ending reason: Later corrected memory'),
    );
    final withdrawn = summary(
      [],
      before: before,
      operations: [
        RetractAssertionOperation(
          record: f.ref(3),
          expectedVersion: f.ver(3),
          rationale: 'Cannot substantiate memory',
        ),
      ],
    );
    expect(withdrawn.single, contains('no opposite claim asserted'));
  });

  test('message and knowledge corrections show acquisition limits and original versus proposed claim', () {
    final before = knowledge.rows();
    final replacementMessage = knowledge.message(
      received: ExactTime(knowledge.otherCalendar, '9007199254740993'),
    );
    final oldAttitude =
        before.singleWhere((r) => r.payload is EpistemicAttitudeRecord).payload
            as EpistemicAttitudeRecord;
    final claim = f.row(
      20,
      f.patch<PropositionRecord>(
        facts
                .fixture()
                .singleWhere((r) => r.payload is PropositionRecord)
                .payload
            as PropositionRecord,
        {'value': const BooleanValue(false).toWire()},
      ),
    );
    final replacement = f.patch<EpistemicAttitudeRecord>(oldAttitude, {
      'proposition': f.ref(20).toCanonical(),
    });
    final lines = summary(
      [claim, f.row(40, replacementMessage), f.row(50, replacement)],
      before: before,
      operations: [
        ReviseCommunicationOperation(
          record: f.ref(40),
          expectedVersion: f.ver(40),
          replacement: replacementMessage,
          rationale: 'Correct receipt',
        ),
        ReviseInterpretationOperation(
          record: f.ref(50),
          expectedVersion: f.ver(50),
          rationale: 'Unsupported interpretation',
        ),
        ReviseAttitudeOperation(
          record: f.ref(50),
          expectedVersion: f.ver(50),
          replacement: replacement,
          rationale: 'Correct belief',
        ),
      ],
    );
    expect(
      lines.first,
      allOf(
        startsWith('Historical message correction:'),
        contains('9007199254740993'),
        contains('Dependent knowledge/actions are rechecked'),
      ),
    );
    expect(
      lines[1],
      contains('interpretation removed; knowledge may become unsupported'),
    );
    expect(
      lines[2],
      allOf(
        contains('original claim Mara.open = true'),
        contains('proposed claim Mara.open = false'),
        contains('acquisition and basis retained'),
      ),
    );
    expect(lines, contains(contains('Content alone is not objective truth')));
    final decision = f.patch<EpistemicAttitudeRecord>(oldAttitude, {
      'basis': const AuthorDecisionBasis('Explicit memoir decision').toWire(),
    });
    expect(
      summary([f.row(50, decision)], before: before),
      contains(
        contains('attributed knowledge only, no objective fact asserted'),
      ),
    );
  });

  test('exact source byte counts use UTF-8 and definitions retain declared contract limits', () {
    final stage = stageWritingSource(
      universe: f.u,
      author: proposals.actor,
      label: 'Memoir',
      text: 'é😀\r\n',
      importTime: '2026-10-12T00:00:00Z',
    );
    final attached = attachWritingSource(
      universe: f.u,
      context: facts.frame().context,
      operations: [],
      sourceOperations: stage.operations,
      sourceVersion: stage.sourceVersion,
      text: 'é😀\r\n',
      digest: stage.digest,
      byteSize: stage.byteSize,
    );
    final compiled = proposals.prepare(
      request: proposals.create(operations: attached.operations),
      versions: attached.versions,
    );
    final lines = summarizeWritingAuthorReview(stored: compiled, originals: []);
    expect(
      lines.single,
      'Exact author source: 8 UTF-8 bytes; digest ${stage.digest}',
    );
    final declarations = summary([
      f.row(30, units.unit()),
      f.row(
        31,
        consequences.action(
          const SetEffect(Polarity.support, IntegerValue('3')),
        ),
      ),
      ...powers.rows(),
      f.row(
        33,
        ItemPowerRecord(
          item: f.ref(1),
          holderPredicate: f.ref(3),
          powerPredicate: f.ref(4),
          value: const BooleanValue(true),
          scope: facts.scope,
          validity: const UnspecifiedValidity(),
        ),
      ),
      f.row(
        34,
        CompletenessRecord(
          subject: f.ref(1),
          predicate: 'test:owners',
          members: [f.ref(2)],
          completeness: const ObjectiveCompleteness(),
          scope: facts.scope,
          validity: const UnspecifiedValidity(),
        ),
      ),
    ]);
    expect(declarations, contains(contains('no conversion declared')));
    expect(declarations, contains(startsWith('Author action declaration:')));
    expect(
      declarations,
      contains(contains('Ownership relations do not establish possession')),
    );
    expect(
      declarations,
      contains(allOf(startsWith('Author exhaustive set:'), contains('Mara'))),
    );
  });
}
