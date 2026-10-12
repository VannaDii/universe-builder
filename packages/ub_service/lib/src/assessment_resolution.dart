import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show Assignment, StoredVersion;

import 'assessment_validation.dart';
import 'proposal_authorization.dart';
import 'proposal_state.dart';

String assessmentSelectionPrefix(ProposalRef proposal) =>
    'assessment-selection:${proposal.proposalId.value}:${proposal.version.toString().padLeft(20, '0')}:';
String assessmentEnvelopeKey(AssessmentRef reference) =>
    'assessment:${reference.assessmentId.value}';

/// Admit the whole frozen candidate, including retained historical dependencies.
/// The owner must supply current grants/scope after installation admission and
/// hold its consistent authority/universe context throughout the reads.
Future<List<RecordVersion>> checkAssessmentAccess({
  required StoredProposal proposal,
  required SourceAssessmentV1? body,
  required GrantLimits limits,
  required Set<WorldId>? worldScope,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  readCanon,
  required FutureOr<RecordVersion> Function(RecordVersionId) readVersion,
}) async {
  const denied = NotFoundOrNotAccessibleError(message: 'resource');
  final frame = proposal.proposal.baseFrame;
  List<RecordVersion>? base;
  Future<void> boundaries(List<Assignment> changes) async {
    try {
      if (limits.continuities != null &&
          !limits.continuities!.contains(frame.continuity)) {
        throw denied;
      }
      if (limits.entities != null || limits.predicates != null) {
        base ??= await readCanon(frame.continuity, frame.revision);
      }
      checkWriteBoundaries(
        base: base ?? const [],
        changes: changes,
        continuity: frame.continuity,
        limits: limits,
      );
    } on Object {
      throw denied;
    }
  }

  await boundaries(proposal.changes);
  base ??= await readCanon(frame.continuity, frame.revision);
  final records = [...assessmentCandidate(proposal, base!)];
  if (body != null) {
    for (final dependency in body.dependencies) {
      if (!records.any((r) => r.recordVersionId == dependency.version)) {
        try {
          records.add(await readVersion(dependency.version));
        } on Object {
          // Missing history does not grant access; later admission rejects it.
        }
      }
    }
  }
  final visible = visibleRecordIds(records: records, worldScope: worldScope);
  if (records.any((r) => !visible.contains(r.identity.recordId))) {
    throw denied;
  }
  await boundaries([
    for (final record in records)
      Assignment(
        recordId: record.identity.recordId,
        next: StoredVersion(
          versionId: record.recordVersionId,
          identity: record.identity,
          payload: record.payload.toWire(),
          digest: record.payloadDigest,
        ),
      ),
  ]);
  return List.unmodifiable(records);
}

