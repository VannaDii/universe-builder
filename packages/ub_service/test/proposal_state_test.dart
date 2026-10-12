import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/proposal_state.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as frames;

final actor = ProfileId.parse('prf_${f.suffix(1)}'),
    other = ProfileId.parse('prf_${f.suffix(2)}'),
    contextId = ContextId.parse('ctx_${f.suffix(1)}');
CreateProposalRequest create({
  List<DomainOperation>? operations,
}) => CreateProposalRequest(
  universe: Selector('Disposable universe'),
  contextId: contextId,
  operations:
      operations ??
      [CreateEntityOperation(clientRef: f.id(10).value, record: f.entity())],
  submission: Submission.draft,
  rationale: 'Author edit',
  idempotencyKey: 'create',
);
ReviseProposalRequest revise(StoredProposal previous) => ReviseProposalRequest(
  universe: Selector('Disposable universe'),
  contextId: contextId,
  proposalReference: previous.reference,
  operations: [
    CreateEntityOperation(clientRef: f.id(10).value, record: f.entity()),
  ],
  submission: Submission.submitted,
  rationale: 'Revised edit',
  idempotencyKey: 'revise',
);
WorkflowRequest transition(StoredProposal previous, {bool withdraw = false}) =>
    withdraw
    ? WithdrawProposalRequest(
        universe: Selector('Disposable universe'),
        contextId: contextId,
        proposalReference: previous.reference,
        idempotencyKey: 'withdraw',
      )
    : SubmitProposalRequest(
        universe: Selector('Disposable universe'),
        contextId: contextId,
        proposalReference: previous.reference,
        idempotencyKey: 'submit',
      );
