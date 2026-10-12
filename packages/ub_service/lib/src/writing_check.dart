import 'package:ub_contracts/ub_contracts.dart';

/// An evaluated candidate is still provisional. This status grants neither
/// human approval nor publication, and incomplete/restricted results never pass.
WritingCheck finishWritingCheck({
  required WritingCheck check,
  required Proposal proposal,
  required ValidationV3 validation,
  required Impact impact,
  required bool impactDeliveryComplete,
}) {
  final execution = validation.execution;
  final complete =
      validation is EvaluatedValidation &&
      execution != null &&
      execution.coverage == Coverage.complete &&
      execution.unsupportedCapabilities.isEmpty &&
      impactDeliveryComplete &&
      impact.coverage == Coverage.complete;
  final unresolved =
      execution?.findings.any(
        (f) =>
            f.outcome != EvidenceOutcome.supported ||
            f.coverage != Coverage.complete,
      ) ??
      false;
  final conflict =
      (execution?.findings.any(
            (f) =>
                f.outcome == EvidenceOutcome.conflicting ||
                f.outcome == EvidenceOutcome.refuted,
          ) ??
          false) ||
      (execution?.opposingEvidence.isNotEmpty ?? false);
  return WritingCheck(
    status: !complete
        ? 'incomplete'
        : conflict
        ? 'conflict'
        : unresolved || check.clarifications.isNotEmpty
        ? 'needs_clarification'
        : 'checked_candidate',
    candidateHandle: proposal.proposalId.value,
    additions: check.additions,
    unchanged: check.unchanged,
    clarifications: check.clarifications,
    excluded: check.excluded,
    unknowns: check.unknowns,
    validation: validation.toWire(),
    impact: impact.toWire(),
  );
}
