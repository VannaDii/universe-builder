import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/candidate_validation.dart';
import 'package:ub_service/operation_state.dart';
import 'package:ub_service/validation_binding.dart';

import 'assessment_validation_test.dart' as a;
import 'operation_state_test.dart' as operations;
import 'validation_capture_test.dart' as captures;

Validation execution({
  Coverage coverage = Coverage.complete,
  String? evaluator,
}) => Validation(
  runId: ValidationRunId.generate(),
  coverage: coverage,
  findings: [],
  unsupportedCapabilities: [],
  inputDigest: a.proposal.proposal.digest,
  evaluatorVersion: evaluator ?? candidateEvaluatorVersion,
);
StoredOperation operation(
  Validation execution, {
  ValidationCapture? capture,
  OperationState state = OperationState.queued,
}) => StoredOperation(
  owner: a.proposal.owner,
  digest: 'a' * 64,
  input: null,
  footprint: a.proposal.footprint,
  validationCapture: capture,
  status: OperationStatus(
    operationId: operations.id,
    kind: OperationKind.validate,
    state: state,
    proposal: a.proposal.proposal,
    validation: execution,
    failure: 'Private source details',
    cancellationRequested: state == OperationState.cancelled,
  ),
);
Future<OperationStatusV3> report(
  StoredOperation op, {
  Set<WorldId>? scope,
  CheckedValidation? checked,
  void Function(String)? onRead,
}) => publicOperationStatus(
  status: op.status,
  worldScope: scope,
  readWorkflow: (key) {
    onRead?.call(key);
    if (key == 'validation:${op.status.validation!.runId.value}') {
      return checked?.toWire();
    }
    if (key == a.proposal.key) return a.proposal.toWire();
    if (key == 'operation:${operations.id.value}') return op.toWire();
    throw StateError('Unexpected workflow key');
  },
);

void main() {
  test('scoped validation returns restricted values without reading complete evidence', () async {
    final op = operation(execution());
    final result = await report(
      op,
      scope: {},
      onRead: (_) => fail('Complete evidence read'),
    );
    expect(result.validation, isA<RestrictedValidation>());
    expect(result.failure, isNull);
    expect(result.proposal, isNull);
    expect(result.operationId, operations.id);
    expect(result.state, OperationState.queued);
    final restricted = await report(
      operation(execution(coverage: Coverage.restricted)),
      onRead: (_) => fail('Restricted execution read full evidence'),
    );
    expect(restricted.validation, isA<RestrictedValidation>());
  });

  test('queued captured report retains attributed source accounting without a finished binding', () async {
    final capture = await captures.capture();
    final result = await report(operation(execution(), capture: capture));
    final evaluated = result.validation as EvaluatedValidation;
    expect(evaluated.assessment, isA<BoundAssessment>());
    expect(
      (evaluated.assessment as BoundAssessment).declaredConclusion,
      DeclaredConclusion.unresolved,
    );
    expect(evaluated.submittedInput, isA<SourceAssessedCandidateInput>());
    expect(evaluated.finalBindingDigest, isNull);
  });

  test('failed cancelled and interrupted fallbacks report unavailable assessment and record input', () async {
    final capture = await captures.capture();
    for (final state in [
      OperationState.failed,
      OperationState.cancelled,
      OperationState.interrupted,
    ]) {
      final result = await report(
        operation(execution(), capture: capture, state: state),
      );
      final evaluated = result.validation as EvaluatedValidation;
      expect(
        (evaluated.assessment as UnavailableAssessment).reason,
        UnavailableReason.failedOrCancelledCheck,
      );
      expect(evaluated.submittedInput, isA<RecordCandidateInput>());
      expect(evaluated.finalBindingDigest, isNull);
      expect(result.state, state);
    }
  });

  test('missing retained reports distinguish current and legacy evaluators without manufacturing completion', () async {
    final current = await report(
      operation(execution(), state: OperationState.succeeded),
    );
    final evaluated = current.validation as EvaluatedValidation;
    expect(evaluated.assessment, isA<AbsentAssessment>());
    expect(evaluated.finalBindingDigest, isNull);
    final legacy = await report(
      operation(execution(evaluator: 'historical-evaluator')),
    );
    expect(
      (legacy.validation as EvaluatedValidation).assessment,
      isA<LegacyUnavailableAssessment>(),
    );
    expect(
      (legacy.validation as EvaluatedValidation).finalBindingDigest,
      isNull,
    );
  });

  test('completed retained report preserves its exact finished binding and input accounting', () async {
    final capture = await captures.capture();
    final core = execution();
    final completed = capture.report(
      proposal: a.proposal.reference,
      baseFrame: a.proposal.proposal.baseFrame,
      execution: core,
      finished: true,
    );
    final checked = CheckedValidation(
      proposalDigest: a.proposal.proposal.digest,
      validation: core,
      admissible: true,
      capture: capture,
      report: completed,
    );
    final result = await report(
      operation(core, capture: capture, state: OperationState.succeeded),
      checked: checked,
      onRead: (key) => expect(key, 'validation:${core.runId.value}'),
    );
    expect(result.validation!.toWire().toText(), completed.toWire().toText());
    expect(
      (result.validation as EvaluatedValidation).finalBindingDigest,
      completed.finalBindingDigest,
    );
  });
}
