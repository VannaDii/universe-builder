import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/validation_task.dart';

import 'proposal_state_test.dart' as proposals;
import 'operation_compilation_test.dart' as f;
import 'structural_checks_test.dart' as structure;

void main() {
  test('evaluation uses immutable snapshots and propagates cancellation', () {
    final base = [structure.context(99)];
    final proposal = proposals.prepare(base: base);
    final candidate = [...base, f.row(10, f.entity())];
    final task = PreparedValidationTask(
      operationId: OperationId.generate(),
      proposal: proposal,
      base: base,
      candidate: candidate,
      approvalAuthor: proposals.actor,
      restricted: false,
      capture: null,
    );
    base.clear();
    candidate.clear();
    expect(task.base, hasLength(1));
    expect(task.candidate, hasLength(2));
    expect(() => task.candidate.clear(), throwsUnsupportedError);
    final checked = task.evaluate();
    expect(checked.proposalDigest, proposal.proposal.digest);
    expect(checked.validation.inputDigest, proposal.proposal.digest);
    final cancelled = StateError('cancelled');
    expect(
      () => task.evaluate(checkCancelled: () => throw cancelled),
      throwsA(same(cancelled)),
    );
  });

  test('restricted evaluation returns no complete evidence or capture', () {
    final proposal = proposals.prepare();
    final task = PreparedValidationTask(
      operationId: OperationId.generate(),
      proposal: proposal,
      base: [],
      candidate: [],
      approvalAuthor: proposals.actor,
      restricted: true,
      capture: null,
    );
    final checked = task.evaluate(
      checkCancelled: () =>
          fail('Restricted evaluation does not execute the candidate'),
    );
    expect(checked.validation.coverage, Coverage.restricted);
    expect(checked.admissible, isFalse);
    expect(checked.capture, isNull);
    expect(checked.report, isNull);
    expect(checked.validation.findings, isEmpty);
    expect(checked.validation.opposingEvidence, isEmpty);
  });
}
