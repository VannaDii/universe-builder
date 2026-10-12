import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

import 'proposal_authorization.dart';
import 'validation_binding.dart';

CommitInput _input(CanonicalValue value) {
  final f = WireFields(value, {
    'universe',
    'continuity',
    'expected_head',
    'principal',
    'decision',
    'reason',
    'idempotency_key',
    'changes',
  });
  return CommitInput(
    universe: UniverseId.parse(f.string('universe')),
    continuity: ContinuityId.parse(f.string('continuity')),
    expectedHead: RevisionId.parse(f.string('expected_head')),
    principal: PrincipalId.parse(f.string('principal')),
    decision: f.string('decision'),
    reason: f.string('reason'),
    idempotencyKey: f.string('idempotency_key'),
    changes: f.array('changes').map((value) {
      final change = CompiledChange.fromWire(value);
      final next = change.next;
      return Assignment(
        recordId: change.recordId,
        expected: change.expected,
        next: next == null
            ? null
            : StoredVersion(
                versionId: next.recordVersionId,
                identity: next.identity,
                payload: next.payload.toWire(),
                digest: next.payloadDigest,
              ),
      );
    }),
  );
}

/// Durable operation inputs and ownership, separate from live scheduler state.
final class StoredOperation {
  const StoredOperation({
    required this.owner,
    required this.digest,
    required this.status,
    required this.input,
    required this.footprint,
    this.validationCapture,
  });
  final ProfileId owner;
  final String digest;
  final OperationStatus status;
  final CommitInput? input;
  final WriteFootprint footprint;
  final ValidationCapture? validationCapture;
  factory StoredOperation.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'owner',
      'digest',
      'status',
      'input',
      'footprint',
      'validation_capture',
    });
    final footprint = WireFields(f.require('footprint'), {
      'worlds',
      'shared',
      'protected',
    });
    return StoredOperation(
      owner: ProfileId.parse(f.string('owner')),
      digest: f.string('digest'),
      status: OperationStatus.fromWire(f.require('status')),
      input: f.optional('input', _input),
      footprint: WriteFootprint(
        worlds: footprint
            .array('worlds')
            .map((v) => WorldId.parse(wireString(v))),
        shared: footprint.boolean('shared'),
        protected: footprint.boolean('protected'),
      ),
      validationCapture: f.optional(
        'validation_capture',
        ValidationCapture.fromWire,
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('owner', CanonicalString(owner.value)),
    MapEntry('digest', CanonicalString(digest)),
    MapEntry('status', status.toWire()),
    MapEntry('input', input?.toCanonical() ?? const CanonicalNull()),
    MapEntry('footprint', footprint.toWire()),
    MapEntry(
      'validation_capture',
      validationCapture?.toWire() ?? const CanonicalNull(),
    ),
  ]);
}

/// Resolve retained state under current authority. No status is written here.
/// Only the live scheduler may establish [isValidationActive]; a stored running
/// marker alone is insufficient. Durable commit receipts take priority over loss
/// or cancellation because committed facts must never be reported as cancelled.
Future<StoredOperation> loadStoredOperation({
  required String key,
  required ProfileId principal,
  required Set<WorldId>? worldScope,
  required FutureOr<CanonicalValue?> Function(String) readWorkflow,
  required FutureOr<RevisionId?> Function(CommitInput) readReceipt,
  required bool Function(OperationId) isValidationActive,
}) async {
  const denied = NotFoundOrNotAccessibleError(message: 'resource');
  Future<StoredOperation> load(String key) async {
    final value = await readWorkflow(key);
    if (value == null) throw denied;
    return StoredOperation.fromWire(value);
  }

  var op = await load(key);
  if (op.status.kind == OperationKind.validate &&
      !key.startsWith('operation:')) {
    op = await load('operation:${op.status.operationId.value}');
  }
  if (op.status.kind == OperationKind.validate) {
    for (final state in ['terminal', 'running']) {
      final saved = await readWorkflow(
        'job:${op.status.operationId.value}:$state',
      );
      if (saved != null) {
        op = StoredOperation.fromWire(saved);
        break;
      }
    }
  }
  if (op.owner != principal ||
      worldScope != null &&
          (op.footprint.shared ||
              !op.footprint.worlds.every(worldScope.contains))) {
    throw denied;
  }
  var state = op.status.state;
  var receipt = op.status.receipt;
  var cancelled = op.status.cancellationRequested;
  final id = op.status.operationId;
  final input = op.input;
  if (input != null) {
    final revision = await readReceipt(input);
    if (revision != null) {
      final proposal = op.status.proposal;
      if (proposal == null) throw denied;
      state = OperationState.succeeded;
      receipt = CommitReceipt(
        operationId: id,
        proposalId: proposal.proposalId,
        revision: revision,
      );
    } else if (await readWorkflow('cancel:${id.value}') != null) {
      state = OperationState.cancelled;
      cancelled = true;
    } else {
      state = OperationState.interrupted;
    }
  }
  if (op.status.kind == OperationKind.validate) {
    if (await readWorkflow('cancel:${id.value}') != null) {
      state = OperationState.cancelled;
      cancelled = true;
    } else if (state == OperationState.running && !isValidationActive(id)) {
      state = OperationState.interrupted;
    }
  }
  return StoredOperation(
    owner: op.owner,
    digest: op.digest,
    input: op.input,
    footprint: op.footprint,
    validationCapture: op.validationCapture,
    status: OperationStatus(
      validation: op.status.validation,
      failure: op.status.failure,
      operationId: id,
      kind: op.status.kind,
      state: state,
      proposal: op.status.proposal,
      receipt: receipt,
      cancellationRequested: cancelled,
    ),
  );
}
