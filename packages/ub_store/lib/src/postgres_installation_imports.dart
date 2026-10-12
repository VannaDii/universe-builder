part of 'postgres_installation_store.dart';

/// Exact private review and admission in the caller's installation transaction.
/// The archive is retained in bounded database chunks, independent of host paths.
extension PostgresInstallationImports on PostgresInstallationSession {
  String get _control => postgresAuthorityNamespace(authority.instanceId);

  Future<List<String>> importConflicts({
    required ProfileId actor,
    required UniverseId id,
    required String name,
  }) async {
    await authority.requireAuthor(actor);
    final rows = await _tx.execute(
      'SELECT EXISTS(SELECT 1 FROM $_control.catalog WHERE id=\$1), '
      'EXISTS(SELECT 1 FROM $_control.aliases WHERE key=\$2)',
      parameters: [id.value, selectorKey(name)],
    );
    return List.unmodifiable([
      if (rows.single[0] == true)
        'Universe identity already registered; choose a named clone',
      if (rows.single[1] == true) 'Universe name or alias is already reserved',
    ]);
  }

  Future<InstallationImportPreview> prepareImport({
    required ProfileId actor,
    required String source,
    required String name,
    required ImportMode mode,
  }) => rollbackOnFailure(() async {
    await authority.requireAuthor(actor);
    selectorKey(name);
    final temporary = Directory.systemTemp.createTempSync(
      'universe-builder-import-',
    );
    try {
      privateDirectory(temporary.path);
      final archive = OwnedSqliteDatabase.stageLogicalArchive(
        source,
        temporary.path,
      );
      try {
        final fields = WireFields(archive.manifest, {
          'format',
          'universe',
          'name',
          'complete',
          'omitted_records',
          'includes_history',
          'includes_workflow',
        });
        final sourceId = UniverseId.parse(fields.string('universe'));
        final target = mode == ImportMode.restore
            ? sourceId
            : UniverseId.generate();
        final staged = archive.reconstruct(
          temporary.path,
          target: target,
          name: name,
        );
        staged.close();
        final preview = InstallationImportPreview(
          id: OperationId.generate(),
          owner: actor,
          sourceDigest: archive.digest,
          target: target,
          source: sourceId,
          name: name,
          complete: fields.boolean('complete'),
          omittedRecords: int.parse(
            (fields.require('omitted_records') as CanonicalNumber).digits,
          ),
          records:
              archive.package.database
                      .select('SELECT count(*) AS n FROM record_identities')
                      .single['n']
                  as int,
          includesWorkflow: fields.boolean('includes_workflow'),
        );
        final path = '${temporary.path}/reviewed.sqlite';
        archive.persistReviewedSource(path);
        await _tx.execute(
          'INSERT INTO $_control.import_preview VALUES(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11)',
          parameters: [
            preview.id.value,
            actor.value,
            preview.sourceDigest,
            target.value,
            sourceId.value,
            postgresAuthoredText(name),
            preview.complete,
            preview.omittedRecords,
            preview.records,
            preview.includesWorkflow,
            preview.digest,
          ],
        );
        final input = File(path).openSync();
        try {
          var ordinal = 0, bytes = 0;
          while (true) {
            final chunk = input.readSync(262144);
            if (chunk.isEmpty) break;
            bytes += chunk.length;
            if (bytes > maxArchiveBytes) {
              throw const FormatException('Archive byte budget exceeded');
            }
            await _tx.execute(
              'INSERT INTO $_control.import_archive VALUES(\$1,\$2,\$3)',
              parameters: [preview.id.value, ordinal++, chunk],
            );
          }
        } finally {
          input.closeSync();
        }
        return preview;
      } finally {
        archive.close();
      }
    } finally {
      temporary.deleteSync(recursive: true);
    }
  });

