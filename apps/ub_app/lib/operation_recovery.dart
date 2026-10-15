import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

bool canCancelOperation(OperationStatusV3 status) => !{
  OperationState.succeeded,
  OperationState.failed,
  OperationState.cancelled,
}.contains(status.state);

final class OperationRecovery {
  const OperationRecovery({
    required this.call,
    required this.universe,
    required this.universeId,
  });
  final Future<CanonicalValue> Function(EngineRequest) call;
  final Selector universe;
  final UniverseId universeId;

  Future<OperationStatusV3> read(OperationId id) async {
    String? cursor;
    OperationStatusV3? first;
    final findings = <Finding>[];
    do {
      final response = Envelope<OperationStatusV3>.fromWire(
        await call(
          ToolEngineRequest(
            request: GetOperationIdRequest(
              universe: universe,
              universeId: universeId,
              operationId: id,
              cursor: cursor,
            ),
          ),
        ),
        OperationStatusV3.fromWire,
      );
      first ??= response.result;
      if (response.result.validation case EvaluatedValidation(
        :final execution,
      )) {
        findings.addAll(execution.findings);
      }
      if (response.delivery.complete) break;
      cursor = response.delivery.cursor;
      if (cursor == null) {
        throw const FormatException(
          'The complete operation result was not returned.',
        );
      }
    } while (true);
    if (first.validation case EvaluatedValidation(
      :final execution,
      :final submittedInput,
      :final assessment,
      :final finalBindingDigest,
    )) {
      return OperationStatusV3(
        operationId: first.operationId,
        kind: first.kind,
        state: first.state,
        proposal: first.proposal,
        receipt: first.receipt,
        failure: first.failure,
        cancellationRequested: first.cancellationRequested,
        validation: EvaluatedValidation(
          execution: Validation(
            operationId: execution.operationId,
            runId: execution.runId,
            coverage: execution.coverage,
            findings: findings,
            opposingEvidence: execution.opposingEvidence,
            unsupportedCapabilities: execution.unsupportedCapabilities,
            inputDigest: execution.inputDigest,
            evaluatorVersion: execution.evaluatorVersion,
          ),
          submittedInput: submittedInput,
          assessment: assessment,
          finalBindingDigest: finalBindingDigest,
        ),
      );
    }
    return first;
  }

  String cancellationKey(OperationId id) => 'flutter-cancel-${id.value}';

  Future<OperationStatusV3> cancel(OperationId id) async {
    try {
      await call(
        ToolEngineRequest(
          request: GetOperationKeyRequest(
            universe: universe,
            universeId: universeId,
            operationKind: OperationKind.cancel,
            idempotencyKey: cancellationKey(id),
          ),
        ),
      );
    } on NotFoundOrNotAccessibleError {
      await call(
        ToolEngineRequest(
          request: CancelOperationRequest(
            universe: universe,
            universeId: universeId,
            operationId: id,
            idempotencyKey: cancellationKey(id),
          ),
        ),
      );
    }
    return read(id);
  }
}
