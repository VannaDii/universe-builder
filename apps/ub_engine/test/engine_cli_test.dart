@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_engine/engine_cli.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_settings.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory root;
  late List<String> output, errors;
  setUp(() {
    root = Directory('/tmp').createTempSync('ub-run-');
    output = [];
    errors = [];
  });
  tearDown(() => root.deleteSync(recursive: true));
  Future<int> run(
    List<String> args, {
    Map<String, String> environment = const {},
  }) => runEngine(
    args,
    environment: environment,
    output: output.add,
    error: errors.add,
  );
  List<String> initialize(String path) => [
    '--installation',
    path,
    '--initialize',
  ];
  Future<String> entrypoint() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:ub_engine/engine_cli.dart'),
    );
    return File.fromUri(uri!).parent.parent.uri
        .resolve('bin/universe-engine.dart')
        .toFilePath();
  }

  test('initialization prints only profile identity; repeat preserves authority and credential', () async {
    final path = '${root.path}/installation';
    expect(await run(initialize(path)), 0);
    final profile = ProfileId.parse(output.single);
    expect(errors, isEmpty);
    final secret = ProfileCredentialStore.read(root: path, profile: profile);
    expect(output.join(), isNot(contains(secret)));
    final authority = SqliteInstallationStore.openExisting(path);
    final instance = authority.instanceId;
    authority.close();
    output.clear();
    expect(await run(initialize(path)), 1);
    expect(output, isEmpty);
    expect(errors.single, isNot(contains(secret)));
    final retained = SqliteInstallationStore.openExisting(path);
    expect(retained.instanceId, instance);
    expect(retained.currentAuthor(), profile);
    retained.close();
    expect(ProfileCredentialStore.read(root: path, profile: profile), secret);
  });

  test('ordinary startup never initializes a missing installation', () async {
    final path = '${root.path}/absent';
    expect(await run(['--installation', path]), 1);
    expect(Directory(path).existsSync(), isFalse);
    expect(output, isEmpty);
  });

  test('invalid options never create authority', () async {
    final path = '${root.path}/absent';
    for (final args in <List<String>>[
      [],
      ['--initialize'],
      ['--installation'],
      ['--installation', path, '--fixture'],
      ['--installation', path, '--exit-on-stdin-close'],
      ['--installation', path, '--initialize', '--initialize'],
      ['--installation', path, '--installation', path],
      ['--installation='],
      ['--installation', path, 'extra'],
    ]) {
      expect(await run(args), 2);
      expect(Directory(path).existsSync(), isFalse);
    }
    output.clear();
    expect(await run(['--help']), 0);
    expect(output.single, contains('Usage: universe-engine'));
  });

  test('configuration failures precede creation and redact PostgreSQL credentials', () async {
    final path = '${root.path}/absent';
    const endpoint =
        'postgresql://disposable:private_password@db.example.test/world?sslmode=verify-full';
    for (final env in <Map<String, String>>[
      {'UB_USE_POSTGRES': 'invalid'},
      {'UB_USE_POSTGRES': 'true'},
      {
        'UB_USE_POSTGRES': 'true',
        'UB_POSTGRES_ENDPOINT': 'invalid private_password',
      },
      {'UB_USE_POSTGRES': 'true', 'UB_POSTGRES_ENDPOINT': endpoint},
    ]) {
      expect(await run(initialize(path), environment: env), 1);
      expect(Directory(path).existsSync(), isFalse);
      expect(output, isEmpty);
      expect(errors.last, isNot(contains('private_password')));
      expect(errors.last, isNot(contains(endpoint)));
    }
  });

  test('saved backend selection works; explicit selection bypasses corrupt settings', () async {
    final path = '${root.path}/installation';
    final settings = LocalSettingsStore.create(
      '$path/settings.sqlite',
      installationId: 'Disposable settings',
    );
    settings.save(
      usePostgres: true,
      endpoint: EncryptedPostgresEndpoint(
        keyReference: 'unused-disposable-key',
        ciphertext: [1],
        nonce: List.filled(12, 1),
        tag: List.filled(16, 1),
      ),
    );
    settings.close();
    expect(
      await run(
        initialize(path),
        environment: {
          'UB_POSTGRES_ENDPOINT': 'postgresql://user:password@db.example.test/world?sslmode=verify-full',
        },
      ),
      1,
    );
    expect(File('$path/installation.sqlite').existsSync(), isFalse);
    expect(errors.single, contains('PostgreSQL runtime'));
    File('$path/settings.sqlite')
        .writeAsStringSync('Disposable corrupted settings');
    errors.clear();
    expect(await run(initialize(path)), 1);
    expect(File('$path/installation.sqlite').existsSync(), isFalse);
    expect(
      await run(
        initialize(path),
        environment: {
          'UB_USE_POSTGRES': 'false',
          'UB_POSTGRES_ENDPOINT': 'invalid-unused',
        },
      ),
      0,
    );
    expect(
      File('$path/settings.sqlite').readAsStringSync(),
      'Disposable corrupted settings',
    );
  });

  test('compiled engine initializes, serves outside source tree and shuts down through author command and signal', () async {
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target',
      await entrypoint(),
      '--output',
      '${root.path}/compiled',
      '--verbosity=error',
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: 'Standalone engine compilation failed',
    );
    final binary = '${root.path}/compiled/bundle/bin/universe-engine';
    final path = '${root.path}/installation';
    const env = {
      'PATH': '',
      'UB_USE_POSTGRES': 'false',
      'UB_POSTGRES_ENDPOINT': '',
    };
    final initialized = await Process.run(
      binary,
      initialize(path),
      workingDirectory: root.path,
      environment: env,
    );
    expect(initialized.exitCode, 0);
    expect(initialized.stderr, isEmpty);
    final profile = ProfileId.parse((initialized.stdout as String).trim());
    final secret = ProfileCredentialStore.read(root: path, profile: profile);
    for (final stopMode in ['author', 'interrupt', 'terminate']) {
      final process = await Process.start(
        binary,
        ['--installation=$path'],
        workingDirectory: root.path,
        environment: env,
      );
      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();
      int? ended;
      final exit = process.exitCode.then((value) {
        ended = value;
        return value;
      });
      LocalEngineClient? connection;
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (connection == null &&
            DateTime.now().isBefore(deadline) &&
            ended == null) {
          try {
            connection = await LocalEngineClient.connect(
              root: path,
              profile: profile,
              clientName: 'Disposable compiled client',
            );
          } on LocalEngineException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        expect(
          connection,
          isNotNull,
          reason: 'Compiled engine did not become available',
        );
        await connection!.call(const StatusEngineRequest());
        final blockedInitialization = await Process.run(
          binary,
          initialize(path),
          workingDirectory: root.path,
          environment: env,
        );
        expect(blockedInitialization.exitCode, 1);
        expect(blockedInitialization.stdout, isEmpty);
        expect(blockedInitialization.stderr, isNot(contains(secret)));
        await connection.call(const StatusEngineRequest());
        if (stopMode != 'author') {
          expect(
            process.kill(
              stopMode == 'interrupt'
                  ? ProcessSignal.sigint
                  : ProcessSignal.sigterm,
            ),
            isTrue,
          );
        } else {
          await connection.call(const ShutdownEngineRequest());
        }
        expect(await exit.timeout(const Duration(seconds: 10)), 0);
        expect(await stdoutText, isEmpty);
        expect(await stderrText, isEmpty);
        expect(
          FileSystemEntity.typeSync('$path/engine.sock', followLinks: false),
          FileSystemEntityType.notFound,
        );
      } finally {
        await connection?.close();
        if (ended == null) {
          process.kill(ProcessSignal.sigkill);
          await exit.timeout(const Duration(seconds: 10));
        }
        expect(await stdoutText, isNot(contains(secret)));
        expect(await stderrText, isNot(contains(secret)));
      }
    }
    final store = SqliteInstallationStore.openExisting(path);
    expect(store.currentAuthor(), profile);
    store.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
