import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

import 'candidate_validation.dart';
import 'proposal_state.dart';
import 'source_verification.dart';
import 'validation_binding.dart';

/// Disclosures and their complete dependency closure must still be the exact
/// versions in the edition's pinned canon. This does not authorize disclosure.
Future<void> checkSceneDisclosures({
  required VersionRef edition,
  required List<RecordRef> disclosures,
  required List<RecordVersion> rows,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  readCanon,
}) async {
  if (disclosures.isEmpty) return;
  RecordVersion? version;
  for (final row in rows) {
    if (row.identity.recordId == edition.record &&
        row.recordVersionId == edition.version) {
      version = row;
      break;
    }
  }
  if (version == null) {
    throw const FormatException('Select the exact published edition.');
  }
  final work = version.payload;
  if (work is! WorkVersionRecord) {
    throw const FormatException('Expected edition');
  }
  final binding = work.binding;
  if (binding is! BoundWork) {
    throw const FormatException(
      'Reader disclosures require an edition bound to one canon revision.',
    );
  }
  final canon = await readCanon(binding.continuity, binding.revision);
  final pending = disclosures.map((r) => r.record).toList(),
      dependencies = <RecordId>{};
  while (pending.isNotEmpty) {
    final target = pending.removeLast();
    if (!dependencies.add(target)) continue;
    RecordVersion? row;
    for (final record in rows) {
      if (record.identity.recordId == target) {
        row = record;
        break;
      }
    }
    if (row == null) {
      throw const FormatException('Disclosure dependencies are unavailable.');
    }
    if (!canon.any(
      (old) =>
          old.identity.recordId == target &&
          old.recordVersionId == row!.recordVersionId,
    )) {
      throw const FormatException(
        "Disclosure and its dependencies must match the edition's pinned canon; research that revision or explicitly create a newly bound edition.",
      );
    }
    pending.addAll(
      recordDependencies(
        StoredVersion(
          versionId: row.recordVersionId,
          identity: row.identity,
          payload: row.payload.toWire(),
          digest: row.payloadDigest,
        ),
      ),
    );
    if (dependencies.length + pending.length > 5000000) {
      throw const FormatException('Disclosure dependency budget exceeded');
    }
  }
}

/// The workflow must already admit the principal and exact frozen proposal.
/// Scene checks use the base plus all changes; a deleted dependency cannot be
/// recovered from history merely to make a current disclosure pass.
Future<CommitInput> proposalCommitInput({
  required StoredProposal stored,
  required UniverseId universe,
  required ProfileId principal,
  required String idempotencyKey,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  readCanon,
}) async {
  final proposed = [
    for (final c in stored.changes)
      if (c.next != null) RecordVersion.fromWire(c.next!.toCanonical()),
  ];
  final scenes = proposed.where((r) => r.payload is SceneRecord);
  if (scenes.isNotEmpty) {
    final frame = stored.proposal.baseFrame;
    final rows = [...await readCanon(frame.continuity, frame.revision)];
    for (final change in stored.changes) {
      rows.removeWhere((r) => r.identity.recordId == change.recordId);
      if (change.next != null) {
        rows.add(RecordVersion.fromWire(change.next!.toCanonical()));
      }
    }
    for (final row in scenes) {
      final scene = row.payload as SceneRecord;
      await checkSceneDisclosures(
        edition: scene.workVersion,
        disclosures: scene.disclosedRecords,
        rows: rows,
        readCanon: readCanon,
      );
    }
  }
  final frame = stored.proposal.baseFrame;
  return CommitInput(
    universe: universe,
    continuity: frame.continuity,
    expectedHead: frame.revision,
    principal: PrincipalId.parse(principal.value.replaceFirst('prf_', 'prn_')),
    decision: stored.proposal.digest,
    reason: stored.proposal.rationale,
    idempotencyKey: idempotencyKey,
    changes: stored.changes,
  );
}

/// Synchronous-workflow candidate check with real kernel preview and retained
/// sources. Call under owning package/installation coordination, after current
/// request, grant and proposal admission. This creates no approval or receipt;
/// capture/report binding and atomic retention remain workflow responsibilities.
Future<CheckedValidation> checkProposalCandidate({
  required StoredProposal stored,
  required UniverseId universe,
  required ProfileId principal,
  required ProfileId approvalAuthor,
  required Set<WorldId>? scope,
  required FutureOr<List<RecordVersion>> Function(CommitInput) preview,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  readCanon,
  required FutureOr<CanonicalValue?> Function(String) readWorkflow,
  required FutureOr<RecordVersion> Function(RecordVersionId) readVersion,
}) async {
  final frame = stored.proposal.baseFrame;
  if (frame.time is! TimelessFrameTime) {
    throw const UnsupportedSemanticsError(
      message: 'proposal validation requires an all-validities author frame',
    );
  }
  if (scope != null) {
    return CheckedValidation(
      proposalDigest: stored.proposal.digest,
      admissible: false,
      validation: Validation(
        runId: ValidationRunId.generate(),
        coverage: Coverage.restricted,
        findings: [],
        opposingEvidence: [],
        unsupportedCapabilities: [
          'An author must validate this proposal against the complete universe.',
        ],
        inputDigest: stored.proposal.digest,
        evaluatorVersion: candidateEvaluatorVersion,
      ),
    );
  }
  await verifyImmutableAdoptions(stored: stored, readVersion: readVersion);
  final input = await proposalCommitInput(
    stored: stored,
    universe: universe,
    principal: principal,
    idempotencyKey: 'validation',
    readCanon: readCanon,
  );
  final candidate = await preview(input);
  await verifyCandidateSources(
    records: candidate,
    readWorkflow: readWorkflow,
    readVersion: readVersion,
  );
  final base = await readCanon(frame.continuity, frame.revision);
  final result = evaluateCandidate(
    candidate: candidate,
    base: base,
    changes: stored.changes,
    frame: frame,
    digest: stored.proposal.digest,
    footprint: stored.footprint,
    authorOrigin: stored.authorOrigin,
    approvalAuthor: approvalAuthor,
  );
  return CheckedValidation(
    proposalDigest: stored.proposal.digest,
    validation: result.validation,
    admissible: result.admissible,
  );
}
