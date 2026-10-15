part of 'installation_store.dart';

CanonicalObject archiveUploadProgress(
  BeginArchiveUploadEngineRequest upload,
  int nextOrdinal,
) => CanonicalObject([
  MapEntry('upload_id', CanonicalString(upload.uploadId.value)),
  MapEntry('digest', CanonicalString(upload.digest)),
  MapEntry('bytes', CanonicalNumber('${upload.bytes}')),
  MapEntry('next_ordinal', CanonicalNumber('$nextOrdinal')),
  MapEntry(
    'received_bytes',
    CanonicalNumber(
      '${nextOrdinal * ReadMoveChunkEngineRequest.chunkBytes < upload.bytes ? nextOrdinal * ReadMoveChunkEngineRequest.chunkBytes : upload.bytes}',
    ),
  ),
]);

extension InstallationUploads on SqliteInstallationStore {
  InstallationImportPreview reviewArchiveUpload({
    required ProfileId actor,
    required ReviewArchiveUploadEngineRequest request,
  }) {
    final upload = _upload(actor, request.uploadId);
    selectorKey(request.name);
    final existing = _db.select(
      'SELECT preview_digest FROM import_preview WHERE id=? AND owner=?',
      [request.uploadId.value, actor.value],
    );
    if (existing.isNotEmpty) {
      final preview = loadImport(
        actor: actor,
        id: request.uploadId,
        digest: existing.single['preview_digest'] as String,
      );
      if (preview.sourceDigest != upload.digest ||
          preview.name != request.name ||
          (preview.source == preview.target) !=
              (request.mode == ImportMode.restore)) {
        throw const FormatException(
          'Upload already bound to another import review',
        );
      }
      return preview;
    }
    final temporary = privateTemporaryDirectory(
      Directory.systemTemp.path,
      'universe-builder-upload-review-',
    );
    try {
      privateDirectory(temporary.path);
      final path = '${temporary.path}/archive.sqlite';
      protectedFile(path, createNew: true);
      final output = File(path).openSync(mode: FileMode.writeOnly);
      try {
        var ordinal = 0, bytes = 0;
        while (true) {
          final rows = _db.select(
            'SELECT ordinal,content FROM archive_upload_chunk WHERE upload=? AND ordinal>=? ORDER BY ordinal LIMIT 64',
            [request.uploadId.value, ordinal],
          );
          if (rows.isEmpty) break;
          for (final row in rows) {
            final content = row['content'] as List<int>;
            if (row['ordinal'] != ordinal++ ||
                content.isEmpty ||
                content.length > ReadMoveChunkEngineRequest.chunkBytes ||
                bytes + content.length > upload.bytes) {
              throw const FormatException('Upload chunk integrity mismatch');
            }
            output.writeFromSync(content);
            bytes += content.length;
          }
        }
        if (bytes != upload.bytes) {
          throw const FormatException('Archive upload is incomplete');
        }
        output.flushSync();
      } finally {
        output.closeSync();
      }
      return prepareImport(
        actor: actor,
        source: path,
        name: request.name,
        mode: request.mode,
        previewId: request.uploadId,
        expectedDigest: upload.digest,
      );
    } finally {
      temporary.deleteSync(recursive: true);
    }
  }

  BeginArchiveUploadEngineRequest _upload(ProfileId actor, OperationId id) {
    requireAuthor(actor);
    final rows = _db.select(
      'SELECT source_digest,bytes FROM archive_upload WHERE id=? AND owner=?',
      [id.value, actor.value],
    );
    if (rows.length != 1) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final upload = BeginArchiveUploadEngineRequest(
      uploadId: id,
      digest: rows.single['source_digest'] as String,
      bytes: rows.single['bytes'] as int,
    );
    upload.validate();
    return upload;
  }

  int _nextUploadOrdinal(OperationId id) {
    final rows = _db.select(
      'SELECT ordinal FROM archive_upload_chunk WHERE upload=? ORDER BY ordinal DESC LIMIT 1',
      [id.value],
    );
    return rows.isEmpty ? 0 : (rows.single['ordinal'] as int) + 1;
  }

  CanonicalObject beginArchiveUpload({
    required ProfileId actor,
    required BeginArchiveUploadEngineRequest request,
  }) {
    requireAuthor(actor);
    request.validate();
    final exists = _db.select('SELECT id FROM archive_upload WHERE id=?', [
      request.uploadId.value,
    ]);
    if (exists.isNotEmpty) {
      final retained = _upload(actor, request.uploadId);
      if (retained.digest != request.digest ||
          retained.bytes != request.bytes) {
        throw const FormatException('Upload is bound to another archive');
      }
    } else {
      if (_db.select('SELECT id FROM import_preview WHERE id=?', [
        request.uploadId.value,
      ]).isNotEmpty) {
        throw const FormatException('Upload identity is already reserved');
      }
      _transaction(() {
        requireAuthor(actor);
        _db.execute('INSERT INTO archive_upload VALUES(?,?,?,?)', [
          request.uploadId.value,
          actor.value,
          request.digest,
          request.bytes,
        ]);
      });
    }
    return archiveUploadProgress(request, _nextUploadOrdinal(request.uploadId));
  }

  CanonicalObject writeArchiveChunk({
    required ProfileId actor,
    required WriteArchiveChunkEngineRequest request,
  }) {
    final upload = _upload(actor, request.uploadId);
    final chunk = request.chunk;
    ReadMoveChunkEngineRequest.validateOrdinal(chunk.ordinal);
    final remaining =
        upload.bytes - chunk.ordinal * ReadMoveChunkEngineRequest.chunkBytes;
    final expected = remaining < ReadMoveChunkEngineRequest.chunkBytes
        ? remaining
        : ReadMoveChunkEngineRequest.chunkBytes;
    if (expected <= 0 || chunk.content.length != expected) {
      throw const FormatException('Upload chunk length does not match archive');
    }
    final existing = _db.select(
      'SELECT content=? AS same FROM archive_upload_chunk WHERE upload=? AND ordinal=?',
      [chunk.content, request.uploadId.value, chunk.ordinal],
    );
    if (existing.isNotEmpty) {
      if (existing.single['same'] != 1) {
        throw const FormatException(
          'Upload chunk retry changed retained bytes',
        );
      }
    } else {
      if (chunk.ordinal != _nextUploadOrdinal(request.uploadId)) {
        throw const FormatException('Upload chunks must arrive in order');
      }
      _transaction(() {
        requireAuthor(actor);
        _db.execute('INSERT INTO archive_upload_chunk VALUES(?,?,?)', [
          request.uploadId.value,
          chunk.ordinal,
          chunk.content,
        ]);
      });
    }
    return archiveUploadProgress(upload, _nextUploadOrdinal(request.uploadId));
  }
}
