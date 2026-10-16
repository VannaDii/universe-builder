@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/validation_task.dart';
import 'package:ub_service/validation_worker.dart';

import 'proposal_state_test.dart' as proposals;

import 'package:ub_service/src/universe_evidence_policy.dart';

import 'operation_compilation_test.dart' as f;
import 'structural_checks_test.dart' as structure;

PreparedValidationTask task() {
  final base = [
    structure.context(99),
    ...initialUniversePolicyRecords(f.u, false),
  ];
  return PreparedValidationTask(
    operationId: OperationId.generate(),
    proposal: proposals.prepare(base: base),
    base: base,
    candidate: [...base, f.row(10, f.entity())],
    approvalAuthor: proposals.actor,
    restricted: false,
    capture: null,
  );
}

void main() {
  test(
    'native isolate evaluates frozen inputs without service handles',
    () async {
      final input = task();
      final expected = input.evaluate();
      final worker = ValidationEvaluationWorker(input);
      final result = await worker.result;
      expect(result.proposalDigest, expected.proposalDigest);
      expect(result.admissible, expected.admissible);
      expect(result.validation.coverage, expected.validation.coverage);
      expect(result.validation.inputDigest, expected.validation.inputDigest);
      worker.cancel();
      expect(await worker.result, same(result));
    },
  );

  test('cancellation during spawn settles once and kills the worker', () async {
    final worker = ValidationEvaluationWorker(task());
    final result = expectLater(
      worker.result,
      throwsA(isA<UnsupportedSemanticsError>()),
    );
    worker.cancel();
    worker.cancel();
    await result;
    // Exercise the spawn completion after cancellation, without starting a
    // replacement task or retaining success for the cancelled evaluation.
    await worker.ready;
  });
}
