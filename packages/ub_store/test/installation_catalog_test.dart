@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show sqlite3, OpenMode;
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/owned_database.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory directory;
  late SqliteInstallationStore store;
  late ProfileId author;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-catalog-',
    );
    store = SqliteInstallationStore.create(directory.path);
    author = ProfileId.generate();
    store.enroll(id: author, credentialHash: '0' * 64);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  ({String path, UniverseId id}) package(String name) {
    final path = '${directory.path}/packages/$name.sqlite';
    final id = UniverseId.generate();
    final package = OwnedSqliteDatabase.create(path);
    try {
      package.database.execute('BEGIN IMMEDIATE');
      SqliteJournal(package.database, id).initialize(
        'Disposable package',
        ContinuityId.generate(),
        PrincipalId.generate(),
      );
      package.database.execute('COMMIT');
    } finally {
      package.close();
    }
    return (path: path, id: id);
  }

  test('failed move audit rolls back source guard and retains access', () {
    final fixture = package('move');
    store.registerExistingPackage(
      actor: author,
      name: 'Move',
      path: fixture.path,
    );
    store.close();
    final db = sqlite3.open('${directory.path}/installation.sqlite');
    db.execute(
      "CREATE TRIGGER refuse_move BEFORE INSERT ON audit WHEN NEW.action='quiesce_move' BEGIN SELECT RAISE(ABORT, 'disposable move failure'); END",
    );
    db.close();
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(
      () => store.quiesceUniverseForMove(
        actor: author,
        universe: fixture.id,
        operation: OperationId.generate(),
        targetInstance: OperationId.generate(),
      ),
      throwsA(
        isA<InstallationException>().having(
          (e) => e.failure,
          'failure',
          InstallationFailure.unavailable,
        ),
      ),
    );
    expect(
      store.resolveUniverseAlias(actor: author, name: 'Move').universeId,
      fixture.id,
    );
    expect(
      store.audit(author).where((e) => e.action == 'quiesce_move'),
      isEmpty,
    );
  });

  test('explicit purge removes move binding with catalog while retaining pending cleanup', () {
    final fixture = package('move');
    store.registerExistingPackage(
      actor: author,
      name: 'Move',
      path: fixture.path,
    );
    store.quiesceUniverseForMove(
      actor: author,
      universe: fixture.id,
      operation: OperationId.generate(),
      targetInstance: OperationId.generate(),
    );
    store.beginPurge(actor: author, universe: fixture.id);
    store.close();
    final db = sqlite3.open(
      '${directory.path}/installation.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(db.select('SELECT * FROM move_quiescence'), isEmpty);
      expect(db.select('SELECT * FROM purge_pending'), hasLength(1));
    } finally {
      db.close();
    }
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(File(fixture.path).existsSync(), isFalse);
  });

  test('registration derives the real universe identity and persists exact aliases after restart', () {
    final fixture = package('one');
    expect(
      store.registerExistingPackage(
        actor: author,
        name: ' Café ',
        path: fixture.path,
      ),
      fixture.id,
    );
    expect(
      store.resolveUniverseAlias(actor: author, name: 'CAFE\u0301').universeId,
      fixture.id,
    );
    store.renameUniverse(actor: author, id: fixture.id, name: 'New Name');
    final instance = store.instanceId;
    store.close();
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(store.instanceId, instance);
    for (final name in ['CAFÉ', 'new name']) {
      final resolved = store.resolveUniverseAlias(actor: author, name: name);
      expect(resolved.universeId, fixture.id);
      expect(resolved.name, 'New Name');
      expect(resolved.path, File(fixture.path).resolveSymbolicLinksSync());
    }
    expect(store.audit(author).map((r) => r.action).toList(), [
      'enroll',
      'register',
      'rename',
    ]);
  });

  test(
    'pending purge finishes on startup after interruption before file deletion',
    () {
      final fixture = package('pending');
      store.registerExistingPackage(
        actor: author,
        name: 'Pending',
        path: fixture.path,
      );
      store.beginPurge(actor: author, universe: fixture.id);
      expect(store.catalog(author), isEmpty);
      expect(File(fixture.path).existsSync(), isTrue);
      expect(store.audit(author).last.action, 'purge');
      store.close();
      store = SqliteInstallationStore.openExisting(directory.path);
      expect(File(fixture.path).existsSync(), isFalse);
      expect(store.catalog(author), isEmpty);
      final db = sqlite3.open(
        '${directory.path}/installation.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          db.select('SELECT count(*) AS n FROM purge_pending').single['n'],
          0,
        );
      } finally {
        db.close();
      }
    },
  );

  test('interrupted purge retains its pending row until sidecar removal and directory sync succeed', () {
    final fixture = package('sidecar');
    store.registerExistingPackage(
      actor: author,
      name: 'Sidecar',
      path: fixture.path,
    );
    store.beginPurge(actor: author, universe: fixture.id);
    final blocked = Directory('${fixture.path}-wal')..createSync();
    expect(
      () => store.finishPurges(actor: author),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(fixture.path).existsSync(), isFalse);
    final db = sqlite3.open(
      '${directory.path}/installation.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(
        db.select('SELECT universe FROM purge_pending').single['universe'],
        fixture.id.value,
      );
    } finally {
      db.close();
    }
    blocked.deleteSync();
    store.close();
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(store.catalog(author), isEmpty);
    expect(File('${fixture.path}-wal').existsSync(), isFalse);
  });

  test('startup refuses changed identity and symlink at a pending purge path without deleting either file', () {
    final fixture = package('identity');
    store.registerExistingPackage(
      actor: author,
      name: 'Identity',
      path: fixture.path,
    );
    store.beginPurge(actor: author, universe: fixture.id);
    final original = '${fixture.path}.original';
    File(fixture.path).renameSync(original);
    final replacement = File(fixture.path)
      ..writeAsStringSync('Replacement data');
    store.close();
    expect(
      () => SqliteInstallationStore.openExisting(directory.path),
      throwsA(isA<InstallationException>()),
    );
    expect(replacement.readAsStringSync(), 'Replacement data');
    expect(File(original).existsSync(), isTrue);
    replacement.deleteSync();
    final link = Link(fixture.path)..createSync(original);
    expect(
      () => SqliteInstallationStore.openExisting(directory.path),
      throwsA(isA<InstallationException>()),
    );
    expect(link.targetSync(), original);
    expect(File(original).existsSync(), isTrue);
    link.deleteSync();
    File(original).renameSync(fixture.path);
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(File(fixture.path).existsSync(), isFalse);
    expect(store.catalog(author), isEmpty);
  });

  test('alias and package collisions rollback without losing historical reservations', () {
    final first = package('one');
    final second = package('two');
    store.registerExistingPackage(
      actor: author,
      name: 'Straße',
      path: first.path,
    );
    expect(
      () => store.registerExistingPackage(
        actor: author,
        name: 'STRASSE',
        path: second.path,
      ),
      throwsA(isA<InstallationException>()),
    );
    expect(store.catalog(author).length, 1);
    store.registerExistingPackage(
      actor: author,
      name: 'Other',
      path: second.path,
    );
    store.renameUniverse(actor: author, id: first.id, name: 'Renamed');
    final before = store.audit(author).length;
    expect(
      () => store.renameUniverse(actor: author, id: second.id, name: 'strasse'),
      throwsA(isA<InstallationException>()),
    );
    expect(
      () => store.registerExistingPackage(
        actor: author,
        name: 'Duplicate path',
        path: first.path,
      ),
      throwsA(isA<InstallationException>()),
    );
    expect(store.audit(author).length, before);
    expect(
      store.resolveUniverseAlias(actor: author, name: 'Other').universeId,
      second.id,
    );
    expect(store.catalog(author).map((e) => e.name).toList(), [
      'Other',
      'Renamed',
    ]);
  });

  test('replacement and symbolic-link substitution are refused by pinned file identity', () {
    final fixture = package('one');
    store.registerExistingPackage(
      actor: author,
      name: 'World',
      path: fixture.path,
    );
    final moved = '${fixture.path}.original';
    File(fixture.path).renameSync(moved);
    File(fixture.path).writeAsStringSync('Disposable replacement');
    expect(
      () => store.resolveUniverseAlias(actor: author, name: 'World'),
      throwsA(isA<InstallationException>()),
    );
    File(fixture.path).deleteSync();
    Link(fixture.path).createSync(moved);
    expect(
      () => store.resolveUniverseAlias(actor: author, name: 'World'),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(moved).existsSync(), isTrue);
  });

  test(
    'native metadata preserves exact device/inode and rejects hard links',
    () {
      final fixture = package('one');
      final identity = fileIdentity(fixture.path);
      final result = Process.runSync(
        'stat',
        Platform.isMacOS
            ? ['-f', '%d:%i', fixture.path]
            : ['-c', '%d:%i', fixture.path],
      );
      expect(result.exitCode, 0);
      expect('${result.stdout}'.trim(), '${identity.device}:${identity.inode}');
      store.registerExistingPackage(
        actor: author,
        name: 'World',
        path: fixture.path,
      );
      final alias = '${fixture.path}.hardlink';
      expect(Process.runSync('ln', [fixture.path, alias]).exitCode, 0);
      expect(
        () => store.resolveUniverseAlias(actor: author, name: 'World'),
        throwsA(isA<FileSystemException>()),
      );
      File(alias).deleteSync();
      expect(
        store.resolveUniverseAlias(actor: author, name: 'World').universeId,
        fixture.id,
      );
    },
  );

  test(
    'non-author and invalid packages cannot publish catalog or audit changes',
    () {
      final agent = ProfileId.generate();
      store.enroll(id: agent, credentialHash: '1' * 64, actor: author);
      final fixture = package('one');
      final before = store.audit(author).length;
      expect(
        () => store.registerExistingPackage(
          actor: agent,
          name: 'World',
          path: fixture.path,
        ),
        throwsA(isA<InstallationException>()),
      );
      expect(store.catalog(agent), isEmpty);
      final empty = OwnedSqliteDatabase.create(
        '${directory.path}/packages/empty.sqlite',
      );
      empty.close();
      expect(
        () => store.registerExistingPackage(
          actor: author,
          name: 'Empty',
          path: '${directory.path}/packages/empty.sqlite',
        ),
        throwsFormatException,
      );
      expect(
        () => store.registerExistingPackage(
          actor: author,
          name: '*',
          path: fixture.path,
        ),
        throwsFormatException,
      );
      expect(store.catalog(author), isEmpty);
      expect(store.audit(author).length, before);
    },
  );
}
