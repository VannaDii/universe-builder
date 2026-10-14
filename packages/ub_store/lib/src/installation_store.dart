import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_contracts/ub_contracts.dart';

import 'installation_schema.g.dart';
import 'ownership.dart';
import 'owned_database.dart';

part 'installation_grants.dart';
part 'installation_imports.dart';
part 'installation_uploads.dart';
part 'installation_moves.dart';

const _normalization = selectorNormalizationVersion;

enum InstallationFailure {
  unavailable,
  incompatibleSchema,
  identityNotInitialized,
  denied,
  alreadyEnrolled,
  invalidGrant,
}

final class InstallationException implements Exception {
  const InstallationException(this.failure);
  final InstallationFailure failure;
  @override
  String toString() => 'InstallationException(${failure.name})';
}

/// Coordinates explicit initialization and on-demand launch without opening the
/// installation database or creating an absent installation directory.
final class InstallationBootstrapLock {
  InstallationBootstrapLock._(this.root, this._lock);
  final String root;
  final OwnedFileLock _lock;
  static InstallationBootstrapLock acquireExisting(String root) {
    if (FileSystemEntity.typeSync(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
    final directory = privateDirectory(root);
    return InstallationBootstrapLock._(
      directory,
      OwnedFileLock.acquire('$directory/bootstrap.lock'),
    );
  }

  void close() => _lock.close();
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

final class InstallationCatalogEntry {
  const InstallationCatalogEntry({
    required this.universeId,
    required this.name,
    required this.path,
  });
  final UniverseId universeId;
  final String name;
  final String path;
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
  final Object _authorityZoneKey = Object();
  Object? _authorityToken;
  Future<void> _authorityTail = Future.value();

  /// Serialize authority-sensitive workflows across asynchronous universe reads.
  /// The service owns this installation exclusively via its existing file lock.
  /// Grant/revocation routes must use the same section; direct mutations from
  /// outside an active section are refused rather than changing captured rights.
  /// Acquire installation authority before the universe writer/read context.
  Future<T> withAuthority<T>(FutureOr<T> Function() action) async {
    _ensureOpen();
    if (_authorityToken != null &&
        Zone.current[_authorityZoneKey] == _authorityToken) {
      throw StateError('Installation authority section is not reentrant');
    }
    final previous = _authorityTail;
    final release = Completer<void>();
    _authorityTail = release.future;
    await previous;
    try {
      _ensureOpen();
      final token = Object();
      _authorityToken = token;
      return await runZoned(action, zoneValues: {_authorityZoneKey: token});
    } finally {
      _authorityToken = null;
      release.complete();
    }
  }

  static SqliteInstallationStore create(String root) =>
      _open(root, create: true);
  static SqliteInstallationStore openExisting(String root) =>
      _open(root, create: false);

  /// Explicit installation initialization holds bootstrap ownership as well as
  /// the store's service lock. Existing authority is opened without replacement.
  static T withBootstrap<T>(
    String root,
    T Function(SqliteInstallationStore) initialize,
  ) {
    final directory = privateDirectory(root);
    final bootstrap = InstallationBootstrapLock.acquireExisting(directory);
    try {
      final path = '$directory/installation.sqlite';
      final store =
          FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.notFound
          ? create(directory)
          : openExisting(directory);
      try {
        return initialize(store);
      } finally {
        store.close();
      }
    } finally {
      bootstrap.close();
    }
  }

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
      final store = SqliteInstallationStore._(db, lock, directory, instanceId);
      if (!create) store._rebaseOwnedPackagePaths();
      store._finishPurges();
      return store;
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

  /// App updates may move the private container without replacing its files.
  /// Rebase only deterministic installation-owned paths whose original location
  /// disappeared, preserving the registered device/inode binding. External
  /// registrations and replacement files retain their existing failure behavior.
  void _rebaseOwnedPackagePaths() {
    _transaction(() {
      for (final (table, key) in [
        ('catalog', 'id'),
        ('purge_pending', 'universe'),
      ]) {
        for (final row in _db.select(
          'SELECT $key,path,device,inode FROM $table',
        )) {
          final id = UniverseId.parse(row[key] as String);
          final old = row['path'] as String;
          final relative = 'packages/${id.value}.sqlite';
          final current = '$root/$relative';
          if (old == current ||
              !old.replaceAll('\\', '/').endsWith('/$relative') ||
              FileSystemEntity.typeSync(old, followLinks: false) !=
                  FileSystemEntityType.notFound) {
            continue;
          }
          try {
            final type = FileSystemEntity.typeSync(current, followLinks: false);
            if (type == FileSystemEntityType.notFound) {
              // A pending purge may have removed the main file before the
              // process stopped; finish its remaining cleanup in this root.
              if (table != 'purge_pending') continue;
            } else {
              final identity = fileIdentity(current);
              if (identity.device != row['device'] ||
                  identity.inode != row['inode']) {
                if (table == 'purge_pending') {
                  throw const InstallationException(
                    InstallationFailure.unavailable,
                  );
                }
                continue;
              }
            }
          } on FileSystemException {
            if (table == 'purge_pending') rethrow;
            continue;
          }
          _db.execute('UPDATE $table SET path=? WHERE $key=? AND path=?', [
            current,
            id.value,
            old,
          ]);
        }
      }
    });
  }

  static void _checkSchema(Database db) {
    final reviews = db
        .select('PRAGMA table_info(move_review)')
        .map((r) => r['name'])
        .join(',');
    final moves = db
        .select('PRAGMA table_info(move_quiescence)')
        .map((r) => r['name'])
        .join(',');
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
    final uploads = db
        .select('PRAGMA table_info(archive_upload)')
        .map((r) => r['name'])
        .join(',');
    final chunks = db
        .select('PRAGMA table_info(archive_upload_chunk)')
        .map((r) => r['name'])
        .join(',');
    if (uploads != 'id,owner,source_digest,bytes' ||
        chunks != 'upload,ordinal,content' ||
        reviews !=
            'operation,preview_id,owner,name,source_digest,records,preview_digest,state' ||
        moves != 'universe,operation,target_instance' ||
        !grants.contains('worlds_state') ||
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

  /// Open/recover the real package and derive its identity before registration.
  /// The package writer lock remains held through catalog publication.
  UniverseId registerExistingPackage({
    required ProfileId actor,
    required String name,
    required String path,
  }) {
    requireAuthor(actor);
    selectorKey(name);
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      return registerOwnedPackage(actor: actor, name: name, package: package);
    } finally {
      package.close();
    }
  }

  /// Check identity and historical name reservations before importing a package.
  List<String> importConflicts({
    required ProfileId actor,
    required UniverseId id,
    required String name,
  }) {
    requireAuthor(actor);
    final key = selectorKey(name);
    return List.unmodifiable([
      if (_db.select(
            'SELECT EXISTS(SELECT 1 FROM catalog WHERE id=?) AS present',
            [id.value],
          ).single['present'] ==
          1)
        'Universe identity already registered; choose a named clone',
      if (_db.select(
            'SELECT EXISTS(SELECT 1 FROM aliases WHERE key=?) AS present',
            [key],
          ).single['present'] ==
          1)
        'Universe name or alias is already reserved',
    ]);
  }

  /// Retain caller ownership while publishing the recovered package's identity.
  /// The path comes from its open session, never from a separate caller claim.
  UniverseId registerOwnedPackage({
    required ProfileId actor,
    required String name,
    required OwnedSqliteDatabase package,
  }) {
    requireAuthor(actor);
    selectorKey(name);
    package.recover();
    final id = package.universeId;
    _registerUniverse(actor: actor, id: id, name: name, path: package.path);
    return id;
  }

  void _registerUniverse({
    required ProfileId actor,
    required UniverseId id,
    required String name,
    required String path,
  }) {
    requireAuthor(actor);
    final key = selectorKey(name);
    final actualPath = File(path).resolveSymbolicLinksSync();
    final identity = fileIdentity(actualPath);
    _transaction(() {
      requireAuthor(actor);
      _db.execute(
        'INSERT INTO catalog(id,name,path,device,inode) VALUES(?,?,?,?,?)',
        [id.value, name, actualPath, identity.device, identity.inode],
      );
      _db.execute('INSERT INTO aliases(key,universe) VALUES(?,?)', [
        key,
        id.value,
      ]);
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'register',?)",
        [actor.value, id.value],
      );
    });
  }

  /// Retain the source intact while a trusted coordinator moves it elsewhere.
  /// This installation metadata must never enter universe archives.
  void quiesceUniverseForMove({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) {
    requireAuthor(actor);
    if (targetInstance == instanceId) {
      throw const FormatException('Move target must be another installation');
    }
    if (_db.select('SELECT id FROM catalog WHERE id=?', [
      universe.value,
    ]).isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final existing = _db.select(
      'SELECT operation,target_instance FROM move_quiescence WHERE universe=?',
      [universe.value],
    );
    if (existing.isNotEmpty) {
      if (existing.single['operation'] != operation.value ||
          existing.single['target_instance'] != targetInstance.value) {
        throw const FormatException('Source is bound to another move');
      }
      return;
    }
    if (_db.select('SELECT universe FROM move_quiescence WHERE operation=?', [
      operation.value,
    ]).isNotEmpty) {
      throw const FormatException('Move operation belongs to another universe');
    }
    // These synchronous checks and the write execute without yielding within
    // the installation's authority queue and exclusive lifetime file lock.
    _transaction(() {
      requireAuthor(actor);
      _db.execute('INSERT INTO move_quiescence VALUES(?,?,?)', [
        universe.value,
        operation.value,
        targetInstance.value,
      ]);
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'quiesce_move',?)",
        [actor.value, universe.value],
      );
    });
  }

  /// Trusted coordinator access only for the exact retained move binding.
  /// Ordinary alias/catalog routes continue to deny this source.
  ({InstallationCatalogEntry catalog, String archivePath}) moveSource({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) {
    requireAuthor(actor);
    final rows = _db.select(
      'SELECT c.name,c.path,c.device,c.inode FROM catalog c '
      'JOIN move_quiescence m ON m.universe=c.id '
      'WHERE c.id=? AND m.operation=? AND m.target_instance=?',
      [universe.value, operation.value, targetInstance.value],
    );
    if (rows.length != 1) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final row = rows.single;
    final path = row['path'] as String;
    final identity = fileIdentity(path);
    if (identity.device != row['device'] || identity.inode != row['inode']) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final directory = privateDirectory('$root/moves');
    final archivePath = '$directory/${operation.value}.sqlite';
    if (FileSystemEntity.typeSync(archivePath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      protectedFile(archivePath);
    }
    return (
      catalog: InstallationCatalogEntry(
        universeId: universe,
        name: row['name'] as String,
        path: path,
      ),
      archivePath: archivePath,
    );
  }

  void renameUniverse({
    required ProfileId actor,
    required UniverseId id,
    required String name,
  }) {
    requireAuthor(actor);
    final key = selectorKey(name);
    _transaction(() {
      requireAuthor(actor);
      final existing = _db.select('SELECT universe FROM aliases WHERE key=?', [
        key,
      ]);
      if (existing.isNotEmpty && existing.single['universe'] != id.value) {
        throw const InstallationException(InstallationFailure.denied);
      }
      _db.execute('UPDATE catalog SET name=? WHERE id=?', [name, id.value]);
      if (_db.updatedRows != 1) {
        throw const InstallationException(InstallationFailure.denied);
      }
      // Historical aliases remain reserved for the original universe.
      _db.execute('INSERT OR IGNORE INTO aliases(key,universe) VALUES(?,?)', [
        key,
        id.value,
      ]);
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'rename',?)",
        [actor.value, id.value],
      );
    });
  }

  InstallationCatalogEntry resolveUniverseAlias({
    required ProfileId actor,
    required String name,
    BigInt? epochSeconds,
  }) {
    _activeProfile(actor);
    final rows = _db.select(
      'SELECT c.id,c.name,c.path,c.device,c.inode FROM catalog c JOIN aliases a ON a.universe=c.id WHERE a.key=?',
      [selectorKey(name)],
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final row = rows.single;
    final id = UniverseId.parse(row['id'] as String);
    universeScope(
      actor,
      id,
      epochSeconds ??
          BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    );
    final path = row['path'] as String;
    final identity = fileIdentity(path);
    if (identity.device != row['device'] || identity.inode != row['inode']) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return InstallationCatalogEntry(
      universeId: id,
      name: row['name'] as String,
      path: path,
    );
  }

  List<InstallationCatalogEntry> catalog(
    ProfileId actor, {
    BigInt? epochSeconds,
  }) {
    _activeProfile(actor);
    final rows = _db.select(
      'SELECT id,name,path FROM catalog ORDER BY name LIMIT 1001',
    );
    if (rows.length > 1000) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
    final entries = <InstallationCatalogEntry>[];
    final now =
        epochSeconds ??
        BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    for (final row in rows) {
      final id = UniverseId.parse(row['id'] as String);
      try {
        universeScope(actor, id, now);
      } on Object {
        continue;
      }
      entries.add(
        InstallationCatalogEntry(
          universeId: id,
          name: row['name'] as String,
          path: row['path'] as String,
        ),
      );
    }
    return List<InstallationCatalogEntry>.unmodifiable(entries);
  }

  void _transaction(void Function() action) {
    _ensureOpen();
    if (_authorityToken != null &&
        Zone.current[_authorityZoneKey] != _authorityToken) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
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

  /// Retire installation access atomically before removing any package bytes.
  /// The service closes its owned package before calling [finishPurges].
  void beginPurge({required ProfileId actor, required UniverseId universe}) {
    requireAuthor(actor);
    _transaction(() {
      requireAuthor(actor);
      final registered = _db.select('SELECT id FROM catalog WHERE id=?', [
        universe.value,
      ]);
      if (registered.length != 1) {
        throw const InstallationException(InstallationFailure.denied);
      }
      _db.execute(
        'INSERT INTO purge_pending SELECT id,path,device,inode FROM catalog WHERE id=?',
        [universe.value],
      );
      for (final table in [
        'grant_worlds',
        'grant_entities',
        'grant_predicates',
        'grant_continuities',
        'grants',
        'aliases',
        'catalog',
      ]) {
        final column = table == 'catalog' ? 'id' : 'universe';
        _db.execute('DELETE FROM $table WHERE $column=?', [universe.value]);
      }
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'purge',?)",
        [actor.value, universe.value],
      );
    });
  }

  void finishPurges({required ProfileId actor}) {
    requireAuthor(actor);
    _finishPurges();
  }

  void _finishPurges() {
    final pending = _db.select(
      'SELECT universe,path,device,inode FROM purge_pending',
    );
    for (final entry in pending) {
      final path = entry['path'] as String;
      ({String device, String inode})? identity;
      try {
        identity = fileIdentity(path);
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 2) rethrow;
      }
      if (identity != null) {
        if (identity.device != entry['device'] ||
            identity.inode != entry['inode']) {
          throw const InstallationException(InstallationFailure.unavailable);
        }
        File(path).deleteSync();
      }
      for (final suffix in ['-wal', '-shm']) {
        try {
          File('$path$suffix').deleteSync();
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 2) rethrow;
        }
      }
      syncPrivateDirectory(File(path).parent.path);
      _transaction(() {
        _db.execute('DELETE FROM purge_pending WHERE universe=?', [
          entry['universe'],
        ]);
      });
    }
  }

  void close() {
    if (_closed) return;
    if (_authorityToken != null) {
      throw StateError('Installation authority section is still active');
    }
    _closed = true;
    try {
      _db.close();
    } finally {
      _lock.close();
    }
  }
}
