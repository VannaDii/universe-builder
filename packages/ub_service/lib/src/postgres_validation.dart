import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/ub_store.dart';

import 'assessment_resolution.dart';
import 'candidate_validation.dart';
import 'installation_authority.dart';
import 'operation_state.dart';
import 'proposal_authorization.dart';
import 'proposal_state.dart';
import 'proposal_validation.dart';
import 'validation_binding.dart';

/// Native PostgreSQL proposal workflow in the caller's installation transaction.
/// Public engine routing must resolve/authorize contexts before supplying frames.
/// Approval remains a private human route; publication re-evaluates the exact
/// retained candidate. No method accepts caller-authored checked validation.
final class PostgresValidationWorkflow {
  PostgresValidationWorkflow({
    required this.session,
    required this.universe,
    required this.authority,
    required this.principal,
  });
  final PostgresInstallationSession session;
  final UniverseId universe;
  final PostgresServiceAuthority authority;
  final InstallationPrincipal principal;
  PostgresKernel get _kernel => session.kernel(universe);
  PostgresJournal get _journal => _kernel.journal;
  PostgresWorkflowStorage get _workflow => session.workflows(universe);
  Future<RecordVersion> _version(RecordVersionId id) async =>
      RecordVersion.fromWire((await _journal.load(id)).toCanonical());
  Future<List<RecordVersion>> _canon(
    ContinuityId continuity,
    RevisionId revision,
  ) async {
    final rows = <RecordVersion>[];
    for (final id in (await _journal.snapshot(continuity, revision)).values) {
      rows.add(await _version(id));
    }
    rows.sort(
      (a, b) => a.identity.recordId.value.compareTo(b.identity.recordId.value),
    );
    return rows;
  }

  Future<List<RecordVersion>> _preview(CommitInput input) async =>
      (await _kernel.preview(input))
          .map((r) => RecordVersion.fromWire(r.toCanonical()))
          .toList();
  Future<StoredProposal> _proposal(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) async {
    final value = await _workflow.get(proposalKey(reference));
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = StoredProposal.fromWire(value);
    await _admitProposal(proposal, reference, current);
    return proposal;
  }

