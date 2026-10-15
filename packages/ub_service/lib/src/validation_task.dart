import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'candidate_validation.dart';
import 'proposal_state.dart';
import 'validation_binding.dart';

/// Frozen, already admitted evaluation inputs. No database or authority handle
/// enters the evaluator; completion must revalidate before retaining results.
final class PreparedValidationTask {
  PreparedValidationTask({
    required this.operationId,
    required this.proposal,
    required Iterable<RecordVersion> base,
    required Iterable<RecordVersion> candidate,
    required this.approvalAuthor,
    required this.restricted,
    required this.capture,
    this.selectedAssessment,
    Iterable<RecordVersion> evidenceCategories = const [],
  }) : base = List.unmodifiable(base),
       candidate = List.unmodifiable(candidate),
       evidenceCategories = List.unmodifiable(evidenceCategories);
  final OperationId operationId;
  final StoredProposal proposal;
  final List<RecordVersion> base, candidate;
  final ProfileId approvalAuthor;
  final bool restricted;
  final ValidationCapture? capture;
  final AssessmentReview? selectedAssessment;
  final List<RecordVersion> evidenceCategories;

  CheckedValidation evaluate({void Function()? checkCancelled}) {
    if (restricted) {
      return CheckedValidation(
        proposalDigest: proposal.proposal.digest,
        admissible: false,
        validation: Validation(
          runId: ValidationRunId.generate(),
          coverage: Coverage.restricted,
          findings: [],
          opposingEvidence: [],
          unsupportedCapabilities: [
            'Author validation required for complete evaluation scope',
          ],
          inputDigest: proposal.proposal.digest,
          evaluatorVersion: candidateEvaluatorVersion,
        ),
      );
    }
    final result = evaluateCandidate(
      candidate: candidate,
      base: base,
      changes: proposal.changes,
      frame: proposal.proposal.baseFrame,
      digest: proposal.proposal.digest,
      footprint: proposal.footprint,
      authorOrigin: proposal.authorOrigin,
      approvalAuthor: approvalAuthor,
      selectedAssessment: selectedAssessment,
      evidenceCategories: evidenceCategories,
      checkCancelled: checkCancelled,
    );
    return CheckedValidation(
      proposalDigest: proposal.proposal.digest,
      validation: result.validation,
      admissible: result.admissible,
      capture: capture,
    );
  }
}
