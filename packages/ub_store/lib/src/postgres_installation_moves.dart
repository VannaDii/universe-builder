part of 'postgres_installation_store.dart';

/// Source move artifacts belong to current installation authority. They never
/// become a universe export's installation credentials or imported permissions.
extension PostgresInstallationMoves on PostgresInstallationSession {
  Future<void> _requireMoveBinding({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) async {
    await authority.requireAuthor(actor);
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT universe FROM $schema.move_quiescence WHERE universe=\$1 AND operation=\$2 AND target_instance=\$3',
      parameters: [universe.value, operation.value, targetInstance.value],
    );
    if (rows.length != 1) {
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  void _verifyMoveManifest(
    VerifiedLogicalArchive archive,
    UniverseId universe,
  ) {
    final fields = WireFields(archive.manifest, {
      'format',
      'universe',
      'name',
      'complete',
      'omitted_records',
      'includes_history',
      'includes_workflow',
    });
    if (UniverseId.parse(fields.string('universe')) != universe ||
        !fields.boolean('complete') ||
        !fields.boolean('includes_history') ||
        !fields.boolean('includes_workflow') ||
        (fields.require('omitted_records') as CanonicalNumber).digits != '0') {
      throw const FormatException('Move requires complete source history');
    }
  }

  Future<void> prepareMoveArchive({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) => rollbackOnFailure(() async {
    await _requireMoveBinding(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    final schema = postgresAuthorityNamespace(authority.instanceId);
    if ((await _tx.execute(
      'SELECT operation FROM $schema.move_stage WHERE operation=\$1',
      parameters: [operation.value],
    )).isNotEmpty) {
      return;
    }
    final temporary = Directory.systemTemp.createTempSync(
      'universe-builder-move-',
    );
    try {
      privateDirectory(temporary.path);
      final path = '${temporary.path}/archive.sqlite';
      await exportUniverse(universe, path, completeHistory: true);
      final archive = OwnedSqliteDatabase.stageLogicalArchive(
        path,
        temporary.path,
      );
      try {
        _verifyMoveManifest(archive, universe);
        await _tx.execute(
          'INSERT INTO $schema.move_stage VALUES(\$1,\$2)',
          parameters: [operation.value, archive.digest],
        );
      } finally {
        archive.close();
      }
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
            'INSERT INTO $schema.move_archive VALUES(\$1,\$2,\$3)',
            parameters: [operation.value, ordinal++, chunk],
          );
        }
      } finally {
        input.closeSync();
      }
    } finally {
      temporary.deleteSync(recursive: true);
    }
  });

  /// Recover the same verified archive into a protected transport file. A failed
  /// destination publish never removes the database's committed source stage.
  Future<({String path, String digest, CanonicalObject manifest})>
  writeMoveArchive({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required String destination,
  }) async {
    await _requireMoveBinding(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT digest FROM $schema.move_stage WHERE operation=\$1',
      parameters: [operation.value],
    );
    if (rows.length != 1) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
    final digest = rows.single.single as String;
    final temporary = Directory.systemTemp.createTempSync(
      'universe-builder-move-copy-',
    );
    try {
      privateDirectory(temporary.path);
      final path = '${temporary.path}/archive.sqlite';
      protectedFile(path, createNew: true);
      final output = File(path).openSync(mode: FileMode.writeOnly);
      try {
        var ordinal = 0, bytes = 0;
        while (true) {
          final chunks = await _tx.execute(
            'SELECT ordinal,content FROM $schema.move_archive WHERE operation=\$1 AND ordinal>=\$2 ORDER BY ordinal LIMIT 64',
            parameters: [operation.value, ordinal],
          );
          if (chunks.isEmpty) break;
          for (final row in chunks) {
            final content = row[1] as List<int>;
            bytes += content.length;
            if (row[0] != ordinal++ ||
                content.isEmpty ||
                content.length > 262144 ||
                bytes > maxArchiveBytes) {
              throw const FormatException(
                'Retained move chunk integrity mismatch',
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
        _verifyMoveManifest(archive, universe);
        if (archive.digest != digest) throw const ApprovalStaleError();
        final target = File(destination).absolute.path;
        if (FileSystemEntity.typeSync(target, followLinks: false) ==
            FileSystemEntityType.notFound) {
          archive.persistReviewedSource(target);
        } else {
          protectedFile(target);
          final retained = OwnedSqliteDatabase.stageLogicalArchive(
            target,
            temporary.path,
          );
          try {
            if (retained.digest != digest) throw const ApprovalStaleError();
          } finally {
            retained.close();
          }
        }
        return (path: target, digest: digest, manifest: archive.manifest);
      } finally {
        archive.close();
      }
    } finally {
      temporary.deleteSync(recursive: true);
    }
  }
}