  Future<void> _admitProposal(
    StoredProposal proposal,
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) async {
    if (proposal.proposal.baseFrame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    authorizeStoredProposal(
      stored: proposal,
      reference: reference,
      principal: current.principal.id,
      author: current.principal.author,
      scope: current.worldScope,
    );
    await authority.authorizeWrite(
      principal,
      universe: universe,
      worlds: proposal.footprint.worlds,
      shared: proposal.footprint.shared,
      protected: proposal.footprint.protected,
      commit: false,
    );
    try {
      if (current.limits.continuities != null &&
          !current.limits.continuities!.contains(
            proposal.proposal.baseFrame.continuity,
          )) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      checkWriteBoundaries(
        base:
            current.limits.entities != null || current.limits.predicates != null
            ? await _canon(
                proposal.proposal.baseFrame.continuity,
                proposal.proposal.baseFrame.revision,
              )
            : const [],
        changes: proposal.changes,
        continuity: proposal.proposal.baseFrame.continuity,
        limits: current.limits,
      );
    } on Object {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
  }

  Future<AssessmentReview> _assessmentReview(
    ProposalRef reference,
    CurrentUniverseAuthority current, {
    AssessmentRef? exact,
    bool publication = false,
  }) => resolveAssessment(
    reference: reference,
    exact: exact,
    universe: universe,
    canObserveMissingMaterial:
        publication || current.principal.author && current.worldScope == null,
    readProposal: (reference) async => await _proposal(reference, current),
    checkAccess: (proposal, body) async {
      if (publication) return;
      await checkAssessmentAccess(
        proposal: proposal,
        body: body,
        limits: current.limits,
        worldScope: current.worldScope,
        readCanon: _canon,
        readVersion: _version,
      );
    },
    readLatestKey: _workflow.latestKey,
    readWorkflow: _workflow.get,
    readHead: _journal.head,
    readCanon: _canon,
    readVersion: _version,
  );

  Future<ValidationCapture> _capture(
    StoredProposal proposal,
    CurrentUniverseAuthority current, {
    bool publication = false,
  }) => captureValidationBinding(
    proposal: proposal,
    authorityDigest: current.validationDigest,
    authoritySequence: current.sequence,
    readLatestKey: _workflow.latestKey,
    readWorkflow: _workflow.get,
    readHead: _journal.head,
    resolveSelected: (reference) =>
        _assessmentReview(reference, current, publication: publication),
  );

  Future<Proposal> propose(
    WorkflowRequest request, {
    required Frame resolvedFrame,
    required WorldId? worldFocus,
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _propose(
      request,
      current,
      resolvedFrame: resolvedFrame,
      worldFocus: worldFocus,
      isValidationActive: isValidationActive,
    ),
  );

  Future<Proposal> _propose(
    WorkflowRequest request,
    CurrentUniverseAuthority current, {
    required Frame resolvedFrame,
    required WorldId? worldFocus,
    required bool Function(OperationId) isValidationActive,
    Map<RecordId, RecordVersionId> versions = const {},
  }) async {
    final (
      String idempotencyKey,
      UniverseId? requestedUniverse,
      ProposalRef? reference,
      bool compile,
    ) = switch (request) {
      CreateProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        null,
        true,
      ),
      ReviseProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        request.proposalReference,
        true,
      ),
      SubmitProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        request.proposalReference,
        false,
      ),
      WithdrawProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        request.proposalReference,
        false,
      ),
      _ => throw ArgumentError.value(
        request,
        'request',
        'Expected proposal state action',
      ),
    };
    if (resolvedFrame.universe != universe ||
        requestedUniverse != null && requestedUniverse != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    if (resolvedFrame.time is! TimelessFrameTime) {
      throw const UnsupportedSemanticsError(
        message:
            'create or revise proposals from an all-validities author frame',
      );
    }
    final key = operationRequestKey(principal.id, 'propose', idempotencyKey);
    final digest = canonicalDigest(request.toArgs());
    if (await _workflow.get(key) != null) {
      final op = await loadStoredOperation(
        key: key,
        principal: principal.id,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
        readReceipt: _journal.receipt,
        isValidationActive: isValidationActive,
      );
      if (op.digest != digest) {
        throw const IdempotencyKeyReusedError(message: 'request differs');
      }
      final saved = op.status.proposal;
      if (saved == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      return saved;
    }
    final previous = reference == null
        ? null
        : await _proposal(reference, current);
    if (previous != null &&
        await _workflow.latestKey('proposal:${reference!.proposalId.value}:') !=
            previous.key) {
      throw const ApprovalStaleError();
    }
    final base = await _canon(resolvedFrame.continuity, resolvedFrame.revision);
    final prepared = prepareProposal(
      request: request,
      frame: resolvedFrame,
      base: base,
      principal: principal.id,
      author: principal.author,
      worldFocus: worldFocus,
      previous: previous,
      versions: versions,
    );
    await _admitProposal(prepared, prepared.reference, current);
    final kernel = _kernel;
    if (compile) {
      await checkProposalReservations(
        stored: prepared,
        readWorkflow: _workflow.get,
        identityExists: kernel.journal.identityExists,
        readVersion: _version,
      );
      final input = await proposalCommitInput(
        stored: prepared,
        universe: universe,
        principal: principal.id,
        idempotencyKey: 'proposal-preview',
        readCanon: _canon,
      );
      await kernel.preview(input);
    }
    final p = prepared.proposal;
    final op = StoredOperation(
      owner: principal.id,
      digest: digest,
      input: null,
      footprint: prepared.footprint,
      status: OperationStatus(
        operationId: p.operationId,
        kind: OperationKind.propose,
        state: OperationState.succeeded,
        proposal: p,
        cancellationRequested: false,
      ),
    );
    final entries = [
      MapEntry(prepared.key, prepared.toWire()),
      MapEntry(key, op.toWire()),
      MapEntry('operation:${p.operationId.value}', op.toWire()),
      ...await proposalReservationEntries(
        stored: prepared,
        readWorkflow: _workflow.get,
      ),
    ];
    final comparisons = <String, String?>{};
    if (previous != null) {
      comparisons['proposal:${previous.proposal.proposalId.value}:'] =
          previous.key;
    }
    await _workflow.compareAppend(comparisons, entries);
    return p;
  }

  Future<ValidationCapture> capture(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) async =>
            _capture(await _proposal(reference, current), current),
      );

