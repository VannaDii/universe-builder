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
          'INSERT INTO $schema.move_stage VALUES(\$1,\$2,\$3)',
          parameters: [
            operation.value,
            archive.digest,
            archive.package.database
                .select('SELECT count(*) AS n FROM record_identities')
                .single['n'],
          ],
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

  Future<void> _moveAudit(
    ProfileId actor,
    String action,
    UniverseId universe,
  ) async {
    final schema = postgresAuthorityNamespace(authority.instanceId);
    await _tx.execute(
      'INSERT INTO $schema.audit SELECT COALESCE(MAX(sequence),0)+1,\$1,\$2,\$3 FROM $schema.audit',
      parameters: [actor.value, action, universe.value],
    );
  }

  Future<InstallationMoveReview> reviewMoveTarget({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required InstallationImportPreview preview,
  }) => rollbackOnFailure(() async {
    await _requireMoveBinding(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    selectorKey(preview.name);
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final stage = await _tx.execute(
      'SELECT digest,records FROM $schema.move_stage WHERE operation=\$1',
      parameters: [operation.value],
    );
    if (stage.length != 1 ||
        preview.source != universe ||
        preview.target != universe ||
        !preview.complete ||
        !preview.includesWorkflow ||
        preview.omittedRecords != 0 ||
        preview.sourceDigest != stage.single[0] ||
        preview.records != stage.single[1]) {
      throw const FormatException(
        'Target review does not match complete move archive',
      );
    }
    if ((await _tx.execute(
      'SELECT operation FROM $schema.move_review WHERE operation=\$1',
      parameters: [operation.value],
    )).isNotEmpty) {
      final retained = await loadMoveReview(
        actor: actor,
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
      );
      if (retained.preview.digest != preview.digest) {
        throw const FormatException('Move is bound to another target review');
      }
      return retained;
    }
    await _tx.execute(
      'INSERT INTO $schema.move_review VALUES(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8)',
      parameters: [
        operation.value,
        preview.id.value,
        preview.owner.value,
        postgresAuthoredText(preview.name),
        preview.sourceDigest,
        preview.records,
        preview.digest,
        'reviewed',
      ],
    );
    await _moveAudit(actor, 'review_move', universe);
    return loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
  });

  Future<InstallationMoveReview> loadMoveReview({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) async {
    await _requireMoveBinding(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT * FROM $schema.move_review WHERE operation=\$1',
      parameters: [operation.value],
    );
    if (rows.length != 1) {
      throw const NotFoundOrNotAccessibleError(message: 'move target review');
    }
    final row = rows.single.toColumnMap();
    final preview = InstallationImportPreview(
      id: OperationId.parse(row['preview_id'] as String),
      owner: ProfileId.parse(row['owner'] as String),
      sourceDigest: row['source_digest'] as String,
      source: universe,
      target: universe,
      name: readPostgresAuthoredText(row['name'] as List<int>),
      complete: true,
      includesWorkflow: true,
      omittedRecords: 0,
      records: row['records'] as int,
    );
    selectorKey(preview.name);
    if (preview.digest != row['preview_digest']) {
      throw const FormatException('Retained move review integrity mismatch');
    }
    return InstallationMoveReview(
      operation: operation,
      universe: universe,
      targetInstance: targetInstance,
      preview: preview,
      state: MoveAdmissionState.values.byName(row['state'] as String),
    );
  }

  /// Commit before invoking the target. An uncertain result must be recovered
  /// through this exact retained target review, never by resuming the source.
  Future<InstallationMoveReview> beginMoveAdmission({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) => rollbackOnFailure(() async {
    final review = await loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    if (review.state == MoveAdmissionState.reviewed) {
      final schema = postgresAuthorityNamespace(authority.instanceId);
      await _tx.execute(
        "UPDATE $schema.move_review SET state='admitting' WHERE operation=\$1",
        parameters: [operation.value],
      );
      await _moveAudit(actor, 'begin_move_admission', universe);
    }
    return loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
  });

  /// Trusted coordinator only: use the authenticated target's exact receipt.
  /// Successful cutover keeps the original source suspended and retained.
  Future<InstallationMoveReview> recordMoveAdmission({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required CanonicalObject receipt,
  }) => rollbackOnFailure(() async {
    final review = await loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    if (review.state == MoveAdmissionState.reviewed) {
      throw StateError('Record admission attempt before invoking the target');
    }
    if (review.preview.receipt.toText() != receipt.toText()) {
      throw const FormatException(
        'Target receipt does not match retained move review',
      );
    }
    if (review.state != MoveAdmissionState.admitted) {
      final schema = postgresAuthorityNamespace(authority.instanceId);
      await _tx.execute(
        "UPDATE $schema.move_review SET state='admitted' WHERE operation=\$1",
        parameters: [operation.value],
      );
      await _moveAudit(actor, 'complete_move_admission', universe);
    }
    return loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
  });
  Future<CanonicalObject> listMoves({
    required ProfileId actor,
    OperationId? after,
    int limit = 100,
  }) async {
    await authority.requireAuthor(actor);
    ListMovesEngineRequest(after: after, limit: limit).validate();
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT m.universe,m.operation,m.target_instance,c.name,r.state FROM $schema.move_quiescence m '
      'JOIN $schema.catalog c ON c.id=m.universe LEFT JOIN $schema.move_review r ON r.operation=m.operation '
      'WHERE (\$1::text IS NULL OR m.operation>\$1) ORDER BY m.operation LIMIT \$2',
      parameters: [after?.value, limit + 1],
    );
    final page = rows.take(limit).map((row) => row.toColumnMap()).toList();
    return CanonicalObject([
      MapEntry('source_instance', CanonicalString(authority.instanceId.value)),
      MapEntry(
        'moves',
        CanonicalArray(
          page.map(
            (row) => CanonicalObject([
              MapEntry(
                'universe_id',
                CanonicalString(
                  UniverseId.parse(row['universe'] as String).value,
                ),
              ),
              MapEntry(
                'operation_id',
                CanonicalString(
                  OperationId.parse(row['operation'] as String).value,
                ),
              ),
              MapEntry(
                'target_instance',
                CanonicalString(
                  OperationId.parse(row['target_instance'] as String).value,
                ),
              ),
              MapEntry(
                'name',
                CanonicalString(
                  readPostgresAuthoredText(row['name'] as List<int>),
                ),
              ),
              MapEntry(
                'state',
                CanonicalString(
                  row['state'] == null
                      ? 'suspended'
                      : MoveAdmissionState.values
                            .byName(row['state'] as String)
                            .name,
                ),
              ),
            ]),
          ),
        ),
      ),
      MapEntry(
        'next_after',
        rows.length > limit
            ? CanonicalString(page.last['operation'] as String)
            : const CanonicalNull(),
      ),
    ]);
  }

  Future<CanonicalObject> getMove({
    required ProfileId actor,
    required OperationId operation,
  }) async {
    await authority.requireAuthor(actor);
    final schema = postgresAuthorityNamespace(authority.instanceId);
    final rows = await _tx.execute(
      'SELECT m.universe,m.target_instance,c.name,r.state FROM $schema.move_quiescence m '
      'JOIN $schema.catalog c ON c.id=m.universe LEFT JOIN $schema.move_review r ON r.operation=m.operation WHERE m.operation=\$1',
      parameters: [operation.value],
    );
    if (rows.length != 1) {
      throw const NotFoundOrNotAccessibleError(message: 'move');
    }
    final row = rows.single.toColumnMap();
    final universe = UniverseId.parse(row['universe'] as String);
    final target = OperationId.parse(row['target_instance'] as String);
    final review = row['state'] == null
        ? null
        : await loadMoveReview(
            actor: actor,
            universe: universe,
            operation: operation,
            targetInstance: target,
          );
    return moveRecoveryReport(
      sourceInstance: authority.instanceId,
      universe: universe,
      operation: operation,
      targetInstance: target,
      name: readPostgresAuthoredText(row['name'] as List<int>),
      review: review,
    );
  }
}
