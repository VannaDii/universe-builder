import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'canonical_integrity.dart';
import 'database.dart';
import 'journal.dart';
import 'ownership.dart';
import 'projection_recovery.dart';

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
