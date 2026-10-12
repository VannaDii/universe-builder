import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'ownership.dart';
import 'saved_settings.dart';

const _schema = '''
CREATE TABLE local_settings (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  installation_id TEXT NOT NULL CHECK (length(installation_id) > 0),
  use_postgres INTEGER NOT NULL CHECK (use_postgres IN (0, 1)),
  endpoint_key_reference TEXT,
  endpoint_ciphertext BLOB,
  endpoint_nonce BLOB,
  endpoint_tag BLOB,
  CHECK (
    (endpoint_key_reference IS NULL AND endpoint_ciphertext IS NULL AND
     endpoint_nonce IS NULL AND endpoint_tag IS NULL) OR
    (endpoint_key_reference IS NOT NULL AND length(endpoint_key_reference) > 0 AND
     endpoint_ciphertext IS NOT NULL AND endpoint_nonce IS NOT NULL AND
     length(endpoint_nonce) = 12 AND endpoint_tag IS NOT NULL AND length(endpoint_tag) = 16)
  ),
  CHECK (use_postgres = 0 OR endpoint_key_reference IS NOT NULL)
) STRICT;
PRAGMA user_version = 1;
''';

/// Owns the local settings writer for its lifetime. It never opens universe
/// data, validates connections, unlocks keys or changes backend processes.
final class LocalSettingsStore {
  LocalSettingsStore._(this._db, this._lock);
  final Database _db;
  final OwnedFileLock _lock;
  bool _closed = false;

  static LocalSettingsStore create(
    String path, {
    required String installationId,
  }) {
    if (installationId.isEmpty ||
        installationId.contains('\u0000') ||
        installationId.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
      throw const FormatException('Invalid installation identity.');
    }
    return _open(path, installationId: installationId);
  }

  static LocalSettingsStore openExisting(String path) => _open(path);

  static LocalSettingsStore _open(String path, {String? installationId}) {
    final create = installationId != null;
    final file = File(path).absolute;
    if (!create && !file.parent.existsSync()) {
      throw const FileSystemException('Existing settings directory absent');
    }
    final directory = privateDirectory(file.parent.path);
    final name = file.uri.pathSegments.last;
    final actualPath = '$directory/$name';
    final lock = OwnedFileLock.acquire('$actualPath.writer.lock');
    Database? db;
    try {
      protectedFile(actualPath, createNew: create);
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = '$actualPath$suffix';
        if (FileSystemEntity.typeSync(sidecar, followLinks: false) !=
            FileSystemEntityType.notFound) {
          protectedFile(sidecar);
        }
      }
      db = sqlite3.open(actualPath, mode: OpenMode.readWrite);
      if (sqlite3.version.versionNumber < 3051003) {
        throw StateError('SQLite WAL patch baseline not met');
      }
      if (!create) _checkSchema(db);
      db.execute('PRAGMA busy_timeout=2000');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA journal_mode=WAL');
      if (create) {
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(_schema);
          db.execute(
            'INSERT INTO local_settings(singleton, installation_id, use_postgres) VALUES(1, ?, 0)',
            [installationId],
          );
          db.execute('COMMIT');
        } catch (_) {
          if (!db.autocommit) db.execute('ROLLBACK');
          rethrow;
        }
      }
      final store = LocalSettingsStore._(db, lock);
      store.readBackendSelection();
      for (final suffix in ['-wal', '-shm']) {
        if (File('$actualPath$suffix').existsSync()) {
          protectedFile('$actualPath$suffix');
        }
      }
      return store;
    } catch (_) {
      db?.close();
      lock.close();
      rethrow;
    }
  }

  static void _checkSchema(Database db) {
    final version = db.select('PRAGMA user_version').single.values.single;
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final columns = db
        .select('PRAGMA table_info(local_settings)')
        .map((r) => '${r['name']}:${r['type']}')
        .join(',');
    if (version != 1 ||
        tables.length != 1 ||
        tables.single['name'] != 'local_settings' ||
        columns !=
            'singleton:INTEGER,installation_id:TEXT,use_postgres:INTEGER,endpoint_key_reference:TEXT,endpoint_ciphertext:BLOB,endpoint_nonce:BLOB,endpoint_tag:BLOB') {
      throw const FormatException(
        'Unsupported local settings schema; original preserved.',
      );
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Local settings store is closed');
  }

  /// Startup reads only nonsecret columns until PostgreSQL is selected.
  bool readBackendSelection() {
    _ensureOpen();
    return _metadata(
      _db.select(
        'SELECT singleton, installation_id, use_postgres FROM local_settings',
      ),
    ).usePostgres;
  }

  ({String id, bool usePostgres}) _metadata(ResultSet rows) {
    if (rows.length != 1) {
      throw const FormatException('Missing or ambiguous local settings.');
    }
    final row = rows.single;
    final id = row['installation_id'];
    final backend = row['use_postgres'];
    if (row['singleton'] != 1 ||
        id is! String ||
        id.isEmpty ||
        id.contains('\u0000') ||
        id.runes.any((r) => r >= 0xd800 && r <= 0xdfff) ||
        (backend != 0 && backend != 1)) {
      throw const FormatException('Invalid local settings.');
    }
    return (id: id, usePostgres: backend == 1);
  }

  SavedLocalSettings read() {
    _ensureOpen();
    final rows = _db.select('SELECT * FROM local_settings');
    final metadata = _metadata(rows);
    final row = rows.single;
    final reference = row['endpoint_key_reference'];
    final ciphertext = row['endpoint_ciphertext'];
    final nonce = row['endpoint_nonce'];
    final tag = row['endpoint_tag'];
    final EncryptedPostgresEndpoint? endpoint;
    if (reference == null &&
        ciphertext == null &&
        nonce == null &&
        tag == null &&
        !metadata.usePostgres) {
      endpoint = null;
    } else if (reference is String &&
        ciphertext is Uint8List &&
        nonce is Uint8List &&
        tag is Uint8List) {
      endpoint = EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: ciphertext,
        nonce: nonce,
        tag: tag,
      );
    } else {
      throw const FormatException('Invalid encrypted local settings.');
    }
    return SavedLocalSettings(
      installationId: metadata.id,
      usePostgres: metadata.usePostgres,
      endpoint: endpoint,
    );
  }

  /// Explicit setup-only save of a complete configuration. The caller must
  /// successfully unlock/test the connection and drain the engine first.
  /// The installation identity is never updated by a backend change.
  void save({
    required bool usePostgres,
    required EncryptedPostgresEndpoint? endpoint,
  }) {
    _ensureOpen();
    if (usePostgres && endpoint == null) {
      throw const FormatException('PostgreSQL requires an encrypted endpoint.');
    }
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'UPDATE local_settings SET use_postgres=?, endpoint_key_reference=?, endpoint_ciphertext=?, endpoint_nonce=?, endpoint_tag=? WHERE singleton=1',
        [
          usePostgres ? 1 : 0,
          endpoint?.keyReference,
          endpoint == null ? null : Uint8List.fromList(endpoint.ciphertext),
          endpoint == null ? null : Uint8List.fromList(endpoint.nonce),
          endpoint == null ? null : Uint8List.fromList(endpoint.tag),
        ],
      );
      if (_db.updatedRows != 1) {
        throw const FormatException('Local settings row missing.');
      }
      read();
      _db.execute('COMMIT');
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _db.close();
    } finally {
      _lock.close();
    }
  }
}