StoredProposal prepare({
  WorkflowRequest? request,
  StoredProposal? previous,
  bool author = false,
  ProfileId? principal,
  Frame? frame,
  WorldId? focus,
  Map<RecordId, RecordVersionId> versions = const {},
  List<RecordVersion> base = const [],
}) => prepareProposal(
  request: request ?? create(),
  previous: previous,
  frame: frame ?? frames.frame(),
  base: base,
  principal: principal ?? actor,
  author: author,
  worldFocus: focus,
  versions: versions,
);
void access(
  StoredProposal p, {
  ProfileId? principal,
  bool author = false,
  Set<WorldId>? scope,
  ProposalRef? reference,
}) => authorizeStoredProposal(
  stored: p,
  reference: reference ?? p.reference,
  principal: principal ?? actor,
  author: author,
  scope: scope,
);
void main() {
  test('create freezes exact compiled versions and leaves the pinned base untouched', () {
    final base = [f.row(1, f.entity())],
        before = f.row(1, f.entity()).toWire().toText();
    final p = prepare(base: base, versions: {f.id(10): f.ver(20)});
    expect(p.owner, actor);
    expect(p.authorOrigin, isFalse);
    expect(p.proposal.version, BigInt.one);
    expect(p.proposal.submission, Submission.draft);
    expect(p.proposal.canonical, isFalse);
    expect(p.proposal.withdrawn, isFalse);
    expect(p.proposal.compiledChanges, isEmpty);
    expect(p.proposal.digest, hasLength(64));
    expect(p.changes.single.next!.versionId, f.ver(20));
    expect(p.footprint.shared, isTrue);
    expect(base.single.toWire().toText(), before);
    expect(() => p.changes.clear(), throwsUnsupportedError);
    final roundtrip = StoredProposal.fromWire(p.toWire());
    expect(roundtrip.toWire().toText(), p.toWire().toText());
  });
  test('submit and withdraw preserve the original ownership origin and compiled versions', () {
    final original = prepare();
    final submitted = prepare(
      request: transition(original),
      previous: original,
      author: true,
      principal: other,
    );
    expect(submitted.owner, actor);
    expect(submitted.authorOrigin, isFalse);
    expect(submitted.proposal.proposalId, original.proposal.proposalId);
    expect(submitted.proposal.version, BigInt.two);
    expect(submitted.proposal.submission, Submission.submitted);
    expect(
      submitted.changes.single.toCanonical().toText(),
      original.changes.single.toCanonical().toText(),
    );
    expect(
      submitted.proposal.operationId,
      isNot(original.proposal.operationId),
    );
    expect(submitted.proposal.digest, isNot(original.proposal.digest));
    final withdrawn = prepare(
      request: transition(submitted, withdraw: true),
      previous: submitted,
    );
    expect(withdrawn.proposal.withdrawn, isTrue);
    expect(withdrawn.proposal.version, BigInt.from(3));
    final resubmitted = prepare(
      request: transition(withdrawn),
      previous: withdrawn,
    );
    expect(resubmitted.proposal.withdrawn, isTrue);
    expect(resubmitted.proposal.version, BigInt.from(4));
  });
  test('revision recompiles and uses the acting profile origin without changing proposal identity', () {
    final original = prepare();
    final withdrawn = prepare(
      request: transition(original, withdraw: true),
      previous: original,
    );
    final next = prepare(
      request: revise(withdrawn),
      previous: withdrawn,
      principal: other,
      author: true,
      versions: {f.id(10): f.ver(30)},
    );
    expect(next.owner, other);
    expect(next.authorOrigin, isTrue);
    expect(next.proposal.proposalId, original.proposal.proposalId);
    expect(next.proposal.version, BigInt.from(3));
    expect(next.proposal.withdrawn, isFalse);
    expect(next.changes.single.next!.versionId, f.ver(30));
    expect(next.proposal.rationale, 'Revised edit');
  });
  test('state transitions require the exact previous reference and represented frame', () {
    final original = prepare();
    expect(
      () => prepare(request: transition(original)),
      throwsA(isA<ApprovalStaleError>()),
    );
    expect(
      () => prepare(request: revise(original)),
      throwsA(isA<ApprovalStaleError>()),
    );
    final otherFrame = Frame(
      universe: f.u,
      continuity: frames.frame().continuity,
      revision: f.revision,
      context: f.ref(98),
      time: const TimelessFrameTime(),
      perspective: const AuthorPerspective(),
    );
    expect(
      () => prepare(
        request: transition(original),
        previous: original,
        frame: otherFrame,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
    // A revision can deliberately use a newly selected author frame.
    expect(
      prepare(
        request: revise(original),
        previous: original,
        frame: otherFrame,
      ).proposal.baseFrame,
      otherFrame,
    );
  });
  test('proposals require an all-validities author frame', () {
    final at = frames.frame(
      time: AtFrameTime(ExactTime(frames.calendar, '12')),
    );
    expect(() => prepare(frame: at), throwsA(isA<UnsupportedSemanticsError>()));
    final reader = Frame(
      universe: f.u,
      continuity: frames.frame().continuity,
      revision: f.revision,
      context: f.ref(99),
      time: const TimelessFrameTime(),
      perspective: const ReaderPerspective(),
    );
    expect(
      () => prepare(frame: reader),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
  });
  test('named focus uses the complete write footprint', () {
    final world = WorldId.parse('wld_${f.suffix(10)}');
    expect(
      () => prepare(focus: world),
      throwsA(isA<WorldScopeConflictError>()),
    );
    final p = prepare(
      focus: world,
      request: create(
        operations: [
          CreateWorldOperation(
            clientRef: f.id(10).value,
            record: WorldRecord(selector: 'Earth'),
          ),
        ],
      ),
    );
    expect(p.footprint.worlds, {world});
    expect(p.footprint.shared, isFalse);
    expect(p.proposal.worldScope, world);
    expect(
      () => prepare(
        focus: world,
        request: create(
          operations: [
            CreateWorldOperation(
              clientRef: f.id(10).value,
              record: WorldRecord(selector: 'Earth'),
            ),
            CreateWorldOperation(
              clientRef: f.id(11).value,
              record: WorldRecord(selector: 'Mars'),
            ),
          ],
        ),
      ),
      throwsA(isA<WorldScopeConflictError>()),
    );
  });
  test('stored proposal reads preserve owner and world-scope restrictions', () {
    final p = prepare();
    access(p);
    access(p, principal: other, author: true);
    expect(
      () => access(p, principal: other),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(
      () => access(p, scope: {}),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final wrong = ProposalRef(
      proposalId: p.reference.proposalId,
      version: p.reference.version,
      digest: 'b' * 64,
    );
    expect(
      () => access(p, reference: wrong),
      throwsA(isA<ApprovalStaleError>()),
    );
    final world = WorldId.parse('wld_${f.suffix(10)}');
    final local = prepare(
      focus: world,
      request: create(
        operations: [
          CreateWorldOperation(
            clientRef: f.id(10).value,
            record: WorldRecord(selector: 'Earth'),
          ),
        ],
      ),
    );
    access(local, scope: {world});
    expect(
      () => access(local, scope: {}),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });
  test('latest proposal selection uses ordered immutable version keys', () {
    final old = prepare(),
        next = prepare(request: transition(old), previous: old);
    expect(isLatestProposal(old, []), isFalse);
    expect(isLatestProposal(old, [old.key]), isTrue);
    expect(isLatestProposal(old, [old.key, next.key]), isFalse);
    expect(isLatestProposal(next, [old.key, next.key]), isTrue);
    expect(old.key.endsWith(':00000000000000000001'), isTrue);
  });
}
