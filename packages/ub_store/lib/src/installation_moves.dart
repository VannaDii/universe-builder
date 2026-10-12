part of 'installation_store.dart';

enum MoveAdmissionState { reviewed, admitting, admitted }

/// Exact target review retained by the source coordinator. Target permissions
/// and credentials remain solely in the target installation.
final class InstallationMoveReview {
  const InstallationMoveReview({
    required this.operation,
    required this.universe,
    required this.targetInstance,
    required this.preview,
    required this.state,
  });
  final OperationId operation, targetInstance;
  final UniverseId universe;
  final InstallationImportPreview preview;
  final MoveAdmissionState state;
  AcceptImportEngineRequest get acceptRequest =>
      AcceptImportEngineRequest(previewId: preview.id, digest: preview.digest);
}

extension InstallationMoves on SqliteInstallationStore {
  InstallationMoveReview reviewMoveTarget({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required InstallationImportPreview preview,
  }) {
    final source = moveSource(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    final archive = OwnedSqliteDatabase.stageLogicalArchive(
      source.archivePath,
      File(source.archivePath).parent.path,
    );
    try {
      selectorKey(preview.name);
      if (preview.source != universe ||
          preview.target != universe ||
          !preview.complete ||
          !preview.includesWorkflow ||
          preview.omittedRecords != 0 ||
          preview.sourceDigest != archive.digest ||
          preview.records !=
              archive.package.database
                  .select('SELECT count(*) AS n FROM record_identities')
                  .single['n']) {
        throw const FormatException(
          'Target review does not match complete move archive',
        );
      }
    } finally {
      archive.close();
    }
    final existing = _db.select(
      'SELECT operation FROM move_review WHERE operation=?',
      [operation.value],
    );
    if (existing.isNotEmpty) {
      final retained = loadMoveReview(
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
    _transaction(() {
      requireAuthor(actor);
      _db.execute('INSERT INTO move_review VALUES(?,?,?,?,?,?,?,?)', [
        operation.value,
        preview.id.value,
        preview.owner.value,
        preview.name,
        preview.sourceDigest,
        preview.records,
        preview.digest,
        'reviewed',
      ]);
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'review_move',?)",
        [actor.value, universe.value],
      );
    });
    return loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
  }

  InstallationMoveReview loadMoveReview({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) {
    moveSource(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    final rows = _db.select('SELECT * FROM move_review WHERE operation=?', [
      operation.value,
    ]);
    if (rows.length != 1) {
      throw const NotFoundOrNotAccessibleError(message: 'move target review');
    }
    final row = rows.single;
    final preview = InstallationImportPreview(
      id: OperationId.parse(row['preview_id'] as String),
      owner: ProfileId.parse(row['owner'] as String),
      sourceDigest: row['source_digest'] as String,
      source: universe,
      target: universe,
      name: row['name'] as String,
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

  /// Commit before invoking target admission. This state means the target may
  /// have admitted, so recovery must retry the exact target review.
  InstallationMoveReview beginMoveAdmission({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) {
    final review = loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
    if (review.state == MoveAdmissionState.reviewed) {
      _transaction(() {
        requireAuthor(actor);
        _db.execute(
          "UPDATE move_review SET state='admitting' WHERE operation=?",
          [operation.value],
        );
        _db.execute(
          "INSERT INTO audit(actor,action,target) VALUES(?,'begin_move_admission',?)",
          [actor.value, universe.value],
        );
      });
    }
    return loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
  }

  /// Trusted coordinator only: supply the authenticated target's exact receipt.
  /// The original remains retained and suspended after successful cutover.
  InstallationMoveReview recordMoveAdmission({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required CanonicalObject receipt,
  }) {
    final review = loadMoveReview(
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
      _transaction(() {
        requireAuthor(actor);
        _db.execute(
          "UPDATE move_review SET state='admitted' WHERE operation=?",
          [operation.value],
        );
        _db.execute(
          "INSERT INTO audit(actor,action,target) VALUES(?,'complete_move_admission',?)",
          [actor.value, universe.value],
        );
      });
    }
    return loadMoveReview(
      actor: actor,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    );
  }
}
