@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory directory;
  late ProfileId profile;
  late String path;
  const secret = 'Disposable exact credential: spaces, café, 世界, 🌍\n\u0000';
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-profile-',
    );
    profile = ProfileId.generate();
    path = '${directory.path}/profiles/${profile.value}.sqlite';
  });
  tearDown(() => directory.deleteSync(recursive: true));
  void write() => ProfileCredentialStore.write(
    root: directory.path,
    profile: profile,
    credential: secret,
  );
  String read() =>
      ProfileCredentialStore.read(root: directory.path, profile: profile);
  Matcher failure(ProfileCredentialFailure expected) => throwsA(
    isA<ProfileCredentialException>().having(
      (e) => e.failure,
      'failure',
      expected,
    ),
  );
  void chmod(String mode, String path) =>
      expect(Process.runSync('chmod', [mode, path]).exitCode, 0);

  test('device reconnect hint replaces only a protected regular file', () {
    final next = ProfileId.generate();
    DeviceProfileStore.write(directory.path, profile);
    DeviceProfileStore.write(directory.path, next);
    expect(DeviceProfileStore.read(directory.path), next);
    final hint = '${directory.path}/device-profile';
    chmod('644', hint);
    expect(
      () => DeviceProfileStore.write(directory.path, profile),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(hint).readAsStringSync().trim(), next.value);
    File(hint).deleteSync();
    final original = File('${directory.path}/other')
      ..writeAsStringSync(next.value);
    Link(hint).createSync(original.path);
    expect(
      () => DeviceProfileStore.write(directory.path, profile),
      throwsA(isA<FileSystemException>()),
    );
    expect(original.readAsStringSync(), next.value);
  });

  test('exact credential persists in the unchanged typed private format', () {
    write();
    expect(read(), secret);
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    expect(
      Directory('${directory.path}/profiles').statSync().mode & 0x1ff,
      0x1c0,
    );
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      expect(
        db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .single['name'],
        'credential',
      );
      expect(
        db
            .select('PRAGMA table_info(credential)')
            .map((r) => '${r['name']}:${r['type']}')
            .toList(),
        ['profile_id:TEXT', 'credential:TEXT'],
      );
      expect(db.select('PRAGMA journal_mode').single.values.single, 'delete');
    } finally {
      db.close();
    }
    expect(File('$path-wal').existsSync(), isFalse);
    expect(File('$path-journal').existsSync(), isFalse);
  });

  test('create-only writes never replace an enrolled credential', () {
    write();
    final before = File(path).readAsBytesSync();
    expect(
      () => ProfileCredentialStore.write(
        root: directory.path,
        profile: profile,
        credential: 'replacement disposable secret',
      ),
      failure(ProfileCredentialFailure.unavailable),
    );
    expect(File(path).readAsBytesSync(), before);
    expect(read(), secret);
  });

  test(
    'leading and inline BOM characters survive exact secret byte storage',
    () {
      for (final value in [
        '\uFEFF$secret',
        '\uFEFF\uFEFF$secret',
        'a\uFEFF$secret',
      ]) {
        final id = ProfileId.generate();
        ProfileCredentialStore.write(
          root: directory.path,
          profile: id,
          credential: value,
        );
        expect(
          ProfileCredentialStore.read(root: directory.path, profile: id),
          value,
        );
        final db = sqlite3.open(
          '${directory.path}/profiles/${id.value}.sqlite',
          mode: OpenMode.readOnly,
        );
        try {
          expect(
            db
                .select(
                  'SELECT CAST(credential AS BLOB) AS bytes FROM credential',
                )
                .single['bytes'],
            orderedEquals(utf8.encode(value)),
          );
        } finally {
          db.close();
        }
      }
    },
  );

  test('existing Rust-format credentials read without conversion', () {
    Directory('${directory.path}/profiles').createSync();
    chmod('700', '${directory.path}/profiles');
    final db = sqlite3.open(path);
    db.execute(
      'CREATE TABLE credential(profile_id TEXT PRIMARY KEY, credential TEXT NOT NULL) STRICT',
    );
    db.execute('INSERT INTO credential VALUES(?, ?)', [profile.value, secret]);
    db.close();
    chmod('600', path);
    final before = File(path).readAsBytesSync();
    expect(read(), secret);
    expect(File(path).readAsBytesSync(), before);
  });

  test('copied profile identity, symlinks and hard links are refused', () {
    write();
    final other = ProfileId.generate();
    final otherPath = '${directory.path}/profiles/${other.value}.sqlite';
    File(path).copySync(otherPath);
    expect(
      () => ProfileCredentialStore.read(root: directory.path, profile: other),
      failure(ProfileCredentialFailure.identityMismatch),
    );
    File(otherPath).deleteSync();
    Link(otherPath).createSync(path);
    expect(
      () => ProfileCredentialStore.read(root: directory.path, profile: other),
      failure(ProfileCredentialFailure.unavailable),
    );
    Link(otherPath).deleteSync();
    expect(Process.runSync('ln', [path, otherPath]).exitCode, 0);
    expect(read, failure(ProfileCredentialFailure.unavailable));
    File(otherPath).deleteSync();
    expect(read(), secret);
  });

  test('permissive credential file and profile directory are refused', () {
    write();
    chmod('644', path);
    expect(read, failure(ProfileCredentialFailure.unavailable));
    chmod('600', path);
    chmod('755', '${directory.path}/profiles');
    expect(read, failure(ProfileCredentialFailure.unavailable));
    chmod('700', '${directory.path}/profiles');
    expect(read(), secret);
  });

  test('missing or ambiguous credential rows never synthesize a secret', () {
    expect(read, failure(ProfileCredentialFailure.unavailable));
    expect(File(path).existsSync(), isFalse);
    write();
    final db = sqlite3.open(path);
    try {
      db.execute('INSERT INTO credential VALUES(?, ?)', [
        ProfileId.generate().value,
        secret,
      ]);
      expect(read, failure(ProfileCredentialFailure.identityMismatch));
      db.execute('DELETE FROM credential');
      expect(read, failure(ProfileCredentialFailure.identityMismatch));
    } finally {
      db.close();
    }
  });

  test('invalid Unicode is rejected before any credential file exists', () {
    expect(
      () => ProfileCredentialStore.write(
        root: directory.path,
        profile: profile,
        credential: String.fromCharCode(0xd800),
      ),
      failure(ProfileCredentialFailure.invalidText),
    );
    expect(File(path).existsSync(), isFalse);
  });

  test(
    'malformed stored UTF-8 fails instead of replacing credential bytes',
    () {
      write();
      final db = sqlite3.open(path);
      db.execute("UPDATE credential SET credential=CAST(x'ff' AS TEXT)");
      db.close();
      expect(read, failure(ProfileCredentialFailure.unavailable));
    },
  );

  test('driver and filesystem error diagnostics never contain credentials', () {
    write();
    try {
      ProfileCredentialStore.write(
        root: directory.path,
        profile: profile,
        credential: secret,
      );
      fail('Expected refusal');
    } on ProfileCredentialException catch (error) {
      expect('$error', 'ProfileCredentialException(unavailable)');
      expect('$error', isNot(contains(secret)));
      expect('$error', isNot(contains(path)));
    }
    final db = sqlite3.open(path);
    db.execute('DROP TABLE credential');
    db.close();
    expect(read, failure(ProfileCredentialFailure.unavailable));
  });
}
