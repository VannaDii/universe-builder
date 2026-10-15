import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

bool canAcceptResourceFinding(
  Finding finding,
  Map<RecordId, RecordVersion> records,
) =>
    finding.coverage == Coverage.complete &&
    finding.outcome == EvidenceOutcome.notEstablished &&
    finding.records.length == 2 &&
    finding.fingerprint.value.isNotEmpty &&
    switch (records[finding.ruleId]?.payload) {
      RuleRecord(:final capabilities) => capabilities.contains(
        'resources.accounting.v1',
      ),
      _ => false,
    };

/// The selected finding stays bound to the exact proposal shown in Changes.
final class ResourceAcceptance {
  const ResourceAcceptance({required this.proposal, required this.finding});
  final Proposal proposal;
  final Finding finding;
  ProposalRef get reference => ProposalRef(
    proposalId: proposal.proposalId,
    version: proposal.version,
    digest: proposal.digest,
  );
  String get clientRef =>
      'rec_${canonicalDigest(CanonicalObject([MapEntry('proposal', reference.toWire()), MapEntry('finding', CanonicalString(finding.fingerprint.value))])).substring(0, 24)}';
  String get scope => 'resource:${finding.records.first.record.value}';

  UnfinishedIssueDecisionForm form(PrincipalId principal) =>
      UnfinishedIssueDecisionForm(
        baseRevision: proposal.baseFrame.revision,
        representedContext: proposal.baseFrame.context.record,
        clientRef: clientRef,
        principal: principal,
        mode: 'accept',
        fingerprints: [finding.fingerprint.value],
        scope: scope,
      );

  RecordIssueDecisionOperation operation(
    UnfinishedIssueDecisionForm input, {
    required bool author,
    required PrincipalId principal,
  }) {
    if (!author) {
      throw const FormatException(
        'Only the author can accept an unexplained resource count.',
      );
    }
    final expected = form(principal);
    if (input.copyWith(rationale: '').toWire().toText() !=
        expected.toWire().toText()) {
      throw const FormatException(
        'Reopen the current resource finding before accepting it.',
      );
    }
    if (input.rationale.trim().isEmpty) {
      throw const FormatException(
        'Explain why you accept this unexplained count.',
      );
    }
    return RecordIssueDecisionOperation(
      clientRef: clientRef,
      record: IssueDecisionRecord(
        fingerprints: [finding.fingerprint],
        mode: IssueDecisionMode.accept,
        scope: scope,
        rationale: input.rationale,
        principal: principal,
      ),
    );
  }

  String revisionKey(RecordIssueDecisionOperation operation) =>
      'flutter-resource-${canonicalDigest(CanonicalObject([MapEntry('proposal', reference.toWire()), MapEntry('decision', operation.toWire())]))}';
}
