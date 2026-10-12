import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';

import 'assessment_resolution.dart';
import 'installation_authority.dart';
import 'proposal_authorization.dart';
import 'proposal_state.dart';
import 'validation_binding.dart';

/// Internal native workflow for an already recovered, writer-owned package.
/// It retains checked results, never approvals or canonical facts. The caller
/// must produce the checked result through the factual evaluator, not client IO.
final class SqliteValidationWorkflow {
  SqliteValidationWorkflow({
    required this.package,
    required this.authority,
    required this.principal,
  });
  final OwnedSqliteDatabase package;
  final InstallationAuthority authority;
  final InstallationPrincipal principal;
  UniverseId get universe => package.universeId;
  SqliteJournal get _journal => SqliteJournal(package.database, universe);
  WorkflowStorage get _workflow => WorkflowStorage(package.database);

  RecordVersion _version(RecordVersionId id) =>
      RecordVersion.fromWire(_journal.load(id).toCanonical());
  List<RecordVersion> _canon(ContinuityId continuity, RevisionId revision) {
    final rows =
        [
          for (final version in _journal.snapshot(continuity, revision).values)
            _version(version),
        ]..sort(
          (a, b) =>
              a.identity.recordId.value.compareTo(b.identity.recordId.value),
        );
    return rows;
  }

  StoredProposal _proposal(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) {
    final value = _workflow.get(proposalKey(reference));
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = StoredProposal.fromWire(value);
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
    authority.authorizeWrite(
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
            ? _canon(
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
    return proposal;
  }

  Future<ValidationCapture> _capture(
    StoredProposal proposal,
    CurrentUniverseAuthority current,
  ) => captureValidationBinding(
    proposal: proposal,
    authorityDigest: current.validationDigest,
    authoritySequence: current.sequence,
    readLatestKey: _workflow.latestKey,
    readWorkflow: _workflow.get,
    readHead: _journal.head,
    resolveSelected: (reference) => resolveAssessment(
      reference: reference,
      universe: universe,
      canObserveMissingMaterial:
          current.principal.author && current.worldScope == null,
      readProposal: (reference) => _proposal(reference, current),
      checkAccess: (proposal, body) async {
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
    ),
  );

  Future<ValidationCapture> capture(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _capture(_proposal(reference, current), current),
      );

  Future<void> persist(ProposalRef reference, CheckedValidation checked) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _workflow.compareAppendWithVerification(
          verify: () async {
            final proposal = _proposal(reference, current);
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
          entries: [
            MapEntry(
              'validation:${checked.validation.runId.value}',
              checked.toWire(),
            ),
          ],
        ),
      );
}
