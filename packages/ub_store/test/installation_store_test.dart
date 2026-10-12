@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';

void main() {
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync(
      'universe-builder-installation-',
    ),
  );
  tearDown(() => directory.deleteSync(recursive: true));
  Matcher failure(InstallationFailure expected) => throwsA(
    isA<InstallationException>().having((e) => e.failure, 'failure', expected),
  );

  test('stable identity and protected writer ownership survive restart', () {
    final store = SqliteInstallationStore.create(directory.path);
    final instance = store.instanceId;
    expect(
      () => SqliteInstallationStore.openExisting(directory.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      File('${directory.path}/installation.sqlite').statSync().mode & 0x1ff,
      0x180,
    );
    store.close();
    final reopened = SqliteInstallationStore.openExisting(directory.path);
    expect(reopened.instanceId, instance);
    expect(reopened.hasProfiles, isFalse);
    reopened.close();
    reopened.close();
    expect(() => reopened.hasProfiles, throwsStateError);
  });

  test('legacy installation without stable identity is preserved', () {
    final store = SqliteInstallationStore.create(directory.path);
    store.close();
    final path = '${directory.path}/installation.sqlite';
    final db = sqlite3.open(path);
    db.execute("DELETE FROM settings WHERE key='installation_instance'");
    db.close();
    final before = File(path).readAsBytesSync();
    expect(
      () => SqliteInstallationStore.openExisting(directory.path),
      failure(InstallationFailure.identityNotInitialized),
    );
    expect(
      () => SqliteInstallationStore.openExisting(directory.path),
      failure(InstallationFailure.identityNotInitialized),
    );
    expect(File(path).readAsBytesSync(), before);
  });

  test('unsupported normalization is refused before journal changes', () {
    final store = SqliteInstallationStore.create(directory.path);
    store.close();
    final path = '${directory.path}/installation.sqlite';
    final db = sqlite3.open(path);
    db.execute(
      "UPDATE settings SET value='unsupported' WHERE key='normalization'",
    );
    db.close();
    final before = File(path).readAsBytesSync();
    expect(
      () => SqliteInstallationStore.openExisting(directory.path),
      failure(InstallationFailure.incompatibleSchema),
    );
    expect(File(path).readAsBytesSync(), before);
  });

  test(
    'malformed stable identity is refused without changing the original',
    () {
      final store = SqliteInstallationStore.create(directory.path);
      store.close();
      final path = '${directory.path}/installation.sqlite';
      final db = sqlite3.open(path);
      db.execute(
        "UPDATE settings SET value='invalid-instance' WHERE key='installation_instance'",
      );
      db.close();
      final before = File(path).readAsBytesSync();
      expect(
        () => SqliteInstallationStore.openExisting(directory.path),
        failure(InstallationFailure.incompatibleSchema),
      );
      expect(File(path).readAsBytesSync(), before);
    },
  );

  test('failed audit append rolls back profile enrollment', () {
    var store = SqliteInstallationStore.create(directory.path);
    final author = ProfileId.generate();
    store.enroll(id: author, credentialHash: '0' * 64);
    store.close();
    final db = sqlite3.open('${directory.path}/installation.sqlite');
    db.execute(
      "CREATE TRIGGER refuse_audit BEFORE INSERT ON audit BEGIN SELECT RAISE(ABORT, 'disposable audit failure'); END",
    );
    db.close();
    store = SqliteInstallationStore.openExisting(directory.path);
    try {
      final agent = ProfileId.generate();
      expect(
        () => store.enroll(id: agent, credentialHash: '1' * 64, actor: author),
        failure(InstallationFailure.unavailable),
      );
      expect(store.profile(agent), isNull);
      expect(store.audit(author).length, 1);
    } finally {
      store.close();
    }
  });
}
