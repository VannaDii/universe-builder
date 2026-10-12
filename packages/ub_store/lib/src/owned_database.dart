import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart' show WireFields;
import 'package:ub_domain/ub_domain.dart';

import 'canonical_integrity.dart';
import 'archive_checksum.dart';
import 'archive_reconstruction.dart';
import 'archive_selection.dart';
import 'archive_schema.g.dart';
import 'database.dart';
import 'journal.dart';
import 'ownership.dart';
import 'projection_recovery.dart';
import 'restore_copy.dart';
import 'relational.dart';
import 'workflow_storage.dart';

/// Internal connection lifetime boundary. Existing initialized packages must
/// complete recover() before serving calls; client authorization remains in
/// the service boundary.
final class OwnedSqliteDatabase {
  OwnedSqliteDatabase._(this._database, this._lock, this.path) {
    _connectionLocks[_database] = _lock;
  }
  // Internal journal helpers retain the connection. Its native ownership must
  // survive too, even if the session wrapper is no longer referenced.
  static final _connectionLocks = Expando<OwnedFileLock>();
  final Database _database;
  final OwnedFileLock _lock;
  final String path;
  bool _closed = false;

  static OwnedSqliteDatabase create(String path) => _open(path, create: true);
  static OwnedSqliteDatabase openExisting(String path) =>
      _open(path, create: false);

  /// Only for a newly published copy whose catalog registration has failed.
  /// The caller closes its owned connection before removing these files.
  static void removeUnregisteredPackage(String path) {
    final file = File(path).absolute;
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    for (final owned in [
      file.path,
      '${file.path}-wal',
      '${file.path}-shm',
      '${file.parent.path}/$stem.writer.lock',
    ]) {
      final target = File(owned);
      if (target.existsSync()) target.deleteSync();
    }
    syncPrivateDirectory(file.parent.path);
  }

