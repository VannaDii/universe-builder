import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'installation_schema.g.dart';
import 'ownership.dart';

const _normalization = 'nfc-0.1.22-casefold-0.2.0-v1';

enum InstallationFailure {
  unavailable,
  incompatibleSchema,
  identityNotInitialized,
  denied,
  alreadyEnrolled,
}

final class InstallationException implements Exception {
  const InstallationException(this.failure);
  final InstallationFailure failure;
  @override
  String toString() => 'InstallationException(${failure.name})';
}

final class InstallationProfile {
  const InstallationProfile({
    required this.id,
    required this.credentialHash,
    required this.author,
    required this.revoked,
  });
  final ProfileId id;
  final String credentialHash;
  final bool author;
  final bool revoked;
  @override
  String toString() =>
      'InstallationProfile(${id.value}, author: $author, revoked: $revoked, hash: [redacted])';
}

final class InstallationAuditEntry {
  const InstallationAuditEntry({
    required this.sequence,
    required this.actor,
    required this.action,
    required this.target,
  });
  final BigInt sequence;
  final String actor;
  final String action;
  final String target;
}

/// Native authority store. No connection or generic metadata writer is exposed.
/// Service authentication supplies actor identities; mutations recheck current
/// author status inside the same transaction as their append-only audit entry.
final class SqliteInstallationStore {
  SqliteInstallationStore._(this._db, this._lock, this.root, this.instanceId);
  final Database _db;
  final OwnedFileLock _lock;
  final String root;
  final OperationId instanceId;
  bool _closed = false;

  static SqliteInstallationStore create(String root) =>
      _open(root, create: true);
  static SqliteInstallationStore openExisting(String root) =>
      _open(root, create: false);

  static SqliteInstallationStore _open(String root, {required bool create}) {
    if (!create && !Directory(root).existsSync()) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
    final directory = privateDirectory(root);
    final lock = OwnedFileLock.acquire('$directory/service.lock');
    Database? db;
    try {
      final path = '$directory/installation.sqlite';
      protectedFile(path, createNew: create);
      for (final suffix in ['-wal', '-shm']) {
        if (FileSystemEntity.typeSync('$path$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          protectedFile('$path$suffix');
        }
      }
      db = sqlite3.open(path, mode: OpenMode.readWrite);
      if (sqlite3.version.versionNumber < 3051003) {
        throw const InstallationException(InstallationFailure.unavailable);
      }
      if (!create) _checkSchema(db);
      db.execute('PRAGMA busy_timeout=2000');
      db.execute('PRAGMA foreign_keys=ON');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA journal_mode=WAL');
      if (create) {
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(installationSchema);
          db.execute("INSERT INTO settings VALUES('normalization', ?)", [
            _normalization,
          ]);
          db.execute(
            "INSERT INTO settings VALUES('installation_instance', ?)",
            [OperationId.generate().value],
          );
          db.execute('COMMIT');
        } catch (_) {
          if (!db.autocommit) db.execute('ROLLBACK');
          rethrow;
        }
        privateDirectory('$directory/profiles');
        privateDirectory('$directory/packages');
      }
      final instance = db.select(
        "SELECT value FROM settings WHERE key='installation_instance'",
      );
      if (instance.length != 1) {
        throw const InstallationException(
          InstallationFailure.identityNotInitialized,
        );
      }
      final instanceId = OperationId.parse(instance.single['value'] as String);
      for (final suffix in ['-wal', '-shm']) {
        if (File('$path$suffix').existsSync()) protectedFile('$path$suffix');
      }
      return SqliteInstallationStore._(db, lock, directory, instanceId);
    } on InstallationException {
      db?.close();
      lock.close();
      rethrow;
    } on Object {
      db?.close();
      lock.close();
      throw const InstallationException(InstallationFailure.unavailable);
    }
  }

