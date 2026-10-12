import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'proposal_state.dart';

({Proposal proposal, bool complete, int next}) pageFrozenProposal(
  StoredProposal stored,
  int offset,
) {
  final proposal = stored.proposal;
  final total = proposal.operations.length > stored.changes.length
      ? proposal.operations.length
      : stored.changes.length;
  if (offset < 0 || offset > total) {
    throw const NotFoundOrNotAccessibleError(message: 'resource');
  }
  var end = offset, bytes = 0;
  while (end < total) {
    final operation = end < proposal.operations.length
        ? proposal.operations[end].toWire()
        : const CanonicalNull();
    final change = end < stored.changes.length
        ? stored.changes[end].toCanonical()
        : const CanonicalNull();
    final size = operation.toBytes().length + change.toBytes().length;
    if (end > offset && (bytes + size > 65536 || end - offset >= 20)) break;
    bytes += size;
    end++;
  }
  int bound(int value, int length) => value < length ? value : length;
  return (
    proposal: Proposal(
      baseFrame: proposal.baseFrame,
      worldScope: proposal.worldScope,
      proposalId: proposal.proposalId,
      version: proposal.version,
      digest: proposal.digest,
      submission: proposal.submission,
      operations: proposal.operations.sublist(
        bound(offset, proposal.operations.length),
        bound(end, proposal.operations.length),
      ),
      compiledChanges: stored.changes
          .sublist(
            bound(offset, stored.changes.length),
            bound(end, stored.changes.length),
          )
          .map(
            (change) => CompiledChange(
              recordId: change.recordId,
              expected: change.expected,
              next: change.next == null
                  ? null
                  : RecordVersion.fromWire(change.next!.toCanonical()),
            ),
          ),
      rationale: proposal.rationale,
      canonical: proposal.canonical,
      operationId: proposal.operationId,
      withdrawn: proposal.withdrawn,
    ),
    complete: end == total,
    next: end,
  );
}

CanonicalObject assessmentPageBinding(
  CanonicalObject args,
  ProposalRef proposal,
  AssessmentReview review,
) => CanonicalObject([
  ...args.fields,
  MapEntry(
    'assessment_pin',
    CanonicalObject([
      MapEntry('proposal', proposal.toWire()),
      MapEntry('selection', review.selection.toWire()),
      MapEntry(
        'envelope',
        review.envelope == null
            ? const CanonicalNull()
            : AssessmentRef(
                assessmentId: review.envelope!.assessmentId,
                digest: review.envelope!.digest,
              ).toWire(),
      ),
    ]),
  ),
]);

/// Only page a fully authorized review. Fragments use UTF-8 byte offsets and
/// preserve the canonical envelope exactly across multi-byte boundaries.
({AssessmentReviewPage page, bool complete, int next}) pageAssessmentReview(
  AssessmentReview review,
  int offset,
) {
  const denied = NotFoundOrNotAccessibleError(message: 'resource');
  AssessmentReviewPage page({
    AssessmentEnvelope? envelope,
    AssessmentFragment? fragment,
  }) => AssessmentReviewPage(
    selection: review.selection,
    state: review.state,
    envelope: envelope,
    fragment: fragment,
  );
  final envelope = review.envelope;
  if (envelope == null) {
    if (offset != 0) throw denied;
    return (page: page(), complete: true, next: 0);
  }
  final bytes = envelope.toWire().toBytes();
  if (offset == 0 && bytes.length <= 32768) {
    return (page: page(envelope: envelope), complete: true, next: bytes.length);
  }
  bool boundary(int index) =>
      index == bytes.length || bytes[index] & 0xc0 != 0x80;
  if (offset < 0 || offset >= bytes.length || !boundary(offset)) throw denied;
  var end = (offset + 32768).clamp(0, bytes.length);
  while (!boundary(end)) {
    end--;
  }
  return (
    page: page(
      fragment: AssessmentFragment(
        assessmentReference: AssessmentRef(
          assessmentId: envelope.assessmentId,
          digest: envelope.digest,
        ),
        offset: BigInt.from(offset),
        totalBytes: BigInt.from(bytes.length),
        canonicalEnvelopeUtf8: utf8.decode(bytes.sublist(offset, end)),
      ),
    ),
    complete: end == bytes.length,
    next: end,
  );
}
