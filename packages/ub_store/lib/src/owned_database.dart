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
