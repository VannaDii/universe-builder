import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'validation_binding_test.dart' as bindings;
import 'rule_checks_test.dart' as frames;
import 'opposing_diagnostics_test.dart' as opposing;

void main() {
  final proposal = proposals.prepare();
  final check = WritingCheck(
    status: 'needs_clarification',
    additions: ['New object: Iris'],
    unchanged: [],
    clarifications: [],
    excluded: ['Represented belief'],
    unknowns: ['Unspecified time'],
  );
  ValidationV3 report({
    Coverage coverage = Coverage.complete,
    EvidenceOutcome? outcome,
    Coverage findingCoverage = Coverage.complete,
    List<String> unsupported = const [],
    bool opposition = false,
  }) => bindings
      .capture(reference: proposal.reference)
      .report(
        proposal: proposal.reference,
        baseFrame: frames.frame(),
        finished: true,
        execution: Validation(
          runId: ValidationRunId.generate(),
          coverage: coverage,
          findings: [
            if (outcome != null)
              Finding(
                fingerprint: FindingFingerprint('a' * 64),
                ruleId: f.id(50),
                outcome: outcome,
                evidence: [],
                coverage: findingCoverage,
              ),
          ],
          unsupportedCapabilities: unsupported,
          opposingEvidence: opposition
              ? opposing.diagnostics(opposing.fixture())
              : [],
          inputDigest: proposal.proposal.digest,
          evaluatorVersion: 'finite-policy-v15-writer-constraint-diagnostics',
        ),
      );
  WritingCheck finish(
    ValidationV3 validation, {
    Coverage impact = Coverage.complete,
    bool delivered = true,
  }) => finishWritingCheck(
    check: check,
    proposal: proposal.proposal,
    validation: validation,
    impact: Impact(records: [f.id(1)], worldIds: [], coverage: impact),
    impactDeliveryComplete: delivered,
  );

  test(
    'only complete supported checks yield a provisional checked candidate',
    () {
      final validation = report(outcome: EvidenceOutcome.supported);
      final result = finish(validation);
      expect(result.status, 'checked_candidate');
      expect(result.candidateHandle, proposal.proposal.proposalId.value);
      expect(result.additions, check.additions);
      expect(result.excluded, check.excluded);
      expect(result.unknowns, check.unknowns);
      expect(result.validation!.toText(), validation.toWire().toText());
      expect(proposal.proposal.canonical, isFalse);
      expect(proposal.proposal.submission, Submission.draft);
    },
  );

  test('restricted unsupported partial and undelivered checks are incomplete before conflict classification', () {
    expect(finish(ValidationV3.restricted()).status, 'incomplete');
    expect(
      finish(
        report(coverage: Coverage.partial, outcome: EvidenceOutcome.refuted),
      ).status,
      'incomplete',
    );
    expect(finish(report(unsupported: ['unknown.v1'])).status, 'incomplete');
    expect(finish(report(), impact: Coverage.restricted).status, 'incomplete');
    expect(finish(report(), delivered: false).status, 'incomplete');
  });

  test('unresolved findings need clarification and opposition is never a passing candidate', () {
    expect(
      finish(report(outcome: EvidenceOutcome.notEstablished)).status,
      'needs_clarification',
    );
    expect(
      finish(
        report(
          outcome: EvidenceOutcome.supported,
          findingCoverage: Coverage.partial,
        ),
      ).status,
      'needs_clarification',
    );
    expect(finish(report(outcome: EvidenceOutcome.refuted)).status, 'conflict');
    expect(
      finish(report(outcome: EvidenceOutcome.conflicting)).status,
      'conflict',
    );
    expect(finish(report(opposition: true)).status, 'conflict');
  });
}
