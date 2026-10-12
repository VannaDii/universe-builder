@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_store/local_settings.dart';

void main() {
  late Directory directory;
  late String path;
  final endpoint = EncryptedPostgresEndpoint(
    keyReference: 'disposable-os-key-reference',
    ciphertext: [1, 2, 3, 4],
    nonce: List<int>.filled(12, 7),
    tag: List<int>.filled(16, 9),
  );
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-settings-',
    );
    path = '${directory.path}/settings.sqlite';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('typed encrypted settings survive restart with stable identity', () {
    var store = LocalSettingsStore.create(
      path,
      installationId: 'installation-one',
    );
    expect(store.read().installationId, 'installation-one');
    expect(store.read().usePostgres, isFalse);
    expect(store.read().endpoint, isNull);
    store.save(usePostgres: true, endpoint: endpoint);
    store.close();
    store = LocalSettingsStore.openExisting(path);
    try {
      final settings = store.read();
      expect(settings.installationId, 'installation-one');
      expect(settings.usePostgres, isTrue);
      expect(settings.endpoint!.keyReference, endpoint.keyReference);
      expect(settings.endpoint!.ciphertext, endpoint.ciphertext);
      expect(settings.endpoint!.nonce, endpoint.nonce);
      expect(settings.endpoint!.tag, endpoint.tag);
      expect('$settings', isNot(contains(endpoint.keyReference)));
      store.save(usePostgres: false, endpoint: endpoint);
      expect(store.read().endpoint, isNotNull);
      store.save(usePostgres: false, endpoint: null);
      expect(store.read().endpoint, isNull);
      expect(store.read().installationId, 'installation-one');
    } finally {
      store.close();
    }
  });

  test('settings use only fixed typed columns and durable WAL policy', () {
    final store = LocalSettingsStore.create(
      path,
      installationId: 'installation',
    );
    try {
      store.save(usePostgres: true, endpoint: endpoint);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA journal_mode').single.values.single, 'wal');
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((row) => row['name'])
              .toList(),
          ['local_settings'],
        );
        final row = db.select('SELECT * FROM local_settings').single;
        expect(row.keys.toList(), [
          'singleton',
          'installation_id',
          'use_postgres',
          'endpoint_key_reference',
          'endpoint_ciphertext',
          'endpoint_nonce',
          'endpoint_tag',
        ]);
        expect(row['endpoint_ciphertext'], isA<Uint8List>());
        expect(row['endpoint_nonce'], isA<Uint8List>());
        expect(row['endpoint_tag'], isA<Uint8List>());
      } finally {
        db.close();
      }
      for (final file in [
        path,
        '$path-wal',
        '$path-shm',
        '$path.writer.lock',
      ]) {
        expect(File(file).statSync().mode & 0x1ff, 0x180);
      }
    } finally {
      store.close();
    }
  });

  test('invalid save preserves prior settings and closed access fails', () {
    final store = LocalSettingsStore.create(
      path,
      installationId: 'installation',
    );
    store.save(usePostgres: true, endpoint: endpoint);
    expect(
      () => store.save(usePostgres: true, endpoint: null),
      throwsFormatException,
    );
    expect(store.read().usePostgres, isTrue);
    expect(store.read().endpoint!.ciphertext, endpoint.ciphertext);
    store.close();
    store.close();
    expect(store.read, throwsStateError);
    expect(
      () => store.save(usePostgres: false, endpoint: null),
      throwsStateError,
    );
  });

  test('writer ownership refuses another opener until close', () {
    final store = LocalSettingsStore.create(
      path,
      installationId: 'installation',
    );
    expect(
      () => LocalSettingsStore.openExisting(path),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => LocalSettingsStore.create(path, installationId: 'replacement'),
      throwsA(isA<FileSystemException>()),
    );
    store.close();
    final reopened = LocalSettingsStore.openExisting(path);
    expect(reopened.read().installationId, 'installation');
    reopened.close();
  });

  test(
    'create never overwrites and absent existing settings are not created',
    () {
      expect(
        () => LocalSettingsStore.openExisting(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).existsSync(), isFalse);
      final store = LocalSettingsStore.create(
        path,
        installationId: 'installation',
      );
      store.close();
      final before = File(path).readAsBytesSync();
      expect(
        () => LocalSettingsStore.create(path, installationId: 'replacement'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).readAsBytesSync(), before);
    },
  );

  test('unrecognized schema version is preserved and ownership released', () {
    final store = LocalSettingsStore.create(
      path,
      installationId: 'installation',
    );
    store.close();
    final db = sqlite3.open(path);
    db.execute('PRAGMA user_version=99');
    db.close();
    final before = File(path).readAsBytesSync();
    expect(() => LocalSettingsStore.openExisting(path), throwsFormatException);
    expect(() => LocalSettingsStore.openExisting(path), throwsFormatException);
    expect(File(path).readAsBytesSync(), before);
  });

  test('existing permissive files and symlink databases are refused', () {
    final store = LocalSettingsStore.create(
      path,
      installationId: 'installation',
    );
    store.close();
    expect(Process.runSync('chmod', ['644', path]).exitCode, 0);
    expect(
      () => LocalSettingsStore.openExisting(path),
      throwsA(isA<FileSystemException>()),
    );
    expect(Process.runSync('chmod', ['600', path]).exitCode, 0);
    final alias = '${directory.path}/alias.sqlite';
    Link(alias).createSync(path);
    expect(
      () => LocalSettingsStore.openExisting(alias),
      throwsA(isA<FileSystemException>()),
    );
    final reopened = LocalSettingsStore.openExisting(path);
    reopened.close();
  });

  test('failed transactional write leaves prior settings after restart', () {
    var store = LocalSettingsStore.create(path, installationId: 'installation');
    store.save(usePostgres: true, endpoint: endpoint);
    store.close();
    final db = sqlite3.open(path);
    db.execute(
      "CREATE TRIGGER refuse_settings BEFORE UPDATE ON local_settings BEGIN SELECT RAISE(ABORT, 'disposable write failure'); END",
    );
    db.close();
    store = LocalSettingsStore.openExisting(path);
    expect(
      () => store.save(usePostgres: false, endpoint: null),
      throwsA(isA<SqliteException>()),
    );
    expect(store.read().usePostgres, isTrue);
    store.close();
    final reopened = LocalSettingsStore.openExisting(path);
    try {
      expect(reopened.read().usePostgres, isTrue);
      expect(reopened.read().endpoint!.ciphertext, endpoint.ciphertext);
    } finally {
      reopened.close();
    }
  });

  test('invalid installation identities do not create a settings file', () {
    for (final identity in ['', 'bad\u0000id', String.fromCharCode(0xd800)]) {
      expect(
        () => LocalSettingsStore.create(path, installationId: identity),
        throwsFormatException,
      );
      expect(File(path).existsSync(), isFalse);
    }
  });

  test(
    'nonsecret startup selection does not read a damaged unused endpoint',
    () {
      final store = LocalSettingsStore.create(
        path,
        installationId: 'installation',
      );
      store.save(usePostgres: false, endpoint: endpoint);
      store.close();
      final db = sqlite3.open(path);
      db.execute('PRAGMA ignore_check_constraints=ON');
      db.execute('UPDATE local_settings SET endpoint_nonce=?', [Uint8List(1)]);
      db.close();
      final reopened = LocalSettingsStore.openExisting(path);
      try {
        expect(reopened.readBackendSelection(), isFalse);
        expect(reopened.read, throwsFormatException);
      } finally {
        reopened.close();
      }
    },
  );

  test('partial encrypted rows cannot be saved by SQLite', () {
    final store = LocalSettingsStore.create(
      path,
      installationId: 'installation',
    );
    store.close();
    final db = sqlite3.open(path);
    try {
      expect(
        () => db.execute(
          "UPDATE local_settings SET endpoint_key_reference='partial'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute('UPDATE local_settings SET use_postgres=1'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute('UPDATE local_settings SET use_postgres=2'),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      db.close();
    }
    final reopened = LocalSettingsStore.openExisting(path);
    expect(reopened.read().endpoint, isNull);
    reopened.close();
  });
}
