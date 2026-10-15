import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';

AssessmentRef? assessmentReference(AssessmentState state) => switch (state) {
  BoundAssessment(:final assessmentReference) ||
  StaleAssessment(:final assessmentReference) => assessmentReference,
  _ => null,
};

/// Read the attachment from the checked assessment, without changing selection.
/// Large declarations use the service's existing UTF-8 fragment/cursor contract.
Future<AssessmentEnvelope?> readProposalAssessment(
  SavedChanges changes,
  Proposal proposal,
  AssessmentRef reference,
) async {
  String? cursor;
  final fragments = StringBuffer();
  do {
    final response = Envelope<AssessmentReviewPage>.fromWire(
      await changes.session.call(
        ToolEngineRequest(
          request: GetProposalRequest(
            universe: changes.universe,
            universeId: changes.scope.universe,
            proposalId: proposal.proposalId,
            version: proposal.version,
            viewGroup: ProposalView.assessment,
            assessmentReference: reference,
            cursor: cursor,
          ),
        ),
      ),
      AssessmentReviewPage.fromWire,
    );
    if (response.result.envelope case final envelope?) return envelope;
    if (response.result.fragment case final fragment?) {
      fragments.write(fragment.canonicalEnvelopeUtf8);
    }
    if (response.delivery.complete) {
      return fragments.isEmpty
          ? null
          : AssessmentEnvelope.fromWire(
              CanonicalValue.parseWireJson(fragments.toString()),
            );
    }
    cursor = response.delivery.cursor;
    if (cursor == null) {
      throw const FormatException('The full assessment was not returned.');
    }
  } while (true);
}
