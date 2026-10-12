import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show Assignment, StoredVersion;

import 'operation_compilation.dart';
import 'proposal_authorization.dart';

String proposalKey(ProposalRef reference) =>
    'proposal:${reference.proposalId.value}:${reference.version.toString().padLeft(20, '0')}';

/// Exact frozen proposal storage, separate from permission and publication.
final class StoredProposal {
  StoredProposal({
    required this.proposal,
    required this.owner,
    required this.authorOrigin,
    required Iterable<Assignment> changes,
    required this.footprint,
  }) : changes = List.unmodifiable(changes);
  final Proposal proposal;
  final ProfileId owner;
  final bool authorOrigin;
  final List<Assignment> changes;
  final WriteFootprint footprint;
  ProposalRef get reference => ProposalRef(
    proposalId: proposal.proposalId,
    version: proposal.version,
    digest: proposal.digest,
  );
  String get key => proposalKey(reference);
  factory StoredProposal.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'proposal',
      'owner',
      'author_origin',
      'changes',
      'footprint',
    });
    final footprint = WireFields(f.require('footprint'), {
      'worlds',
      'shared',
      'protected',
    });
    return StoredProposal(
      proposal: Proposal.fromWire(f.require('proposal')),
      owner: ProfileId.parse(f.string('owner')),
      authorOrigin: f.boolean('author_origin'),
      changes: f.array('changes').map((v) {
        final c = CompiledChange.fromWire(v);
        final next = c.next;
        return Assignment(
          recordId: c.recordId,
          expected: c.expected,
          next: next == null
              ? null
              : StoredVersion(
                  versionId: next.recordVersionId,
                  identity: next.identity,
                  payload: next.payload.toWire(),
                  digest: next.payloadDigest,
                ),
        );
      }),
      footprint: WriteFootprint(
        worlds: footprint
            .array('worlds')
            .map((v) => WorldId.parse(wireString(v))),
        shared: footprint.boolean('shared'),
        protected: footprint.boolean('protected'),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('proposal', proposal.toWire()),
    MapEntry('owner', CanonicalString(owner.value)),
    MapEntry('author_origin', CanonicalBool(authorOrigin)),
    MapEntry('changes', CanonicalArray(changes.map((c) => c.toCanonical()))),
    MapEntry('footprint', footprint.toWire()),
  ]);
}

/// The owning store must load this state by proposalKey(reference) first.
void authorizeStoredProposal({
  required StoredProposal stored,
  required ProposalRef reference,
  required ProfileId principal,
  required bool author,
  required Set<WorldId>? scope,
}) {
  if (stored.proposal.digest != reference.digest) {
    throw const ApprovalStaleError();
  }
  if (!author && stored.owner != principal ||
      scope != null &&
          (stored.footprint.shared ||
              !stored.footprint.worlds.every(scope.contains))) {
    throw const NotFoundOrNotAccessibleError(message: 'resource');
  }
}

/// Keys must be the owning store's ordered immutable proposal namespace.
bool isLatestProposal(StoredProposal stored, List<String> keys) =>
    keys.isNotEmpty && keys.last == stored.key;