  Future<ValidationV3> validate(
    ProposalRef reference, {
    required Frame resolvedFrame,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _validate(reference, resolvedFrame, current),
  );

  Future<ValidationV3> _validate(
    ProposalRef reference,
    Frame frame,
    CurrentUniverseAuthority current,
  ) async {
    if (frame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final stored = await _proposal(reference, current);
    if (stored.proposal.baseFrame != frame) {
      throw const ApprovalStaleError();
    }
    final captured = current.worldScope == null
        ? await _capture(stored, current)
        : null;
    final result = await checkProposalCandidate(
      stored: stored,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: current.worldScope,
      preview: _preview,
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
    );
    final report =
        captured?.report(
          proposal: reference,
          baseFrame: frame,
          execution: result.validation,
          finished: true,
        ) ??
        ValidationV3.restricted();
    final completed = CheckedValidation(
      proposalDigest: result.proposalDigest,
      validation: result.validation,
      admissible: result.admissible,
      capture: captured,
      report: report,
    );
    await _persistValidation(reference, completed, current, [
      MapEntry(
        'validation:${result.validation.runId.value}',
        completed.toWire(),
      ),
    ]);
    return report;
  }

  Future<CommitReceipt> commit(
    CommitRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) =>
        _commit(request, current, isValidationActive: isValidationActive),
  );

  Future<CommitReceipt> _commit(
    CommitRequest request,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = await _proposal(request.proposalReference, current);
    final p = proposal.proposal;
    await authority.authorizeWrite(
      principal,
      universe: universe,
      worlds: proposal.footprint.worlds,
      shared: proposal.footprint.shared,
      protected: proposal.footprint.protected,
      commit: true,
    );
    final key = operationRequestKey(
      principal.id,
      'commit',
      request.idempotencyKey,
    );
    final digest = canonicalDigest(request.toArgs());
    Future<StoredOperation> load() => loadStoredOperation(
      key: key,
      principal: principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    );
    StoredOperation? operation;
    if (await _workflow.get(key) != null) {
      operation = await load();
      if (operation.digest != digest) {
        throw const IdempotencyKeyReusedError(message: 'request differs');
      }
      if (operation.status.receipt != null) return operation.status.receipt!;
    }
    if (await _workflow.latestKey('proposal:${p.proposalId.value}:') !=
            proposal.key ||
        p.withdrawn ||
        p.submission != Submission.submitted ||
        request.expectedBaseRevision != p.baseFrame.revision) {
      throw const ApprovalStaleError();
    }
    final value = await _workflow.get(
      'validation:${request.validationRun.value}',
    );
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final checked = CheckedValidation.fromWire(value);
    if (checked.proposalDigest != p.digest ||
        !checked.admissible ||
        checked.validation.evaluatorVersion != candidateEvaluatorVersion) {
      throw const ApprovalStaleError();
    }
    final limits = current.limits;
    final delegated =
        limits.delegatedCommit &&
        !proposal.footprint.protected &&
        (!proposal.footprint.shared || limits.allowShared) &&
        checked.validation.coverage == Coverage.complete;
    if (!delegated) {
      final approval = await _workflow.get(
        'approval:${current.approvalAuthor.value}:${p.digest}:${request.validationRun.value}',
      );
      if (approval == null) {
        throw const ApprovalRequiredError(
          message: 'author must approve this exact proposal and validation',
        );
      }
      final fields = WireFields(approval, {
        'author',
        'proposal',
        'validation_digest',
        'evaluator',
      });
      if (fields.string('evaluator') != candidateEvaluatorVersion ||
          fields.string('author') != current.approvalAuthor.value ||
          fields.string('validation_digest') !=
              canonicalDigest(checked.toWire())) {
        throw const ApprovalStaleError();
      }
    }
    Future<ValidationCapture> capture() async {
      final result = await _capture(proposal, current, publication: true);
      verifyPublicationReport(
        report: checked.report,
        current: result,
        proposal: request.proposalReference,
        baseFrame: p.baseFrame,
        execution: checked.validation,
      );
      return result;
    }

    final captured = await capture();
    final head = await _journal.head(p.baseFrame.continuity);
    if (head != request.expectedBaseRevision) {
      throw BaseRevisionConflictError(
        expected: request.expectedBaseRevision.value,
        actual: head.value,
      );
    }
    final kernel = _kernel;
    final fresh = await checkProposalCandidate(
      stored: proposal,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: null,
      preview: _preview,
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
    );
    final v = fresh.validation;
    final comparable = Validation(
      operationId: checked.validation.operationId,
      runId: checked.validation.runId,
      coverage: v.coverage,
      findings: v.findings,
      opposingEvidence: v.opposingEvidence,
      unsupportedCapabilities: v.unsupportedCapabilities,
      inputDigest: v.inputDigest,
      evaluatorVersion: v.evaluatorVersion,
    );
    if (!fresh.admissible ||
        canonicalDigest(comparable.toWire()) !=
            canonicalDigest(checked.validation.toWire())) {
      throw const ApprovalStaleError();
    }
    await capture();
    final CommitInput input = await proposalCommitInput(
      stored: proposal,
      universe: universe,
      principal: principal.id,
      idempotencyKey: request.idempotencyKey,
      readCanon: _canon,
    );
    if (operation == null) {
      final id = OperationId.generate();
      operation = StoredOperation(
        owner: principal.id,
        digest: digest,
        input: input,
        footprint: proposal.footprint,
        status: OperationStatus(
          operationId: id,
          kind: OperationKind.commit,
          state: OperationState.committing,
          proposal: p,
          cancellationRequested: false,
        ),
      );
      await _workflow.compareAppend({}, [
        MapEntry(key, operation.toWire()),
        MapEntry('operation:${id.value}', operation.toWire()),
      ]);
    }
    if (operation.status.cancellationRequested) {
      throw const PolicyDeniedError(
        message: 'operation cancelled before commit',
      );
    }
    verifyValidationAuthority(captured, current.sequence);
    final revision = await kernel.commit(
      input,
      expectedWorkflow: captured.comparisons(),
    );
    return CommitReceipt(
      operationId: operation.status.operationId,
      proposalId: p.proposalId,
      revision: revision,
    );
  }

  /// Private human approval route. Public model requests cannot supply approval
  /// evidence; this binds the current author's decision to retained Checked data.
  Future<CanonicalObject> approve(ProposalRef reference, ValidationRunId run) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _approve(reference, run, current),
      );