  /// Protected, unpublished restore staging. The caller retains current author
  /// authority and closes the stage after registration or failure.
  static StagedSqliteRestore stageRestore(String source, String scratch) {
    protectedFile(source);
    if (File(source).lengthSync() > maxPackageBytes) {
      throw const FormatException('Restore package exceeds 8 GiB limit');
    }
    final parent = privateDirectory(scratch);
    final temporary = Directory(parent).createTempSync('.restore-');
    OwnedSqliteDatabase? package;
    try {
      privateDirectory(temporary.path);
      package = create('${temporary.path}/package.sqlite');
      copyRestoreRows(source, package.database);
      package.recover();
      CanonicalIntegrity(SqliteJournal(package.database, package.universeId))
          .verifyComplete();
      return StagedSqliteRestore._(package, temporary);
    } on Object {
      try {
        package?.close();
      } finally {
        temporary.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  static OwnedSqliteDatabase _open(String path, {required bool create}) {
    final file = File(path).absolute;
    if (!create &&
        FileSystemEntity.typeSync(file.parent.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Existing package directory absent',
        file.parent.path,
      );
    }
    final directory = privateDirectory(file.parent.path);
    final name = file.path.substring(file.parent.path.length + 1);
    final actualPath = '$directory/$name';
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final lock = OwnedFileLock.acquire('$directory/$stem.writer.lock');
    try {
      protectedFile(actualPath, createNew: create);
      return OwnedSqliteDatabase._(
        SqliteDatabase.open(actualPath, existing: true),
        lock,
        actualPath,
      );
    } catch (_) {
      lock.close();
      rethrow;
    }
  }

  Database get database {
    if (_closed) throw StateError('Owned SQLite connection is closed');
    return _database;
  }

  /// Required before service startup exposes an existing initialized package.
  /// Retained evidence is checked first; disposable indexes never admit canon.
  void recover() {
    final journal = SqliteJournal(database, universeId);
    CanonicalIntegrity(journal).verify();
    ProjectionRecovery(journal).rebuild();
  }

  UniverseId get universeId {
    final rows = database.select('SELECT id FROM universes');
    if (rows.length != 1) {
      throw const FormatException('Missing or ambiguous package universe');
    }
    return UniverseId.parse(rows.single['id'] as String);
  }

  /// Storage settings from the owned connection; this is not a fresh integrity
  /// check. Existing packages complete recovery before runtime exposure.
  CanonicalObject storageStatus() => CanonicalObject([
    MapEntry('universe', CanonicalString(universeId.value)),
    MapEntry(
      'sqlite_version',
      CanonicalString(
        database.select('SELECT sqlite_version() AS version').single['version']
            as String,
      ),
    ),
    MapEntry(
      'journal_mode',
      CanonicalString(
        database.select('PRAGMA journal_mode').single.values.single as String,
      ),
    ),
    MapEntry(
      'synchronous',
      CanonicalNumber(
        (database.select('PRAGMA synchronous').single.values.single as int)
            .toString(),
      ),
    ),
    MapEntry(
      'foreign_keys',
      CanonicalBool(
        database.select('PRAGMA foreign_keys').single.values.single == 1,
      ),
    ),
    MapEntry(
      'heads',
      CanonicalArray(
        SqliteJournal(database, universeId).heads().entries.map(
          (head) => CanonicalArray([
            CanonicalString(head.key.value),
            CanonicalString(head.value.value),
          ]),
        ),
      ),
    ),
  ]);

  /// A consistent verified SQLite snapshot, published without overwriting an
  /// existing destination. All staged content and immutable history are retained.
  void backup(String destination) {
    if (!database.autocommit) {
      throw StateError('Backup requires no active transaction');
    }
    final target = File(destination).absolute;
    final temporary = target.parent.createTempSync('.universe-backup-');
    try {
      privateDirectory(temporary.path);
      final copyPath = '${temporary.path}/package.sqlite';
      protectedFile(copyPath, createNew: true);
      database.execute('VACUUM INTO ?', [copyPath]);
      if (File(copyPath).lengthSync() > maxPackageBytes) {
        throw const FormatException(
          'Backup exceeds restore budget; original is unchanged',
        );
      }
      final copy = sqlite3.open(copyPath, mode: OpenMode.readOnly);
      try {
        final checks = copy.select('PRAGMA integrity_check');
        if (checks.length != 1 || checks.single.values.single != 'ok') {
          throw const FormatException('Backup integrity failure');
        }
        CanonicalIntegrity(SqliteJournal(copy, universeId)).verifyComplete();
      } finally {
        copy.close();
      }
      publishSnapshot(copyPath, target.path);
    } finally {
      temporary.deleteSync(recursive: true);
    }
  }

  /// Whole-package impact, bound to the exact retained heads and history counts.
  CanonicalObject purgePreview() {
    final db = database;
    if (!db.autocommit) {
      throw StateError('Purge preview requires no active transaction');
    }
    db.execute('BEGIN');
    try {
      CanonicalNumber count(String table) => CanonicalNumber(
        db.select('SELECT count(*) AS n FROM $table').single['n'].toString(),
      );
      final impact = CanonicalObject([
        MapEntry('universe_id', CanonicalString(universeId.value)),
        MapEntry(
          'heads',
          CanonicalArray(
            SqliteJournal(db, universeId).heads().entries.map(
              (head) => CanonicalArray([
                CanonicalString(head.key.value),
                CanonicalString(head.value.value),
              ]),
            ),
          ),
        ),
        MapEntry('revisions', count('commits')),
        MapEntry('record_versions', count('record_versions')),
        MapEntry('workflow_entries', count('workflow_index')),
        MapEntry('commit_receipts', count('operation_receipts')),
        MapEntry(
          'scope',
          CanonicalString(
            'entire registered universe package: all continuities, history, sources, images, drafts, approvals and operation logs',
          ),
        ),
        MapEntry(
          'retained',
          CanonicalString(
            'installation audit records only the universe identity and purge action; external backups, exports, client transcripts and filesystem snapshots remain outside this operation',
          ),
        ),
        MapEntry(
          'erasure',
          CanonicalString(
            'removes owned package files; does not promise forensic erasure',
          ),
        ),
      ]);
      final preview = CanonicalObject([
        MapEntry('digest', CanonicalString(canonicalDigest(impact))),
        MapEntry('impact', impact),
      ]);
      db.execute('COMMIT');
      return preview;
    } on Object {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Complete retained history and editorial evidence in the existing logical
  /// archive format. Filtered/canon-only reconstruction uses a separate path.
  CanonicalObject exportCompleteHistory(String destination) =>
      _exportLogical(destination, completeHistory: true);

  /// All factual records and revision history, excluding editorial workflow
  /// and uncommitted assets. Dependency-filtered selection is a separate path.
  CanonicalObject exportCanonOnly(String destination) =>
      _exportLogical(destination, completeHistory: false);

  CanonicalObject exportLogical(
    String destination, {
    Iterable<RecordId> recordIds = const [],
    bool completeHistory = false,
  }) {
    final requested = recordIds.toList();
    if (completeHistory && requested.isNotEmpty) {
      throw const FormatException(
        'Complete-history export requires all records',
      );
    }
    return _exportLogical(
      destination,
      completeHistory: completeHistory,
      requested: requested,
    );
  }

  CanonicalObject _exportLogical(
    String destination, {
    required bool completeHistory,
    List<RecordId> requested = const [],
  }) {
    final target = File(destination).absolute;
    final temporary = target.parent.createTempSync('.relational-export-');
    try {
      privateDirectory(temporary.path);
      final snapshotPath = '${temporary.path}/snapshot.sqlite';
      backup(snapshotPath);
      final snapshot = OwnedSqliteDatabase.openExisting(snapshotPath);
      final archivePath = '${temporary.path}/export.sqlite';
      OwnedSqliteDatabase? archive;
      late CanonicalObject manifest;
      try {
        archive = create(archivePath);
        final selected = requested.isEmpty
            ? null
            : archiveSelection(
                snapshot.database,
                snapshot.universeId,
                requested,
              );
        final total =
            snapshot.database
                    .select(
                      'SELECT count(DISTINCT record_id) AS n FROM record_versions',
                    )
                    .single['n']
                as int;
        final omitted = selected == null ? 0 : total - selected.length;
        manifest = CanonicalObject([
          MapEntry('format', CanonicalString('universe-relational')),
          MapEntry('universe', CanonicalString(snapshot.universeId.value)),
          MapEntry(
            'name',
            CanonicalString(
              snapshot.database
                      .select('SELECT name FROM universes')
                      .single['name']
                  as String,
            ),
          ),
          MapEntry('complete', CanonicalBool(omitted == 0)),
          MapEntry('omitted_records', CanonicalNumber('$omitted')),
          const MapEntry('includes_history', CanonicalBool(true)),
          MapEntry('includes_workflow', CanonicalBool(completeHistory)),
        ]);
        if (completeHistory) {
          copyTrustedPackageRows(snapshotPath, archive.database);
        } else {
          reconstructArchive(
            snapshot.database,
            archive.database,
            manifest: manifest,
            digest: '',
            target: snapshot.universeId,
            name:
                snapshot.database
                        .select('SELECT name FROM universes')
                        .single['name']
                    as String,
            included: selected,
          );
          archive.recover();
          CanonicalIntegrity(
            SqliteJournal(archive.database, archive.universeId),
          ).verifyComplete();
        }
        final db = archive.database;
        db.execute(archiveSchema);
        db.execute('BEGIN IMMEDIATE');
        try {
          final row = RelationalCodec(db).put('ArchiveManifest', manifest);
          final checksum = archiveChecksum(db);
          db.execute(
            "INSERT INTO archive_integrity VALUES(1,?,'typed-row-stream',?,?,'historical_evidence_only',?)",
            [row, checksum.digest, checksum.rows, canonicalDigest(manifest)],
          );
          db.execute('COMMIT');
        } on Object {
          if (!db.autocommit) db.execute('ROLLBACK');
          rethrow;
        }
        db.execute(
          'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;',
        );
      } finally {
        archive?.close();
        snapshot.close();
      }
      if (File(archivePath).lengthSync() > maxArchiveBytes) {
        throw const FormatException('Archive byte budget exceeded');
      }
      final verified = stageLogicalArchive(archivePath, temporary.path);
      verified.close();
      publishSnapshot(archivePath, target.path);
      return manifest;
    } finally {
      temporary.deleteSync(recursive: true);
    }
  }

  /// Bound raw input copying before SQLite is opened, then stream rows into
  /// generated trusted schema. No SQL supplied by the archive is installed.
  static VerifiedLogicalArchive stageLogicalArchive(
    String source,
    String scratch,
  ) {
    protectedFile(source);
    if (File(source).lengthSync() > maxArchiveBytes) {
      throw const FormatException('Logical archive exceeds 512 MiB');
    }
    final parent = privateDirectory(scratch);
    final temporary = Directory(parent).createTempSync('.logical-archive-');
    OwnedSqliteDatabase? package;
    try {
      privateDirectory(temporary.path);
      final snapshot = '${temporary.path}/input.sqlite';
      protectedFile(snapshot, createNew: true);
      final input = File(source).openSync();
      try {
        final output = File(snapshot).openSync(mode: FileMode.writeOnly);
        try {
          var copied = 0;
          while (true) {
            final chunk = input.readSync(65536);
            if (chunk.isEmpty) break;
            copied += chunk.length;
            if (copied > maxArchiveBytes) {
              throw const FormatException('Logical archive exceeds 512 MiB');
            }
            output.writeFromSync(chunk);
          }
          output.flushSync();
        } finally {
          output.closeSync();
        }
      } finally {
        input.closeSync();
      }
      package = create('${temporary.path}/package.sqlite');
      final db = package.database;
      db.execute(archiveSchema);
      copyTrustedPackageRows(snapshot, db, archive: true);
      final headers = db.select(
        'SELECT manifest_row,checksum_recipe,sha256,row_count,authority_state,manifest_sha256 FROM archive_integrity WHERE singleton=1',
      );
      if (headers.length != 1) {
        throw const FormatException('Invalid archive integrity header');
      }
      final header = headers.single;
      final checksum = archiveChecksum(db);
      if (header['checksum_recipe'] != 'typed-row-stream' ||
          header['sha256'] != checksum.digest ||
          header['row_count'] != checksum.rows ||
          header['authority_state'] != 'historical_evidence_only') {
        throw const FormatException('Archive checksum mismatch');
      }
      final manifest = RelationalCodec(db)
          .get('ArchiveManifest', header['manifest_row']);
      if (db
                  .select('SELECT count(*) AS n FROM r_archive_manifest')
                  .single['n'] !=
              1 ||
          canonicalDigest(manifest) != header['manifest_sha256']) {
        throw const FormatException('Archive manifest checksum mismatch');
      }
      final fields = WireFields(manifest, {
        'format',
        'universe',
        'name',
        'complete',
        'omitted_records',
        'includes_history',
        'includes_workflow',
      });
      final id = UniverseId.parse(fields.string('universe'));
      selectorKey(fields.string('name'));
      if (fields.string('format') != 'universe-relational' ||
          !fields.boolean('includes_history') ||
          fields.boolean('complete') !=
              (fields.u64('omitted_records') == BigInt.zero) ||
          (fields.boolean('includes_workflow') &&
              !fields.boolean('complete')) ||
          id != package.universeId) {
        throw const FormatException('Inconsistent relational archive manifest');
      }
      if (!fields.boolean('includes_workflow')) {
        for (final table in [
          'workflow_entries',
          'operation_receipts',
          'historical_workflow',
          'historical_receipt',
        ]) {
          if (db.select('SELECT count(*) AS n FROM $table').single['n'] != 0) {
            throw const FormatException(
              'Canon-only archive contains workflow evidence',
            );
          }
        }
      }
      package.recover();
      CanonicalIntegrity(SqliteJournal(db, id)).verifyComplete();
      return VerifiedLogicalArchive._(
        package,
        manifest as CanonicalObject,
        archiveReviewDigest(
          checksum.digest,
          header['manifest_sha256'] as String,
        ),
        temporary,
      );
    } on Object {
      try {
        package?.close();
      } finally {
        temporary.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  void preparePurge(String expectedDigest) {
    final preview = WireFields(purgePreview(), {'digest', 'impact'});
    if (preview.string('digest') != expectedDigest) {
      throw const FormatException(
        'purge preview is stale; review current impact',
      );
    }
    database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  /// Retain all author history and evidence. Only disposable snapshot caches
  /// may be collected while this connection retains sole writer ownership.
  CanonicalObject maintain({required bool collect}) {
    if (!database.autocommit) {
      throw StateError('Maintenance owns its transaction');
    }
    final journal = SqliteJournal(database, universeId);
    CanonicalIntegrity(journal).verify();
    int count(String table) =>
        database.select('SELECT count(*) AS total FROM $table').single['total']
            as int;
    final versions = count('record_versions');
    final revisions = count('commits');
    final receipts = count('operation_receipts');
    final workflows = count('workflow_index');
    final sources = count('source_content');
    final caches = count('snapshot_membership');
    if (collect) {
      database.execute('BEGIN IMMEDIATE');
      try {
        database.execute('DELETE FROM snapshot_member');
        database.execute('DELETE FROM snapshot_membership');
        database.execute('COMMIT');
      } on Object {
        if (!database.autocommit) {
          database.execute('ROLLBACK');
        }
        rethrow;
      }
      database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      database.execute('VACUUM');
      CanonicalIntegrity(journal).verify();
    }
    return CanonicalObject([
      MapEntry('retention_policy', CanonicalString('retain-all-history-v1')),
      MapEntry(
        'retained_record_versions',
        CanonicalNumber(versions.toString()),
      ),
      MapEntry('retained_revisions', CanonicalNumber(revisions.toString())),
      MapEntry(
        'retained_commit_receipts',
        CanonicalNumber(receipts.toString()),
      ),
      MapEntry(
        'retained_workflow_entries',
        CanonicalNumber(workflows.toString()),
      ),
      MapEntry('retained_source_assets', CanonicalNumber(sources.toString())),
      MapEntry('eligible_snapshot_caches', CanonicalNumber(caches.toString())),
      MapEntry(
        'collected_snapshot_caches',
        CanonicalNumber((collect ? caches : 0).toString()),
      ),
      const MapEntry('source_assets_collected', CanonicalNumber('0')),
      MapEntry(
        'backup_pins',
        CanonicalString(
          'source bytes are embedded in each complete SQLite snapshot',
        ),
      ),
      const MapEntry('canonical', CanonicalBool(false)),
    ]);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _database.close();
    } finally {
      _connectionLocks[_database] = null;
      _lock.close();
    }
  }
}

/// Owns only a disposable unpublished copy, never the original restore source.
final class StagedSqliteRestore {
  StagedSqliteRestore._(this.package, this._temporary);
  final OwnedSqliteDatabase package;
  final Directory _temporary;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      package.close();
    } finally {
      _temporary.deleteSync(recursive: true);
    }
  }
}

/// Verified disposable archive data. Imported workflow remains evidence until
/// the separate admission path marks it historical in a fresh target package.
final class VerifiedLogicalArchive {
  VerifiedLogicalArchive._(
    this.package,
    this.manifest,
    this.digest,
    this._temporary,
  );
  final OwnedSqliteDatabase package;
  final CanonicalObject manifest;
  final String digest;
  final Directory _temporary;
  bool _closed = false;

  /// Persist the exact bounded input snapshot reviewed by this reader, without
  /// replacing an existing path. Its SQL is never installed into owned storage.
  void persistReviewedSource(String destination) {
    if (_closed) throw StateError('Verified archive is closed');
    publishSnapshot('${_temporary.path}/input.sqlite', destination);
  }

  /// Reconstruct canon-only history or a named clone with remapped canonical
  /// references. Original editorial evidence retains its original bindings.
  StagedSqliteRestore reconstruct(
    String scratch, {
    required UniverseId target,
    required String name,
  }) {
    if (_closed) throw StateError('Verified archive is closed');
    selectorKey(name);
    final fields = WireFields(manifest, {
      'format',
      'universe',
      'name',
      'complete',
      'omitted_records',
      'includes_history',
      'includes_workflow',
    });
    if (!fields.boolean('complete') &&
        target.value == fields.string('universe')) {
      throw const FormatException(
        'Filtered archives require an explicitly named clone',
      );
    }
    final parent = privateDirectory(scratch);
    final temporary = Directory(parent).createTempSync('.logical-import-');
    OwnedSqliteDatabase? output;
    try {
      privateDirectory(temporary.path);
      output = OwnedSqliteDatabase.create('${temporary.path}/package.sqlite');
      reconstructArchive(
        package.database,
        output.database,
        manifest: manifest,
        digest: digest,
        target: target,
        name: name,
      );
      output.recover();
      CanonicalIntegrity(SqliteJournal(output.database, target))
          .verifyComplete();
      return StagedSqliteRestore._(output, temporary);
    } on Object {
      try {
        output?.close();
      } finally {
        temporary.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  /// Stage a complete retained-history identity-preserving import. Canon-only
  /// and clone reconstruction are separate paths; installation authority is absent.
  StagedSqliteRestore stageRestore(String scratch, {required String name}) {
    if (_closed) throw StateError('Verified archive is closed');
    selectorKey(name);
    final fields = WireFields(manifest, {
      'format',
      'universe',
      'name',
      'complete',
      'omitted_records',
      'includes_history',
      'includes_workflow',
    });
    if (!fields.boolean('complete')) {
      throw const FormatException(
        'Filtered archives require an explicitly named clone',
      );
    }
    if (!fields.boolean('includes_workflow')) {
      throw const FormatException('Canon-only archives require reconstruction');
    }
    final source = UniverseId.parse(fields.string('universe'));
    final parent = privateDirectory(scratch);
    final temporary = Directory(parent).createTempSync('.logical-import-');
    OwnedSqliteDatabase? target;
    try {
      privateDirectory(temporary.path);
      target = OwnedSqliteDatabase.create('${temporary.path}/package.sqlite');
      copyTrustedRows(
        package.database,
        target.database,
        historicalEvidence: true,
      );
      target.database.execute('BEGIN IMMEDIATE');
      try {
        target.database.execute('UPDATE universes SET name=?', [name]);
        WorkflowStorage(target.database).put(
          'logical-import-origin:$digest',
          CanonicalObject([
            MapEntry('digest', CanonicalString(digest)),
            MapEntry('source_universe', CanonicalString(source.value)),
            MapEntry('target_universe', CanonicalString(source.value)),
            const MapEntry('complete', CanonicalBool(true)),
            const MapEntry('omitted_records', CanonicalNumber('0')),
          ]),
        );
        target.database.execute('COMMIT');
      } on Object {
        if (!target.database.autocommit) target.database.execute('ROLLBACK');
        rethrow;
      }
      if (target.universeId != source) {
        throw const FormatException('Archive universe mismatch');
      }
      target.recover();
      CanonicalIntegrity(SqliteJournal(target.database, source))
          .verifyComplete();
      return StagedSqliteRestore._(target, temporary);
    } on Object {
      try {
        target?.close();
      } finally {
        temporary.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      package.close();
    } finally {
      _temporary.deleteSync(recursive: true);
    }
  }
}
