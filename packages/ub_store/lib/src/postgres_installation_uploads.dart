part of 'postgres_installation_store.dart';

extension PostgresInstallationUploads on PostgresInstallationSession {
  Future<InstallationImportPreview> reviewArchiveUpload({
    required ProfileId actor,
    required ReviewArchiveUploadEngineRequest request,
  }) => rollbackOnFailure(() async {
    final upload = await _upload(actor, request.uploadId);
    selectorKey(request.name);
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final existing = await _tx.execute(
      'SELECT preview_digest FROM $schema.import_preview WHERE id=\$1 AND owner=\$2',
      parameters: [request.uploadId.value, actor.value],
    );
    if (existing.isNotEmpty) {
      final preview = await loadImport(
        actor: actor,
        id: request.uploadId,
        digest: existing.single.single as String,
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
    final temporary = Directory.systemTemp.createTempSync(
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
          final rows = await _tx.execute(
            'SELECT ordinal,content FROM $schema.archive_upload_chunk WHERE upload=\$1 AND ordinal>=\$2 ORDER BY ordinal LIMIT 64',
            parameters: [request.uploadId.value, ordinal],
          );
          if (rows.isEmpty) break;
          for (final row in rows) {
            final content = row[1] as List<int>;
            if (row[0] != ordinal++ ||
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
      return await prepareImport(
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
  });

  Future<BeginArchiveUploadEngineRequest> _upload(
    ProfileId actor,
    OperationId id,
  ) async {
    await authority.requireAuthor(actor);
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT source_digest,bytes FROM $schema.archive_upload WHERE id=\$1 AND owner=\$2',
      parameters: [id.value, actor.value],
    );
    if (rows.length != 1) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final upload = BeginArchiveUploadEngineRequest(
      uploadId: id,
      digest: rows.single[0] as String,
      bytes: rows.single[1] as int,
    );
    upload.validate();
    return upload;
  }

  Future<int> _nextUploadOrdinal(OperationId id) async {
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT ordinal FROM $schema.archive_upload_chunk WHERE upload=\$1 ORDER BY ordinal DESC LIMIT 1',
      parameters: [id.value],
    );
    return rows.isEmpty ? 0 : (rows.single.single as int) + 1;
  }

  Future<CanonicalObject> beginArchiveUpload({
    required ProfileId actor,
    required BeginArchiveUploadEngineRequest request,
  }) => rollbackOnFailure(() async {
    await authority.requireAuthor(actor);
    request.validate();
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final exists = await _tx.execute(
      'SELECT id FROM $schema.archive_upload WHERE id=\$1',
      parameters: [request.uploadId.value],
    );
    if (exists.isNotEmpty) {
      final retained = await _upload(actor, request.uploadId);
      if (retained.digest != request.digest || retained.bytes != request.bytes) {
        throw const FormatException('Upload is bound to another archive');
      }
    } else {
      if ((await _tx.execute(
        'SELECT id FROM $schema.import_preview WHERE id=\$1',
        parameters: [request.uploadId.value],
      )).isNotEmpty) {
        throw const FormatException('Upload identity is already reserved');
      }
      await _tx.execute(
        'INSERT INTO $schema.archive_upload VALUES(\$1,\$2,\$3,\$4)',
        parameters: [
          request.uploadId.value,
          actor.value,
          request.digest,
          request.bytes,
        ],
      );
    }
    return archiveUploadProgress(
      request,
      await _nextUploadOrdinal(request.uploadId),
    );
  });
  Future<CanonicalObject> writeArchiveChunk({
    required ProfileId actor,
    required WriteArchiveChunkEngineRequest request,
  }) => rollbackOnFailure(() async {
    final upload = await _upload(actor, request.uploadId);
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
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final existing = await _tx.execute(
      'SELECT content=\$3::bytea FROM $schema.archive_upload_chunk WHERE upload=\$1 AND ordinal=\$2',
      parameters: [request.uploadId.value, chunk.ordinal, chunk.content],
    );
    if (existing.isNotEmpty) {
      if (existing.single.single != true) {
        throw const FormatException(
          'Upload chunk retry changed retained bytes',
        );
      }
    } else {
      if (chunk.ordinal != await _nextUploadOrdinal(request.uploadId)) {
        throw const FormatException('Upload chunks must arrive in order');
      }
      await _tx.execute(
        'INSERT INTO $schema.archive_upload_chunk VALUES(\$1,\$2,\$3)',
        parameters: [request.uploadId.value, chunk.ordinal, chunk.content],
      );
    }
    return archiveUploadProgress(
      upload,
      await _nextUploadOrdinal(request.uploadId),
    );
  });
}