/// Prepares the next frozen state after request, context, prior-proposal and
/// latest-version admission. Callers must still authorize its full footprint,
/// check record reservations and adoption, preview kernel admission, and persist
/// proposal/operation/receipt/reservations together. This function writes nothing.
StoredProposal prepareProposal({
  required WorkflowRequest request,
  required Frame frame,
  required List<RecordVersion> base,
  required ProfileId principal,
  required bool author,
  required WorldId? worldFocus,
  StoredProposal? previous,
  Map<RecordId, RecordVersionId> versions = const {},
}) {
  if (frame.time is! TimelessFrameTime) {
    throw const UnsupportedSemanticsError(
      message: 'create or revise proposals from an all-validities author frame',
    );
  }
  if (frame.perspective is! AuthorPerspective) {
    throw const UnsupportedSemanticsError(
      message: 'proposals require an author perspective frame',
    );
  }
  List<DomainOperation> operations;
  Submission submission;
  String rationale;
  List<Assignment> changes;
  WriteFootprint footprint;
  ProfileId owner;
  bool authorOrigin, withdrawn, canonical;
  List<CompiledChange> compiled;
  ProposalId id;
  BigInt version;
  Frame proposalFrame;
  WorldId? proposalWorld;
  switch (request) {
    case CreateProposalRequest() || ReviseProposalRequest():
      if (request is ReviseProposalRequest &&
          (previous == null ||
              previous.reference != request.proposalReference)) {
        throw const ApprovalStaleError();
      }
      final create = request is CreateProposalRequest;
      operations = create
          ? request.operations
          : (request as ReviseProposalRequest).operations;
      submission = create
          ? request.submission
          : (request as ReviseProposalRequest).submission;
      rationale = create
          ? request.rationale
          : (request as ReviseProposalRequest).rationale;
      changes = compileAllocatedOperations(
        universe: frame.universe,
        revision: frame.revision,
        base: base,
        operations: operations,
        versions: versions,
      );
      footprint = writeFootprint(base: base, changes: changes);
      id = create ? ProposalId.generate() : previous!.proposal.proposalId;
      version = create ? BigInt.one : previous!.proposal.version + BigInt.one;
      owner = principal;
      authorOrigin = author;
      withdrawn = false;
      canonical = false;
      compiled = [];
      proposalFrame = frame;
      proposalWorld = worldFocus;
    case SubmitProposalRequest() || WithdrawProposalRequest():
      final reference = request is SubmitProposalRequest
          ? request.proposalReference
          : (request as WithdrawProposalRequest).proposalReference;
      if (previous == null ||
          previous.reference != reference ||
          previous.proposal.baseFrame != frame) {
        throw const ApprovalStaleError();
      }
      final old = previous.proposal;
      operations = old.operations;
      submission = request is WithdrawProposalRequest
          ? old.submission
          : Submission.submitted;
      rationale = old.rationale;
      changes = previous.changes;
      footprint = previous.footprint;
      id = old.proposalId;
      version = old.version + BigInt.one;
      owner = previous.owner;
      authorOrigin = previous.authorOrigin;
      withdrawn = request is WithdrawProposalRequest || old.withdrawn;
      canonical = old.canonical;
      compiled = old.compiledChanges;
      proposalFrame = old.baseFrame;
      proposalWorld = old.worldScope;
    default:
      throw ArgumentError.value(
        request,
        'request',
        'Expected a proposal state action',
      );
  }
  if (worldFocus != null &&
      (footprint.shared || footprint.worlds.any((w) => w != worldFocus))) {
    throw const WorldScopeConflictError(
      message: 'full write footprint exceeds named world; omit focus for an explicit cross-world proposal',
    );
  }
  final unsigned = Proposal(
    baseFrame: proposalFrame,
    worldScope: proposalWorld,
    proposalId: id,
    version: version,
    digest: '',
    submission: submission,
    operations: operations,
    compiledChanges: compiled,
    rationale: rationale,
    canonical: canonical,
    operationId: OperationId.generate(),
    withdrawn: withdrawn,
  );
  final digest = canonicalDigest(
    CanonicalArray([
      unsigned.toWire(),
      CanonicalArray(changes.map((c) => c.toCanonical())),
      footprint.toWire(),
    ]),
  );
  final proposal = Proposal.fromWire(
    CanonicalObject(
      unsigned.toWire().fields.map(
        (e) => MapEntry(
          e.key,
          e.key == 'digest' ? CanonicalString(digest) : e.value,
        ),
      ),
    ),
  );
  return StoredProposal(
    proposal: proposal,
    owner: owner,
    authorOrigin: authorOrigin,
    changes: changes,
    footprint: footprint,
  );
}
