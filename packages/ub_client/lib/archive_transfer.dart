/// Shared client transfer workflow, usable with native and web service callers.
library;

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Stage a move, resume its target upload, and return the target import review.
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
  return target(
    ReviewArchiveUploadEngineRequest(
      uploadId: uploadId,
      name: name,
      mode: ImportMode.restore,
    ),
  );
}
