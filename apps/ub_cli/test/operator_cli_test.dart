@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_cli/operator_cli.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late String unusedInstallation, source, destination;
  late ProfileId profile;
  late List<String> output, errors;
  const secret = 'Disposable CLI credential café 😀\r\n\u0000';
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-operator-cli-',
    );
    privateDirectory(root.path);
    unusedInstallation = '${root.path}/unused-installation';
    source = '${root.path}/source';
    destination = '${root.path}/destination';
    profile = ProfileId.generate();
    output = [];
    errors = [];
  });
  tearDown(() => root.deleteSync(recursive: true));
  int run(List<String> arguments) =>
      runOperatorCli(arguments, output: output.add, error: errors.add);
  List<String> command(String name) => [
    '--installation',
    unusedInstallation,
    name,
    source,
    destination,
  ];
  void createCredential() {
    protectedFile(source, createNew: true);
    File(source).writeAsStringSync(
      jsonEncode({
        'format_version': 1,
        'profile_id': profile.value,
        'credential': secret,
      }),
      flush: true,
    );
  }

  void unused() => expect(Directory(unusedInstallation).existsSync(), isFalse);
  Future<String> entrypoint() async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:ub_cli/operator_cli.dart'),
    );
    return File.fromUri(library!).parent.parent.uri
        .resolve('bin/universe.dart')
        .toFilePath();
  }

  test('credential command preserves exact secret and returns only the conversion report', () {
    createCredential();
    final before = File(source).readAsBytesSync();
    expect(run(command('convert-credential')), 0);
    expect(errors, isEmpty);
    final report = jsonDecode(output.single) as Map<String, dynamic>;
    expect(report['source_sha256'], sha256.convert(before).toString());
    expect(report['credential_verified'], isTrue);
    expect(output.single, isNot(contains(secret)));
    expect(File(source).readAsBytesSync(), orderedEquals(before));
    final target = '${root.path}/target';
    privateDirectory(target);
    privateDirectory('$target/profiles');
    File(destination).renameSync('$target/profiles/${profile.value}.sqlite');
    expect(ProfileCredentialStore.read(root: target, profile: profile), secret);
    unused();
  });

  test('package command converts a private retained universe without engine registration', () {
    final original = OwnedSqliteDatabase.create(source);
    final universe = UniverseId.generate(),
        continuity = ContinuityId.generate();
    try {
      final journal = SqliteJournal(original.database, universe);
      original.database.execute('BEGIN IMMEDIATE');
      journal.initialize(
        'Retained CLI universe',
        continuity,
        PrincipalId.generate(),
      );
      original.database.execute(
        'COMMIT; PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE',
      );
    } finally {
      original.close();
    }
    final before = File(source).readAsBytesSync();
    expect(run(command('convert-package')), 0);
    expect(errors, isEmpty);
    expect(
      (jsonDecode(output.single) as Map<String, dynamic>)['original_preserved'],
      isTrue,
    );
    final target = OwnedSqliteDatabase.openExisting(destination);
    try {
      target.recover();
      expect(target.universeId, universe);
    } finally {
      target.close();
    }
    expect(File(source).readAsBytesSync(), orderedEquals(before));
    unused();
  });

  test('installation command retains unenrolled credentials and installation identity', () {
    final store = SqliteInstallationStore.create(source);
    final identity = store.instanceId;
    store.close();
    ProfileCredentialStore.write(
      root: source,
      profile: profile,
      credential: secret,
    );
    expect(run(command('convert-installation')), 0);
    expect(errors, isEmpty);
    expect(
      (jsonDecode(output.single) as Map<String, dynamic>)['credentials'],
      1,
    );
    final target = SqliteInstallationStore.openExisting(destination);
    try {
      expect(target.instanceId, identity);
      expect(target.profile(profile), isNull);
    } finally {
      target.close();
    }
    expect(
      ProfileCredentialStore.read(root: destination, profile: profile),
      secret,
    );
    unused();
  });

  test('help and invalid arguments have conventional exit codes without touching inputs', () {
    createCredential();
    final before = File(source).readAsBytesSync();
    expect(run(['--help']), 0);
    expect(output.single, contains('convert-package'));
    output.clear();
    expect(run(['convert-package', '--help']), 0);
    output.clear();
    for (final arguments in <List<String>>[
      [],
      ['convert-package', source, destination],
      ['--unknown', secret],
      ['--installation'],
      ['--installation=', 'convert-package', source, destination],
      [
        '--installation',
        unusedInstallation,
        '--installation',
        unusedInstallation,
        'convert-package',
        source,
        destination,
      ],
      ['--installation', unusedInstallation, 'shutdown'],
      [...command('convert-package'), 'extra'],
      ['--installation', unusedInstallation, 'convert-package', source, ''],
      [
        '--installation',
        unusedInstallation,
        'convert-package',
        source,
        '\u0000',
      ],
    ]) {
      expect(run(arguments), 2);
      expect(output, isEmpty);
      expect(errors.last, isNot(contains(secret)));
    }
    expect(File(source).readAsBytesSync(), orderedEquals(before));
    expect(File(destination).existsSync(), isFalse);
    unused();
  });

  test('equal-sign global options and literal path delimiter retain the existing interface', () {
    createCredential();
    expect(
      run([
        '--installation=$unusedInstallation',
        '--profile=unused-offline-profile',
        'convert-credential',
        '--',
        source,
        destination,
      ]),
      0,
    );
    expect(errors, isEmpty);
    unused();
  });

  test('malformed credential and occupied destination errors are redacted', () {
    protectedFile(source, createNew: true);
    File(source).writeAsStringSync(secret);
    expect(run(command('convert-credential')), 1);
    expect(output, isEmpty);
    expect(errors.single, isNot(contains(secret)));
    File(destination).writeAsStringSync('Retained existing target');
    errors.clear();
    expect(run(command('convert-package')), 1);
    expect(errors.single, isNot(contains(secret)));
    expect(File(destination).readAsStringSync(), 'Retained existing target');
    unused();
  });

  test('real Dart process runs offline conversion without resolving engine configuration', () async {
    createCredential();
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        '--verbosity=error',
        await entrypoint(),
        ...command('convert-credential'),
      ],
      environment: {
        'UB_USE_POSTGRES': 'true',
        'UB_POSTGRES_ENDPOINT': 'invalid-disposable-endpoint',
      },
    );
    expect(result.exitCode, 0, reason: 'Dart CLI subprocess failed');
    expect(
      (jsonDecode(result.stdout as String)
          as Map<String, dynamic>)['credential_verified'],
      isTrue,
    );
    expect(result.stderr, isEmpty);
    expect(result.stdout, isNot(contains(secret)));
    unused();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('compiled standalone operator bundle runs without a source-tree working directory', () async {
    createCredential();
    final binary = '${root.path}/compiled/bundle/bin/universe';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target',
      await entrypoint(),
      '--output',
      '${root.path}/compiled',
      '--verbosity=error',
    ]);
    expect(compiled.exitCode, 0, reason: 'Standalone CLI compilation failed');
    final result = await Process.run(
      binary,
      command('convert-credential'),
      workingDirectory: root.path,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(
      (jsonDecode(result.stdout as String)
          as Map<String, dynamic>)['credential_verified'],
      isTrue,
    );
    expect(result.stdout, isNot(contains(secret)));
    unused();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