  Future<CanonicalObject> _approve(
    ProposalRef reference,
    ValidationRunId run,
    CurrentUniverseAuthority current,
  ) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final entries = <MapEntry<String, CanonicalValue>>[];
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        final proposal = await _proposal(reference, current);
        final value = await _workflow.get('validation:${run.value}');
        if (value == null) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final checked = CheckedValidation.fromWire(value);
        final p = proposal.proposal;
        if (await _workflow.latestKey(
                  'proposal:${reference.proposalId.value}:',
                ) !=
                proposal.key ||
            p.withdrawn ||
            p.submission != Submission.submitted ||
            checked.proposalDigest != reference.digest ||
            checked.validation.evaluatorVersion != candidateEvaluatorVersion ||
            await _journal.head(p.baseFrame.continuity) !=
                p.baseFrame.revision) {
          throw const ApprovalStaleError();
        }
        if (!checked.admissible) {
          throw const PolicyDeniedError(
            message: 'validation blocks approval; review the blocking findings',
          );
        }
        final capture = await _capture(proposal, current);
        verifyPublicationReport(
          report: checked.report,
          current: capture,
          proposal: reference,
          baseFrame: p.baseFrame,
          execution: checked.validation,
        );
        verifyValidationAuthority(capture, current.sequence);
        entries.add(
          MapEntry(
            'approval:${current.approvalAuthor.value}:${reference.digest}:${run.value}',
            CanonicalObject([
              MapEntry('author', CanonicalString(principal.id.value)),
              MapEntry('proposal', reference.toWire()),
              MapEntry(
                'validation_digest',
                CanonicalString(canonicalDigest(checked.toWire())),
              ),
              MapEntry('evaluator', CanonicalString(candidateEvaluatorVersion)),
            ]),
          ),
        );
        return capture.comparisons();
      },
    );
    return CanonicalObject([
      MapEntry('approved', reference.toWire()),
      MapEntry('validation_run', CanonicalString(run.value)),
    ]);
  }

  Future<void> _persistValidation(
    ProposalRef reference,
    CheckedValidation checked,
    CurrentUniverseAuthority current,
    List<MapEntry<String, CanonicalValue>> entries,
  ) => _workflow.compareAppendWithVerification(
    verify: () async {
      final proposal = await _proposal(reference, current);
      if (checked.proposalDigest != proposal.proposal.digest) {
        throw const ApprovalStaleError();
      }
      final captured = checked.capture;
      if (captured == null) return const {};
      verifyValidationAuthority(captured, current.sequence);
      final fresh = await _capture(proposal, current);
      verifyValidationCapture(
        proposal: reference,
        captured: captured,
        current: fresh,
      );
      return captured.comparisons();
    },
    entries: entries,
  );
}
