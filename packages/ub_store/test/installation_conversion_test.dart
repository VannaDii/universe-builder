@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/src/installation_conversion.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late String source, destination, databasePath;
  late ProfileId author, revoked, unenrolled;
  late UniverseId universe;
  late WorldId firstWorld, secondWorld;
  late RecordId firstEntity, secondEntity;
  const secret = 'Disposable exact café 😀\r\n\u0000';
  String credential(ProfileId profile) => '$secret:${profile.value}';
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-installation-conversion-',
    );
    privateDirectory(root.path);
    source = privateDirectory('${root.path}/source');
    privateDirectory('$source/profiles');
    destination = '${root.path}/converted';
    databasePath = '$source/installation.sqlite';
    protectedFile(databasePath, createNew: true);
    author = ProfileId.generate();
    revoked = ProfileId.generate();
    unenrolled = ProfileId.generate();
    universe = UniverseId.generate();
    firstWorld = WorldId.generate();
    secondWorld = WorldId.generate();
    firstEntity = RecordId.generate();
    secondEntity = RecordId.generate();
    final database = sqlite3.open(databasePath);
    try {
      database.execute('''
CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE profiles(id TEXT PRIMARY KEY,hash TEXT NOT NULL,author INTEGER NOT NULL,revoked INTEGER NOT NULL);
CREATE TABLE catalog(id TEXT PRIMARY KEY,name TEXT NOT NULL,path TEXT NOT NULL,device TEXT NOT NULL,inode TEXT NOT NULL);
CREATE TABLE aliases(key TEXT PRIMARY KEY,universe TEXT NOT NULL);
CREATE TABLE grants(profile TEXT,universe TEXT,worlds TEXT,propose INTEGER,edit INTEGER,protected INTEGER);
CREATE TABLE grant_limits(profile TEXT,universe TEXT,limits TEXT);
CREATE TABLE purge_pending(universe TEXT,path TEXT,device TEXT,inode TEXT);
CREATE TABLE audit(sequence INTEGER PRIMARY KEY,actor TEXT,action TEXT,target TEXT);
''');
      database.execute('INSERT INTO settings VALUES(?,?)', [
        'normalization',
        selectorNormalizationVersion,
      ]);
      database.execute('INSERT INTO catalog VALUES(?,?,?,?,?)', [
        universe.value,
        'Retained universe',
        '/retained/original.sqlite',
        '123',
        '456',
      ]);
      database.execute('INSERT INTO aliases VALUES(?,?)', [
        'retained universe',
        universe.value,
      ]);
      for (final profile in [author, revoked]) {
        database.execute('INSERT INTO profiles VALUES(?,?,?,?)', [
          profile.value,
          sha256.convert(utf8.encode(credential(profile))).toString(),
          profile == author ? 1 : 0,
          profile == revoked ? 1 : 0,
        ]);
      }
      database.execute('INSERT INTO grants VALUES(?,?,?,1,1,0)', [
        revoked.value,
        universe.value,
        jsonEncode([secondWorld.value, firstWorld.value]),
      ]);
      database.execute('INSERT INTO grant_limits VALUES(?,?,?)', [
        revoked.value,
        universe.value,
        jsonEncode({
          'entities': [secondEntity.value, firstEntity.value],
          'predicates': <String>[],
          'continuities': null,
          'expires_at': 42,
          'delegated_commit': false,
          'allow_shared': true,
        }),
      ]);
      database.execute('INSERT INTO audit VALUES(7,?,?,?)', [
        author.value,
        'revoke',
        revoked.value,
      ]);
    } finally {
      database.close();
    }
    for (final profile in [author, revoked, unenrolled]) {
      final path = '$source/profiles/${profile.value}.json';
      protectedFile(path, createNew: true);
      File(path).writeAsStringSync(
        jsonEncode({
          'format_version': 1,
          'profile_id': profile.value,
          'credential': credential(profile),
        }),
        flush: true,
      );
    }
  });
  tearDown(() => root.deleteSync(recursive: true));
  void edit(void Function(Database) action) {
    final database = sqlite3.open(databasePath);
    try {
      action(database);
    } finally {
      database.close();
    }
  }

  Map<String, List<int>> originals() => {
    databasePath: File(databasePath).readAsBytesSync(),
    for (final file in Directory('$source/profiles').listSync())
      file.path: File(file.path).readAsBytesSync(),
  };
  void unchanged(Map<String, List<int>> before) {
    for (final entry in before.entries) {
      expect(File(entry.key).readAsBytesSync(), orderedEquals(entry.value));
    }
  }

  void noStages() => expect(
    root.listSync().where(
      (entry) => entry.uri.pathSegments.any(
        (part) => part.startsWith('.installation-conversion-'),
      ),
    ),
    isEmpty,
  );
  void refused() {
    final before = originals();
    Object? caught;
    try {
      convertInstallation(source, destination);
    } on Object catch (error) {
      caught = error;
    }
    expect(caught, isA<InstallationConversionException>());
    expect(caught.toString(), isNot(contains(secret)));
    expect(Directory(destination).existsSync(), isFalse);
    unchanged(before);
    noStages();
  }

  test('converts exact authority credentials and ordered limits without moving catalog packages', () {
    final before = originals();
    for (final path in before.keys) {
      expect(Process.runSync('chmod', ['400', path]).exitCode, 0);
    }
    final report = convertInstallation(source, destination).toText();
    expect(report, contains('"profiles":2'));
    expect(report, contains('"credentials":3'));
    expect(report, contains('"grants":1'));
    expect(report, contains('"instance_identity_established":true'));
    expect(report, isNot(contains(secret)));
    unchanged(before);
    final store = SqliteInstallationStore.openExisting(destination);
    final identity = store.instanceId;
    try {
      expect(store.profile(author)!.author, isTrue);
      expect(store.profile(revoked)!.revoked, isTrue);
      expect(store.profile(unenrolled), isNull);
      final grant = store.readGrant(revoked, universe);
      expect(grant.worlds, [secondWorld, firstWorld]);
      expect(grant.propose, isTrue);
      expect(grant.edit, isTrue);
      expect(grant.protected, isFalse);
      expect(grant.limits.entities, [secondEntity, firstEntity]);
      expect(grant.limits.predicates, isEmpty);
      expect(grant.limits.continuities, isNull);
      expect(grant.limits.expiresAt, BigInt.from(42));
      expect(grant.limits.delegatedCommit, isFalse);
      expect(grant.limits.allowShared, isTrue);
    } finally {
      store.close();
    }
    final restarted = SqliteInstallationStore.openExisting(destination);
    try {
      expect(restarted.instanceId, identity);
    } finally {
      restarted.close();
    }
    for (final profile in [author, revoked, unenrolled]) {
      expect(
        ProfileCredentialStore.read(root: destination, profile: profile),
        credential(profile),
      );
    }
    final database = sqlite3.open(
      '$destination/installation.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(
        database.select('SELECT path,device,inode FROM catalog').single.values,
        ['/retained/original.sqlite', '123', '456'],
      );
      expect(
        database
            .select('SELECT sequence,actor,action,target FROM audit')
            .single
            .values,
        [7, author.value, 'revoke', revoked.value],
      );
    } finally {
      database.close();
    }
    expect(Directory('$destination/packages').listSync(), isEmpty);
    noStages();
  });

  test(
    'retains existing installation identity and all-versus-empty grant scope',
    () {
      final identity = OperationId.generate();
      edit((db) {
        db.execute("INSERT INTO settings VALUES('installation_instance',?)", [
          identity.value,
        ]);
        db.execute('UPDATE grants SET worlds=NULL');
        db.execute('UPDATE grant_limits SET limits=?', [
          jsonEncode({
            'entities': <String>[],
            'predicates': null,
            'continuities': <String>[],
            'expires_at': '18446744073709551615',
            'delegated_commit': false,
            'allow_shared': false,
          }),
        ]);
      });
      // Historical u64 expiry is a JSON number, including values beyond JS precision.
      edit(
        (db) => db.execute(
          'UPDATE grant_limits SET limits=replace(limits,?,?)',
          ['"18446744073709551615"', '18446744073709551615'],
        ),
      );
      expect(
        convertInstallation(source, destination).toText(),
        contains('"instance_identity_established":false'),
      );
      final store = SqliteInstallationStore.openExisting(destination);
      try {
        expect(store.instanceId, identity);
        final grant = store.readGrant(revoked, universe);
        expect(grant.worlds, isNull);
        expect(grant.limits.entities, isEmpty);
        expect(grant.limits.predicates, isNull);
        expect(grant.limits.continuities, isEmpty);
        expect(grant.limits.expiresAt, BigInt.parse('18446744073709551615'));
      } finally {
        store.close();
      }
      noStages();
    },
  );

  test('refuses pending purges populated previews and unknown evidence tables', () {
    edit(
      (db) => db.execute('INSERT INTO purge_pending VALUES(?,?,?,?)', [
        universe.value,
        '/retained/original.sqlite',
        '123',
        '456',
      ]),
    );
    refused();
    edit(
      (db) => db.execute(
        'DELETE FROM purge_pending; CREATE TABLE import_preview(value TEXT); INSERT INTO import_preview VALUES(\'retained preview\')',
      ),
    );
    refused();
    edit(
      (db) => db.execute(
        'DELETE FROM import_preview; CREATE TABLE unknown_evidence(value TEXT)',
      ),
    );
    refused();
  });

  test('refuses invalid grant flags unknown limits and orphan limits without coercing authority', () {
    edit((db) => db.execute('UPDATE grants SET edit=2'));
    refused();
    edit(
      (db) => db.execute(
        'UPDATE grants SET edit=1; UPDATE grant_limits SET limits=\'{"unknown":true}\'',
      ),
    );
    refused();
    edit((db) => db.execute('DELETE FROM grants'));
    refused();
  });

  test('missing credentials mismatched hashes and filename identity mismatches prevent publication', () {
    File('$source/profiles/${author.value}.json').deleteSync();
    refused();
    final path = '$source/profiles/${author.value}.json';
    protectedFile(path, createNew: true);
    File(path).writeAsStringSync(
      jsonEncode({
        'format_version': 1,
        'profile_id': author.value,
        'credential': 'Different disposable secret',
      }),
    );
    refused();
    File(path).writeAsStringSync(
      jsonEncode({
        'format_version': 1,
        'profile_id': unenrolled.value,
        'credential': credential(author),
      }),
    );
    refused();
  });

  test('credential inventory changes and publication races cannot admit a partial installation', () {
    final before = originals();
    expect(
      () => convertInstallationWithHook(source, destination, (point) {
        if (point == InstallationConversionPoint.beforePublish) {
          File('$source/profiles/${unenrolled.value}.json').deleteSync();
        }
      }),
      throwsA(
        isA<InstallationConversionException>().having(
          (e) => e.failure,
          'failure',
          InstallationConversionFailure.sourceChanged,
        ),
      ),
    );
    expect(Directory(destination).existsSync(), isFalse);
    noStages();
    final path = '$source/profiles/${unenrolled.value}.json';
    protectedFile(path, createNew: true);
    File(path).writeAsBytesSync(before[path]!);
    expect(
      () => convertInstallationWithHook(source, destination, (point) {
        if (point == InstallationConversionPoint.beforePublish) {
          Directory(destination).createSync();
        }
      }),
      throwsA(isA<InstallationConversionException>()),
    );
    expect(Directory(destination).listSync(), isEmpty);
    unchanged(before);
    noStages();
  });

  test('changed source database and changed credential bytes are detected before publication', () {
    final before = originals();
    expect(
      () => convertInstallationWithHook(source, destination, (point) {
        if (point != InstallationConversionPoint.beforePublish) return;
        File(databasePath).renameSync('$databasePath.retained');
        File('$databasePath.retained').copySync(databasePath);
        edit(
          (db) => db.execute("INSERT INTO settings VALUES('changed','source')"),
        );
      }),
      throwsA(
        isA<InstallationConversionException>().having(
          (e) => e.failure,
          'failure',
          InstallationConversionFailure.sourceChanged,
        ),
      ),
    );
    expect(Directory(destination).existsSync(), isFalse);
    expect(
      File('$databasePath.retained').readAsBytesSync(),
      orderedEquals(before[databasePath]!),
    );
    File(databasePath).deleteSync();
    File('$databasePath.retained').renameSync(databasePath);
    noStages();
    expect(
      () => convertInstallationWithHook(source, destination, (point) {
        if (point == InstallationConversionPoint.beforePublish) {
          File('$source/profiles/${unenrolled.value}.json')
              .writeAsStringSync('Changed retained credential');
        }
      }),
      throwsA(
        isA<InstallationConversionException>().having(
          (e) => e.failure,
          'failure',
          InstallationConversionFailure.sourceChanged,
        ),
      ),
    );
    expect(Directory(destination).existsSync(), isFalse);
    noStages();
  });

  test('interruption after construction cleans only private staging', () {
    final before = originals();
    expect(
      () => convertInstallationWithHook(source, destination, (point) {
        if (point == InstallationConversionPoint.constructed) {
          throw StateError('Interrupted disposable conversion');
        }
      }),
      throwsA(isA<InstallationConversionException>()),
    );
    unchanged(before);
    expect(Directory(destination).existsSync(), isFalse);
    noStages();
  });
}
