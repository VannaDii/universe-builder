import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';

final class WritingChoice {
  WritingChoice(CanonicalValue value) {
    final f = WireFields(value, {
      'candidate',
      'label',
      'submission',
      'base_revision',
      'continuity',
    });
    candidate = ProposalRef.fromWire(f.require('candidate'));
    label = f.string('label');
    submission = Submission.fromName(f.string('submission'));
    continuity = ContinuityId.parse(f.string('continuity'));
  }
  late final ProposalRef candidate;
  late final String label;
  late final Submission submission;
  late final ContinuityId continuity;
}

final class WritingApproval {
  WritingApproval(CanonicalValue value) {
    final f = WireFields(value, {'candidate', 'validation_run', 'label'});
    candidate = ProposalRef.fromWire(f.require('candidate'));
    run = ValidationRunId.parse(f.string('validation_run'));
    label = f.string('label');
  }
  late final ProposalRef candidate;
  late final ValidationRunId run;
  late final String label;
  // Preserve the existing native writing publication key across UI migrations.
  String get publicationKey =>
      'native-writing-commit-${candidate.digest}-${run.value}';
}

final class WritingReview {
  WritingReview(CanonicalValue value) {
    final f = WireFields(value, {
      'candidate',
      'validation',
      'impact',
      'publishable',
      'review',
      'summary',
      'acceptance_options',
    });
    candidate = ProposalRef.fromWire(f.require('candidate'));
    validation = ValidationV3.fromWire(f.require('validation'));
    impact = Impact.fromWire(f.require('impact'));
    publishable = f.boolean('publishable');
    summary = f.array('summary').map(wireString).toList();
    acceptance = f.array('acceptance_options').map((value) {
      final option = WireFields(value, {'fingerprint', 'scope'});
      return (
        fingerprint: FindingFingerprint(option.string('fingerprint')),
        scope: option.string('scope'),
      );
    }).toList();
    final review = WireFields(f.require('review'), {
      'proposal',
      'changes',
      'diff',
      'footprint',
      'latest',
      'assessment_review',
    });
    proposal = Proposal.fromWire(review.require('proposal'));
    footprint = review.require('footprint');
    diff = review.require('diff');
  }
  late final ProposalRef candidate;
  late final Proposal proposal;
  late final ValidationV3 validation;
  late final Impact impact;
  late final bool publishable;
  late final List<String> summary;
  late final List<({FindingFingerprint fingerprint, String scope})> acceptance;
  late final CanonicalValue footprint, diff;
}

/// Uses the same author actions as the existing native writing review.
/// Approval and publication remain distinct service requests.
final class WritingWorkflow {
  const WritingWorkflow(this.changes);
  final SavedChanges changes;

  Future<({List<WritingChoice> proposals, List<WritingApproval> approved})>
  choices() async {
    final library = await changes.session.call(
      LibraryEngineRequest(universe: changes.universe),
    ) as CanonicalObject;
    final writing = WireFields(Map.fromEntries(library.fields)['writing']!, {
      'proposals',
      'approved',
    });
    return (
      proposals: writing
          .array('proposals')
          .map(WritingChoice.new)
          .where((row) => row.continuity == changes.scope.continuity)
          .toList(),
      approved: writing.array('approved').map(WritingApproval.new).toList(),
    );
  }

  Future<Proposal> exact(ProposalRef candidate) async {
    final proposal = Envelope<Proposal>.fromWire(
      await changes.session.call(
        ToolEngineRequest(
          request: GetProposalRequest(
            universe: changes.universe,
            universeId: changes.scope.universe,
            proposalId: candidate.proposalId,
            version: candidate.version,
          ),
        ),
      ),
      Proposal.fromWire,
    ).result;
    if (changes.reference(proposal) != candidate) {
      throw const FormatException('Reopen the original proposal.');
    }
    return proposal;
  }

  Future<WritingReview> review(AuthorWritingAction action) async =>
      WritingReview(
        await changes.session.call(
          AuthorWritingEngineRequest(
            universe: changes.universe,
            action: action,
          ),
        ),
      );

  Future<void> reject(ProposalId candidate) async {
    await changes.session.call(
      AuthorWritingEngineRequest(
        universe: changes.universe,
        action: RejectWritingAction(candidate: candidate),
      ),
    );
  }

  Future<WritingApproval> approve(WritingReview review) async {
    final response = await changes.session.call(
      ApproveEngineRequest(
        universe: changes.universe,
        proposalReference: review.candidate,
        validationRun: review.validation.execution!.runId,
      ),
    );
    final approval = WireFields(response, {'approved', 'validation_run'});
    return WritingApproval(
      CanonicalObject([
        MapEntry('candidate', approval.require('approved')),
        MapEntry('validation_run', approval.require('validation_run')),
        MapEntry('label', CanonicalString(review.proposal.rationale)),
      ]),
    );
  }

  Future<CommitReceipt> publish(WritingApproval approval) async {
    final proposal = await exact(approval.candidate);
    return Envelope<CommitReceipt>.fromWire(
      await changes.session.call(
        ToolEngineRequest(
          request: CommitRequest(
            universe: changes.universe,
            universeId: changes.scope.universe,
            proposalReference: approval.candidate,
            expectedBaseRevision: proposal.baseFrame.revision,
            validationRun: approval.run,
            idempotencyKey: approval.publicationKey,
          ),
        ),
      ),
      CommitReceipt.fromWire,
    ).result;
  }

  EditorFormScope passageScope(Proposal proposal) => EditorFormScope(
    instance: changes.scope.instance,
    profile: changes.scope.profile,
    universe: changes.scope.universe,
    continuity: proposal.baseFrame.continuity,
    representedContext: proposal.baseFrame.context.record,
    typeClientRef: 'writing:${proposal.proposalId.value}',
  );

  UnfinishedSourceForm passage(
    Proposal proposal, {
    String label = '',
    String text = '',
  }) => UnfinishedSourceForm(
    baseRevision: proposal.baseFrame.revision,
    representedContext: proposal.baseFrame.context.record,
    clientRef: 'writing:${proposal.proposalId.value}',
    label: label,
    text: text,
  );
}
