/// Selected-file archive upload for the browser; review and admission stay separate.
library;

import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

/// The caller retains uploadId and the selected file for an explicit retry.
/// Calls are never replayed automatically. The service's acknowledged ordinal
/// resumes a retry, including a chunk retained before its response was lost.
/// Supply the canonical archive digest from source transfer metadata. It is
/// not a hash of the SQLite file bytes. File reads use the existing 256 KiB
/// archive chunk budget; no
/// whole-file buffer is constructed. This returns a review, never an admission.
Future<CanonicalValue> uploadBrowserArchive({
  required web.File file,
  required String digest,
  required OperationId uploadId,
  required String name,
  required ImportMode mode,
  required Future<CanonicalValue> Function(EngineRequest) call,
  bool Function()? isCancelled,
  void Function(int receivedBytes, int totalBytes)? onProgress,
}) async {
  const chunkBytes = ReadMoveChunkEngineRequest.chunkBytes;
  final length = file.size;
  if (length < 1 ||
      length > chunkBytes * ReadMoveChunkEngineRequest.maxChunks) {
    throw const FormatException('Package exceeds the archive byte budget');
  }
  if (name.trim().isEmpty) {
    throw const FormatException('Enter the imported universe name');
  }
  void checkCancelled() {
    if (isCancelled?.call() == true) {
      throw StateError('Archive transfer cancelled');
    }
  }

  Future<List<int>> read(int start) async {
    checkCancelled();
    final end = (start + chunkBytes).clamp(0, length);
    final bytes = (await file.slice(start, end).arrayBuffer().toDart).toDart
        .asUint8List();
    checkCancelled();
    if (bytes.length != end - start) {
      throw const FormatException(
        'Selected package could not be read completely',
      );
    }
    return bytes;
  }

  checkCancelled();
  final begin = BeginArchiveUploadEngineRequest(
    uploadId: uploadId,
    digest: digest,
    bytes: length,
  );
  begin.validate();
  final progress = WireFields(await call(begin), {
    'upload_id',
    'digest',
    'bytes',
    'next_ordinal',
    'received_bytes',
  });
  if (progress.string('upload_id') != uploadId.value ||
      progress.string('digest') != digest ||
      progress.u64('bytes') != BigInt.from(length)) {
    throw const FormatException(
      'Upload progress belongs to a different package',
    );
  }
  final count = (length + chunkBytes - 1) ~/ chunkBytes;
  final next = progress.u64('next_ordinal');
  final received = progress.u64('received_bytes');
  if (next > BigInt.from(count) ||
      received != BigInt.from((next.toInt() * chunkBytes).clamp(0, length))) {
    throw const FormatException('Upload progress exceeds archive length');
  }
  checkCancelled();
  onProgress?.call(received.toInt(), length);
  for (var ordinal = next.toInt(); ordinal < count; ordinal++) {
    final bytes = await read(ordinal * chunkBytes);
    await call(
      WriteArchiveChunkEngineRequest(
        uploadId: uploadId,
        chunk: MoveArchiveChunk(ordinal: ordinal, content: bytes),
      ),
    );
    checkCancelled();
    onProgress?.call(((ordinal + 1) * chunkBytes).clamp(0, length), length);
  }
  checkCancelled();
  return call(
    ReviewArchiveUploadEngineRequest(
      uploadId: uploadId,
      name: name,
      mode: mode,
    ),
  );
}