  static void _checkSchema(Database db) {
    final grants = db
        .select('PRAGMA table_info(grants)')
        .map((r) => r['name'])
        .toList();
    final preview = db
        .select('PRAGMA table_info(import_preview)')
        .map((r) => r['name'])
        .toList();
    final profiles = db
        .select('PRAGMA table_info(profiles)')
        .map((r) => r['name'])
        .join(',');
    final normalization = db.select(
      "SELECT value FROM settings WHERE key='normalization'",
    );
    if (!grants.contains('worlds_state') ||
        !preview.contains('includes_workflow') ||
        profiles != 'id,hash,author,revoked' ||
        normalization.length != 1 ||
        normalization.single['value'] != _normalization) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    final instance = db.select(
      "SELECT value FROM settings WHERE key='installation_instance'",
    );
    if (instance.length != 1) {
      // Controlled cutover must establish this identity. Opening never assigns
      // a replacement identity to an older installation or rewrites its hashes.
      throw const InstallationException(
        InstallationFailure.identityNotInitialized,
      );
    }
    try {
      OperationId.parse(instance.single['value'] as String);
    } on Object {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Installation store is closed');
  }

  InstallationProfile? profile(ProfileId id) {
    _ensureOpen();
    final rows = _db.select(
      'SELECT id,hash,author,revoked FROM profiles WHERE id=?',
      [id.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final hash = row['hash'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        hash.length != 64 ||
        ![0, 1].contains(row['author']) ||
        ![0, 1].contains(row['revoked'])) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    return InstallationProfile(
      id: ProfileId.parse(row['id'] as String),
      credentialHash: hash,
      author: row['author'] == 1,
      revoked: row['revoked'] == 1,
    );
  }

  void requireAuthor(ProfileId id) {
    final actor = profile(id);
    if (actor == null || actor.revoked || !actor.author) {
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  ProfileId currentAuthor() {
    _ensureOpen();
    final rows = _db.select(
      'SELECT id FROM profiles WHERE author=1 AND revoked=0 ORDER BY id',
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return ProfileId.parse(rows.first['id'] as String);
  }

  void enroll({
    required ProfileId id,
    required String credentialHash,
    ProfileId? actor,
  }) {
    if (credentialHash.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(credentialHash)) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    _transaction(() {
      if (actor == null) {
        if (_db.select('SELECT count(*) AS n FROM profiles').single['n'] != 0) {
          throw const InstallationException(
            InstallationFailure.alreadyEnrolled,
          );
        }
      } else {
        requireAuthor(actor);
      }
      _db.execute(
        'INSERT INTO profiles(id, hash, author, revoked) VALUES(?, ?, ?, 0)',
        [id.value, credentialHash, actor == null ? 1 : 0],
      );
      _db.execute(
        "INSERT INTO audit(actor, action, target) VALUES(?, 'enroll', ?)",
        [actor?.value ?? 'local-bootstrap', id.value],
      );
    });
  }

  void revoke({required ProfileId actor, required ProfileId target}) {
    _transaction(() {
      requireAuthor(actor);
      if (actor == target) {
        throw const InstallationException(InstallationFailure.denied);
      }
      _db.execute('UPDATE profiles SET revoked=1 WHERE id=? AND author=0', [
        target.value,
      ]);
      if (_db.updatedRows != 1) {
        throw const InstallationException(InstallationFailure.denied);
      }
      _db.execute(
        "INSERT INTO audit(actor, action, target) VALUES(?, 'revoke', ?)",
        [actor.value, target.value],
      );
    });
  }

  List<InstallationProfile> profiles(ProfileId actor) {
    requireAuthor(actor);
    final ids = _db.select('SELECT id FROM profiles ORDER BY id');
    return List<InstallationProfile>.unmodifiable(
      ids.map((r) => profile(ProfileId.parse(r['id'] as String))!),
    );
  }

  List<InstallationAuditEntry> audit(ProfileId actor) {
    requireAuthor(actor);
    return List<InstallationAuditEntry>.unmodifiable(
      _db
          .select(
            'SELECT sequence,actor,action,target FROM audit ORDER BY sequence',
          )
          .map(
            (r) => InstallationAuditEntry(
              sequence: BigInt.from(r['sequence'] as int),
              actor: r['actor'] as String,
              action: r['action'] as String,
              target: r['target'] as String,
            ),
          ),
    );
  }

  bool get hasProfiles {
    _ensureOpen();
    return _db.select('SELECT count(*) AS n FROM profiles').single['n'] != 0;
  }

  void _transaction(void Function() action) {
    _ensureOpen();
    _db.execute('BEGIN IMMEDIATE');
    try {
      action();
      _db.execute('COMMIT');
    } on InstallationException {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      throw const InstallationException(InstallationFailure.unavailable);
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