  Future<InstallationImportPreview> loadImport({
    required ProfileId actor,
    required OperationId id,
    required String digest,
  }) async {
    await authority.requireAuthor(actor);
    final rows = await _tx.execute(
      'SELECT * FROM $_control.import_preview WHERE id=\$1 AND owner=\$2',
      parameters: [id.value, actor.value],
    );
    if (rows.isEmpty) {
      throw const NotFoundOrNotAccessibleError(message: 'import preview');
    }
    final row = rows.single.toColumnMap();
    final preview = InstallationImportPreview(
      id: OperationId.parse(row['id'] as String),
      owner: ProfileId.parse(row['owner'] as String),
      sourceDigest: row['source_digest'] as String,
      target: UniverseId.parse(row['target'] as String),
      source: UniverseId.parse(row['source'] as String),
      name: readPostgresAuthoredText(row['name'] as List<int>),
      complete: row['complete'] as bool,
      omittedRecords: row['omitted_records'] as int,
      records: row['records'] as int,
      includesWorkflow: row['includes_workflow'] as bool,
    );
    selectorKey(preview.name);
    if (preview.omittedRecords < 0 ||
        preview.records < 0 ||
        preview.digest != row['preview_digest']) {
      throw const FormatException('Import preview integrity mismatch');
    }
    if (preview.digest != digest) throw const ApprovalStaleError();
    return preview;
  }

  Future<CanonicalObject> acceptImport({
    required ProfileId actor,
    required OperationId id,
    required String digest,
  }) => rollbackOnFailure(() async {
    final preview = await loadImport(actor: actor, id: id, digest: digest);
    final receipt = preview.receipt;
    final key = 'logical-import-admission:${preview.id.value}';
    final catalog = await authority.catalog(actor, epochSeconds: BigInt.zero);
    if (catalog.any((entry) => entry.universeId == preview.target)) {
      await recoverUniverse(preview.target);
      final stored = await workflows(preview.target).get(key);
      if (stored?.toText() != receipt.toText()) {
        throw const PolicyDeniedError(
          message:
              'existing universe belongs to another import; choose a clone',
        );
      }
      return receipt;
    }
    if ((await importConflicts(
      actor: actor,
      id: preview.target,
      name: preview.name,
    )).isNotEmpty) {
      throw const NameUnavailableError(
        message: 'import identity or name is reserved',
      );
    }
    final temporary = Directory.systemTemp.createTempSync(
      'universe-builder-import-',
    );
    try {
      privateDirectory(temporary.path);
      final path = '${temporary.path}/reviewed.sqlite';
      protectedFile(path, createNew: true);
      final output = File(path).openSync(mode: FileMode.writeOnly);
      try {
        var ordinal = 0, bytes = 0;
        while (true) {
          final rows = await _tx.execute(
            'SELECT ordinal,content FROM $_control.import_archive WHERE preview_id=\$1 AND ordinal>=\$2 ORDER BY ordinal LIMIT 64',
            parameters: [id.value, ordinal],
          );
          if (rows.isEmpty) break;
          for (final row in rows) {
            final content = row[1] as List<int>;
            bytes += content.length;
            if (row[0] != ordinal++ ||
                content.isEmpty ||
                content.length > 262144 ||
                bytes > maxArchiveBytes) {
              throw const FormatException(
                'Reviewed archive chunk integrity mismatch',
              );
            }
            output.writeFromSync(content);
          }
        }
        output.flushSync();
      } finally {
        output.closeSync();
      }
      final archive = OwnedSqliteDatabase.stageLogicalArchive(
        path,
        temporary.path,
      );
      try {
        if (archive.digest != preview.sourceDigest) {
          throw const ApprovalStaleError();
        }
        await importUniverse(
          actor: actor,
          archive: archive,
          scratch: temporary.path,
          name: preview.name,
          clone: preview.target,
        );
        await workflows(preview.target).put(key, receipt);
        return receipt;
      } finally {
        archive.close();
      }
    } finally {
      temporary.deleteSync(recursive: true);
    }
  });
}
