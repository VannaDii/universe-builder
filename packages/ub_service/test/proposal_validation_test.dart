import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/proposal_validation.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as p;
import 'rule_checks_test.dart' as frames;
import 'source_verification_test.dart' as sources;

final editionRef = VersionRef(
  universe: f.u,
  record: f.id(40),
  version: f.ver(40),
);
RecordVersion edition({WorkBinding? binding}) => f.row(
  40,
  WorkVersionRecord(
    work: f.ref(50),
    versionLabel: 'first',
    binding: binding ?? BoundWork(frames.frame().continuity, f.revision),
  ),
);

Future<void> disclosures(
  List<RecordVersion> rows,
  List<RecordVersion> canon, {
  List<RecordRef>? selected,
  VersionRef? editionReference,
}) => checkSceneDisclosures(
  edition: editionReference ?? editionRef,
  disclosures: selected ?? [f.ref(10)],
  rows: rows,
  readCanon: (continuity, revision) {
    expect(continuity, frames.frame().continuity);
    expect(revision, f.revision);
    return canon;
  },
);

void main() {
  test('disclosures require the exact edition and an unchanged transitive dependency closure', () async {
    final entity = f.row(10, f.entity(classification: f.id(11))),
        type = f.row(11, f.type(11, parent: 12)),
        parent = f.row(12, f.type(12));
    final canon = [entity, type, parent], rows = [edition(), ...canon];
    await disclosures(rows, canon);
    final changed = RecordVersion.build(
      recordVersionId: f.ver(13),
      identity: parent.identity,
      payload: parent.payload,
    );
    await expectLater(
      disclosures([edition(), entity, type, changed], canon),
      throwsFormatException,
    );
    await expectLater(
      disclosures([edition(), entity, type], canon),
      throwsFormatException,
    );
    await expectLater(
      disclosures(
        rows,
        canon,
        editionReference: VersionRef(
          universe: f.u,
          record: f.id(40),
          version: f.ver(41),
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      disclosures([f.row(40, f.entity()), ...canon], canon),
      throwsFormatException,
    );
  });

  test('empty disclosures perform no edition lookup; unbound or segmented editions cannot disclose', () async {
    await checkSceneDisclosures(
      edition: editionRef,
      disclosures: [],
      rows: [],
      readCanon: (_, _) => throw StateError('Unexpected read'),
    );
    for (final binding in [const UnboundWork(), SegmentedWork([])]) {
      await expectLater(
        disclosures(
          [edition(binding: binding), f.row(10, f.entity())],
          [f.row(10, f.entity())],
        ),
        throwsFormatException,
      );
    }
  });

  test('dependency cycles terminate without turning this check into structural admission', () async {
    final canon = [
      f.row(10, f.entity(classification: f.id(11))),
      f.row(11, f.type(11, parent: 12)),
      f.row(12, f.type(12, parent: 11)),
    ];
    await disclosures([edition(), ...canon], canon);
  });

  test('commit input retains exact frozen bindings and performs no reads for non-scenes', () async {
    final stored = p.prepare();
    final input = await proposalCommitInput(
      stored: stored,
      universe: f.u,
      principal: p.actor,
      idempotencyKey: 'exact-key',
      readCanon: (_, _) => throw StateError('Unexpected scene read'),
    );
    expect(input.universe, f.u);
    expect(input.principal.value, p.actor.value.replaceFirst('prf_', 'prn_'));
    expect(input.expectedHead, stored.proposal.baseFrame.revision);
    expect(input.decision, stored.proposal.digest);
    expect(input.reason, stored.proposal.rationale);
    expect(input.idempotencyKey, 'exact-key');
    expect(
      input.changes.single.next!.versionId,
      stored.changes.single.next!.versionId,
    );
  });

  test('scene input checks the complete proposed membership, including changed and removed dependencies', () async {
    final root = f.row(10, f.entity(classification: f.id(11))),
        type = f.row(11, f.type(11));
    final base = [edition(), root, type];
    final scene = SceneRecord(
      workVersion: editionRef,
      sceneId: 'Opening',
      disclosedRecords: [f.ref(10)],
      depictedEvents: [],
      worldAssociations: [],
    );
    final initial = p.prepare();
    StoredProposal withChanges(List<Assignment> changes) => StoredProposal(
      proposal: initial.proposal,
      owner: initial.owner,
      authorOrigin: initial.authorOrigin,
      footprint: initial.footprint,
      changes: changes,
    );
    final change = Assignment(
      recordId: f.id(60),
      next: StoredVersion(
        versionId: f.ver(60),
        identity: f.row(60, scene).identity,
        payload: scene.toWire(),
        digest: f.row(60, scene).payloadDigest,
      ),
    );
    Future<CommitInput> input(List<Assignment> changes) => proposalCommitInput(
      stored: withChanges(changes),
      universe: f.u,
      principal: p.actor,
      idempotencyKey: 'scene',
      readCanon: (_, _) => base,
    );
    await input([change]);
    await expectLater(
      input([change, Assignment(recordId: f.id(11), expected: f.ver(11))]),
      throwsFormatException,
    );
    final changed = RecordVersion.build(
      recordVersionId: f.ver(12),
      identity: type.identity,
      payload: type.payload,
    );
    await expectLater(
      input([
        change,
        Assignment(
          recordId: f.id(11),
          expected: f.ver(11),
          next: StoredVersion(
            versionId: changed.recordVersionId,
            identity: changed.identity,
            payload: changed.payload.toWire(),
            digest: changed.payloadDigest,
          ),
        ),
      ]),
      throwsFormatException,
    );
  });

  test(
    'restricted checks do not preview or read immutable/source evidence',
    () async {
      final stored = p.prepare();
      final checked = await checkProposalCandidate(
        stored: stored,
        universe: f.u,
        principal: p.actor,
        approvalAuthor: p.actor,
        scope: {},
        preview: (_) => throw StateError('Unexpected preview'),
        readCanon: (_, _) => throw StateError('Unexpected canon read'),
        readWorkflow: (_) => throw StateError('Unexpected source read'),
        readVersion: (_) => throw StateError('Unexpected adoption read'),
      );
      expect(checked.admissible, isFalse);
      expect(checked.validation.coverage, Coverage.restricted);
      expect(checked.validation.findings, isEmpty);
      expect(checked.report, isNull);
      expect(checked.capture, isNull);
      expect(checked.validation.unsupportedCapabilities, [
        'An author must validate this proposal against the complete universe.',
      ]);
    },
  );
  test(
    'immutable adoption is checked before preview and source reads',
    () async {
      final source = f.row(10, f.entity());
      final stored = p.prepare(
        request: p.create(
          operations: [AdoptRecordVersionOperation(source: source)],
        ),
      );
      await expectLater(
        checkProposalCandidate(
          stored: stored,
          universe: f.u,
          principal: p.actor,
          approvalAuthor: p.actor,
          scope: null,
          preview: (_) => throw StateError('Unexpected preview'),
          readCanon: (_, _) => throw StateError('Unexpected canon read'),
          readWorkflow: (_) => throw StateError('Unexpected source read'),
          readVersion: (_) => f.row(11, f.entity()),
        ),
        f.fails('existing immutable version', field: 'adoption'),
      );
    },
  );

  test('candidate sources are verified before factual evaluation or base retrieval', () async {
    final stored = p.prepare();
    await expectLater(
      checkProposalCandidate(
        stored: stored,
        universe: f.u,
        principal: p.actor,
        approvalAuthor: p.actor,
        scope: null,
        preview: (_) => [f.row(2, sources.source())],
        readCanon: (_, _) => throw StateError('Unexpected base read'),
        readWorkflow: (_) => null,
        readVersion: (_) => throw StateError('Unexpected version read'),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test(
    'all-validities frame admission precedes even a restricted check',
    () async {
      final initial = p.prepare();
      final frame = frames.frame(
        time: AtFrameTime(ExactTime(frames.calendar, '12')),
      );
      final proposal = Proposal.fromWire(
        CanonicalObject([
          for (final entry in initial.proposal.toWire().fields)
            entry.key == 'base_frame'
                ? MapEntry('base_frame', frame.toWire())
                : entry,
        ]),
      );
      final stored = StoredProposal(
        proposal: proposal,
        owner: initial.owner,
        authorOrigin: initial.authorOrigin,
        changes: initial.changes,
        footprint: initial.footprint,
      );
      await expectLater(
        checkProposalCandidate(
          stored: stored,
          universe: f.u,
          principal: p.actor,
          approvalAuthor: p.actor,
          scope: {},
          preview: (_) => throw StateError('Unexpected preview'),
          readCanon: (_, _) => throw StateError('Unexpected canon read'),
          readWorkflow: (_) => throw StateError('Unexpected source read'),
          readVersion: (_) => throw StateError('Unexpected version read'),
        ),
        throwsA(isA<UnsupportedSemanticsError>()),
      );
    },
  );
}
