/// Shared client transfer workflow, usable with native and web service callers.
library;

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Stage a move, resume its upload, retain its review at the source, and return
/// the target import review for author approval.
///
/// The caller supplies authenticated connections and retains both operation IDs
/// for an explicit retry after interruption. This function neither reconnects
/// nor accepts the review. The source remains suspended and retained.
Future<CanonicalValue> prepareMoveTransfer({
  required Future<CanonicalValue> Function(EngineRequest) source,
  required Future<CanonicalValue> Function(EngineRequest) target,
  required StageMoveEngineRequest move,
  required OperationId uploadId,
  required String name,
}) async {
  final conflicts = await target(
    CheckImportTargetEngineRequest(universeId: move.universeId, name: name),
  ) as CanonicalArray;
  if (conflicts.items.isNotEmpty) {
    throw const InvalidArgumentError(
      field: 'target',
      message: 'Target already contains this universe or name; choose another target or name before preparing a move',
    );
  }
  final stage = WireFields(await source(move), {
    'source_instance',
    'universe_id',
    'operation_id',
    'target_instance',
    'digest',
    'manifest',
    'bytes',
  });
  final upload = BeginArchiveUploadEngineRequest(
    uploadId: uploadId,
    digest: stage.string('digest'),
    bytes: stage.u64('bytes').toInt(),
  );
  upload.validate();
  final progress = WireFields(await target(upload), {
    'upload_id',
    'digest',
    'bytes',
    'next_ordinal',
    'received_bytes',
  });
  final count =
      (upload.bytes + ReadMoveChunkEngineRequest.chunkBytes - 1) ~/
      ReadMoveChunkEngineRequest.chunkBytes;
  final next = progress.u64('next_ordinal');
  if (next > BigInt.from(count)) {
    throw const FormatException('Upload progress exceeds archive length');
  }
  for (var ordinal = next.toInt(); ordinal < count; ordinal++) {
    final chunk = MoveArchiveChunk.fromWire(
      await source(
        ReadMoveChunkEngineRequest(
          universeId: move.universeId,
          operationId: move.operationId,
          targetInstance: move.targetInstance,
          ordinal: ordinal,
        ),
      ),
    );
    if (chunk.ordinal != ordinal) {
      throw const FormatException('Unexpected move chunk ordinal');
    }
    await target(
      WriteArchiveChunkEngineRequest(uploadId: uploadId, chunk: chunk),
    );
  }
  final report = await target(
    ReviewArchiveUploadEngineRequest(
      uploadId: uploadId,
      name: name,
      mode: ImportMode.restore,
    ),
  );
  final fields = Map.fromEntries((report as CanonicalObject).fields);
  final preview = await target(
    GetImportEngineRequest(
      previewId: OperationId.parse(wireString(fields['preview_id']!)),
      digest: wireString(fields['digest']!),
    ),
  );
  await source(
    ReviewMoveEngineRequest(
      universeId: move.universeId,
      operationId: move.operationId,
      targetInstance: move.targetInstance,
      target: preview as CanonicalObject,
    ),
  );
  return report;
}

/// Admit only the exact target review approved by the author, then retain its
/// receipt at the source. An unknown target outcome is recovered by explicitly
/// calling again with the same move and approval, using reconnected callers.
Future<CanonicalValue> admitMoveTransfer({
  required Future<CanonicalValue> Function(EngineRequest) source,
  required Future<CanonicalValue> Function(EngineRequest) target,
  required StageMoveEngineRequest move,
  required AcceptImportEngineRequest approval,
}) async {
  final recovery = await source(
    GetMoveEngineRequest(operationId: move.operationId),
  );
  final fields = Map.fromEntries((recovery as CanonicalObject).fields);
  if (wireString(fields['universe_id']!) != move.universeId.value ||
      wireString(fields['target_instance']!) != move.targetInstance.value ||
      fields['accept_request']!.toText() != approval.toWire().toText()) {
    throw const ApprovalStaleError();
  }
  if (wireString(fields['state']!) == 'admitted') return fields['receipt']!;
  await source(
    BeginMoveAdmissionEngineRequest(
      universeId: move.universeId,
      operationId: move.operationId,
      targetInstance: move.targetInstance,
    ),
  );
  final receipt = await target(approval);
  return source(
    RecordMoveAdmissionEngineRequest(
      universeId: move.universeId,
      operationId: move.operationId,
      targetInstance: move.targetInstance,
      receipt: receipt as CanonicalObject,
    ),
  );
}
