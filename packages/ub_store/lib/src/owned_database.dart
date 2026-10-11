import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'ownership.dart';

/// Internal connection lifetime boundary. Full service startup still adds
/// canonical content/workflow verification and recovery before serving calls.
final class OwnedSqliteDatabase {
  OwnedSqliteDatabase._(this._database, this._lock) {
    _connectionLocks[_database] = _lock;
  }
  // Internal journal helpers retain the connection. Its native ownership must
  // survive too, even if the session wrapper is no longer referenced.
  static final _connectionLocks = Expando<OwnedFileLock>();
  final Database _database;
  final OwnedFileLock _lock;
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