/// Resolve in the owning workflow's consistent authority/universe context.
/// [readProposal] must admit the exact reference. [checkAccess] must check the
/// complete candidate and historical dependency visibility/write boundaries.
/// Only the unrestricted author may observe a missing selected body publicly.
/// Private publication may omit access checks only after its complete footprint
/// and exact publication authority have already been admitted by the owner.
Future<AssessmentReview> resolveAssessment({
  required ProposalRef reference,
  AssessmentRef? exact,
  required UniverseId universe,
  required bool canObserveMissingMaterial,
  required FutureOr<StoredProposal> Function(ProposalRef) readProposal,
  required FutureOr<void> Function(StoredProposal, SourceAssessmentV1?)
  checkAccess,
  required FutureOr<String?> Function(String) readLatestKey,
  required FutureOr<CanonicalValue?> Function(String) readWorkflow,
  required FutureOr<RevisionId> Function(ContinuityId) readHead,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  readCanon,
  required FutureOr<RecordVersion> Function(RecordVersionId) readVersion,
}) async {
  const denied = NotFoundOrNotAccessibleError(message: 'resource');
  StoredProposal proposal;
  try {
    proposal = await readProposal(reference);
  } on Object {
    throw denied;
  }
  await checkAccess(proposal, null);
  final key = await readLatestKey(assessmentSelectionPrefix(reference));
  final AssessmentSelection selection;
  if (key == null) {
    selection = AssessmentSelection(
      proposal: reference,
      generation: BigInt.zero,
      selected: null,
    );
  } else {
    final value = await readWorkflow(key);
    if (value == null) throw denied;
    selection = AssessmentSelection.fromWire(value);
  }
  Future<AssessmentEnvelope> load(AssessmentRef requested) async {
    final value = await readWorkflow(assessmentEnvelopeKey(requested));
    if (value == null) throw denied;
    final envelope = AssessmentEnvelope.fromWire(value);
    try {
      envelope.verify();
    } on FormatException catch (e) {
      throw InvalidArgumentError(field: 'assessment', message: e.message);
    }
    if (envelope.digest != requested.digest) throw denied;
    return envelope;
  }

  const unavailable = UnavailableAssessment(
    reason: UnavailableReason.missingRetainedMaterial,
  );
  final selected = selection.selected;
  if (selected != null &&
      await readWorkflow(assessmentEnvelopeKey(selected)) == null) {
    if (!canObserveMissingMaterial) throw denied;
    AssessmentEnvelope? historical;
    if (exact != null &&
        exact.toWire().toText() != selected.toWire().toText()) {
      try {
        historical = await load(exact);
      } on Object {
        throw denied;
      }
      if (historical.body.proposal != reference) throw denied;
      await checkAccess(proposal, historical.body);
    }
    return AssessmentReview(
      selection: selection,
      state: unavailable,
      envelope: historical,
    );
  }
  AssessmentEnvelope? envelope;
  final requested = exact ?? selected;
  if (requested != null) {
    envelope = await load(requested);
    if (envelope.body.proposal != reference) throw denied;
    await checkAccess(proposal, envelope.body);
  }
  if (selected == null) {
    return AssessmentReview(
      selection: selection,
      state: const AbsentAssessment(),
      envelope: envelope,
    );
  }
  final current = await load(selected);
  await checkAccess(proposal, current.body);
  final reasons = await assessmentStaleReasons(
    proposal: proposal,
    body: current.body,
    readLatestKey: readLatestKey,
    readWorkflow: readWorkflow,
    readHead: readHead,
    readCanon: readCanon,
  );
  if (reasons.isNotEmpty) {
    return AssessmentReview(
      selection: selection,
      state: StaleAssessment(assessmentReference: selected, reasons: reasons),
      envelope: envelope,
    );
  }
  for (final source in current.body.sources) {
    CanonicalValue? value;
    try {
      value = await readWorkflow('source:${source.blobDigest.value}');
    } on Object {
      // Read failures are not classified as missing; admission propagates them.
      continue;
    }
    if (value == null) {
      return AssessmentReview(
        selection: selection,
        state: unavailable,
        envelope: envelope,
      );
    }
  }
  await verifyAssessmentCandidate(
    proposal: proposal,
    universe: universe,
    body: current.body,
    readCanon: readCanon,
    readVersion: readVersion,
    readWorkflow: readWorkflow,
  );
  Sha256Hex inventory;
  try {
    inventory = current.body.inventoryDigest();
  } on FormatException catch (e) {
    throw InvalidArgumentError(field: 'assessment', message: e.message);
  }
  return AssessmentReview(
    selection: selection,
    state: BoundAssessment(
      assessmentReference: selected,
      selectionGeneration: selection.generation,
      byteVerification: ByteVerification.verified,
      declaredConclusion: current.body.conclusion,
      inventoryCount: BigInt.from(current.body.declaredInventory.length),
      mappingCount: BigInt.from(current.body.claimMappings.length),
      unresolvedCount: BigInt.from(current.body.unresolved.length),
      inventoryDigest: inventory,
    ),
    envelope: envelope,
  );
}
