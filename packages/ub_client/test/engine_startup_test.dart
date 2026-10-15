@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory root;
  late ProfileId profile;
  setUp(() {
    root = Directory('/tmp').createTempSync('ub-start-');
    profile = ProfileId.generate();
    ProfileCredentialStore.write(
      root: root.path,
      profile: profile,
      credential: 'Disposable startup credential',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));
  Matcher failure(LocalEngineFailure value) => throwsA(
    isA<LocalEngineException>().having((e) => e.failure, 'failure', value),
  );
  Future<LocalEngineClient> start(String helper) =>
      LocalEngineClient.ensureRunning(
        root: root.path,
        profile: profile,
        helper: helper,
        clientName: 'Disposable startup client',
        environment: const {'UB_USE_POSTGRES': 'false'},
      );
  String helper() {
    final file = File('${root.path}/universe-engine');
    file.writeAsStringSync(
      '#!/bin/sh\nprintf x >> "${root.path}/launched"\nexit 7\n',
    );
    expect(Process.runSync('chmod', ['700', file.path]).exitCode, 0);
    return file.path;
  }

  test(
    'unsafe endpoint or unavailable profile never launches a helper',
    () async {
      final executable = helper();
      File('${root.path}/engine.sock')
          .writeAsStringSync('Retained unrelated file');
      await expectLater(
        start(executable),
        failure(LocalEngineFailure.unsafeEndpoint),
      );
      expect(
        File('${root.path}/engine.sock').readAsStringSync(),
        'Retained unrelated file',
      );
      File('${root.path}/engine.sock').deleteSync();
      File('${root.path}/profiles/${profile.value}.sqlite').deleteSync();
      await expectLater(
        start(executable),
        failure(LocalEngineFailure.credentialUnavailable),
      );
      expect(File('${root.path}/launched').existsSync(), isFalse);
    },
  );

  test('invalid helper and client identity release bootstrap ownership without launching', () async {
    final executable = helper();
    await expectLater(
      start('universe-engine'),
      failure(LocalEngineFailure.helperUnavailable),
    );
    await expectLater(
      start('${root.path}/absent'),
      failure(LocalEngineFailure.helperUnavailable),
    );
    await expectLater(
      LocalEngineClient.ensureRunning(
        root: root.path,
        profile: profile,
        helper: executable,
        clientName: List.filled(65, 'é').join(),
      ),
      failure(LocalEngineFailure.handshakeFailed),
    );
    final lock = InstallationBootstrapLock.acquireExisting(root.path);
    lock.close();
    expect(File('${root.path}/launched').existsSync(), isFalse);
  });

  test(
    'failed detached helper is not repeatedly spawned and startup expires',
    () async {
      await expectLater(
        start(helper()),
        failure(LocalEngineFailure.startupTimeout),
      );
      expect(File('${root.path}/launched').readAsStringSync(), 'x');
      final lock = InstallationBootstrapLock.acquireExisting(root.path);
      lock.close();
    },
  );

  test('bootstrap contention is retried without taking installation service ownership', () async {
    final lock = InstallationBootstrapLock.acquireExisting(root.path);
    final pending = start('${root.path}/absent');
    final released = Future<void>.delayed(
      const Duration(milliseconds: 100),
      lock.close,
    );
    await expectLater(pending, failure(LocalEngineFailure.helperUnavailable));
    await released;
    final next = InstallationBootstrapLock.acquireExisting(root.path);
    next.close();
  });

  test('compiled concurrent clients launch one independent engine and reuse it after both clients exit', () async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:ub_client/local_engine.dart'),
    );
    final workspace = File.fromUri(library!).parent.parent.parent.parent.path;
    final engineEntry = '$workspace/apps/ub_engine/bin/universe-engine.dart';
    final engineBuild = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target',
      engineEntry,
      '--output',
      '${root.path}/engine-build',
      '--verbosity=error',
    ]);
    expect(
      engineBuild.exitCode,
      0,
      reason: 'Engine fixture compilation failed',
    );
    final engine = '${root.path}/engine-build/bundle/bin/universe-engine';
    final installation = '${root.path}/installation';
    const environment = {
      'PATH': '',
      'UB_USE_POSTGRES': 'false',
      'UB_POSTGRES_ENDPOINT': '',
    };
    final initialized = await Process.run(engine, [
      '--installation',
      installation,
      '--initialize',
    ], environment: environment);
    expect(initialized.exitCode, 0);
    expect(initialized.stderr, isEmpty);
    final author = ProfileId.parse((initialized.stdout as String).trim());
    final fixture = File('${root.path}/start_fixture.dart')
      ..writeAsStringSync('''
import 'dart:io';
import 'package:ub_client/local_engine.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_contracts/ub_contracts.dart';
Future<void> main(List<String> args) async {
  try {
    final helper = args[2] == 'sibling' ? await LocalEngineClient.siblingEngine() : args[2];
    final client = await LocalEngineClient.ensureRunning(root: args[0], profile: ProfileId.parse(args[1]), helper: helper, clientName: 'Compiled startup client');
    await client.call(const StatusEngineRequest());
    stdout.writeln(client.welcome.serviceInstance);
    await client.close();
  } on LocalEngineException catch (error) {
    stderr.writeln(error.failure.name);
    exitCode = 1;
  }
}
''');
    final clientBuild = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target',
      fixture.path,
      '--packages',
      '$workspace/.dart_tool/package_config.json',
      '--root-package',
      'ub_client',
      '--output',
      '${root.path}/client-build',
      '--verbosity=error',
    ]);
    expect(
      clientBuild.exitCode,
      0,
      reason: 'Client fixture compilation failed',
    );
    var clientBinary = '${root.path}/client-build/bundle/bin/start_fixture';
    if (Platform.isLinux) {
      final desktop = Directory('${root.path}/client-build/bundle/desktop')
        ..createSync();
      final moved = File(clientBinary)
          .renameSync('${desktop.path}/universe_builder');
      clientBinary = moved.path;
    }
    final installedHelper =
        File(
          '${root.path}/client-build/bundle/bin/universe-engine',
        )..writeAsStringSync(
          '#!/bin/sh\nprintf x >> "${root.path}/launches"\nprintf "%s" "\$\$" > "${root.path}/engine-pid"\nexec "$engine" "\$@"\n',
        );
    expect(Process.runSync('chmod', ['700', installedHelper.path]).exitCode, 0);
    LocalEngineClient? control;
    try {
      final results = await Future.wait(
        List.generate(
          2,
          (_) => Process.run(
            clientBinary,
            [installation, author.value, 'sibling'],
            workingDirectory: root.path,
            environment: environment,
          ).timeout(const Duration(seconds: 20)),
        ),
      );
      for (final result in results) {
        expect(result.exitCode, 0);
        expect(result.stderr, isEmpty);
      }
      expect(results.first.stdout, results.last.stdout);
      expect(File('${root.path}/launches').readAsStringSync(), 'x');
      control = await LocalEngineClient.connect(
        root: installation,
        profile: author,
        clientName: 'Disposable engine cleanup',
      );
      expect('${control.welcome.serviceInstance}\n', results.first.stdout);
      final reused = await Process.run(
        clientBinary,
        [installation, author.value, '/missing/universe-engine'],
        workingDirectory: root.path,
        environment: environment,
      ).timeout(const Duration(seconds: 10));
      expect(reused.exitCode, 0);
      expect(reused.stdout, results.first.stdout);
      expect(reused.stderr, isEmpty);
      expect(File('${root.path}/launches').readAsStringSync(), 'x');
      final enrolled =
          await control.call(const EnrollEngineRequest()) as CanonicalObject;
      final writer = ProfileId.parse(
        (enrolled.fields.singleWhere((f) => f.key == 'profile_id').value
                as CanonicalString)
            .value,
      );
      await control.call(RevokeEngineRequest(profileId: writer));
      final refused = await Process.run(
        clientBinary,
        [installation, writer.value, 'sibling'],
        workingDirectory: root.path,
        environment: environment,
      ).timeout(const Duration(seconds: 10));
      expect(refused.exitCode, 1);
      expect(refused.stdout, isEmpty);
      expect(refused.stderr, 'handshakeFailed\n');
      expect(File('${root.path}/launches').readAsStringSync(), 'x');

      final oldInstance = control.welcome.serviceInstance;
      final pid = int.parse(File('${root.path}/engine-pid').readAsStringSync());
      expect(Process.killPid(pid, ProcessSignal.sigkill), isTrue);
      await control.close();
      control = null;
      // Observe actual installation lock release before attempting stale recovery.
      final died = DateTime.now().add(const Duration(seconds: 5));
      SqliteInstallationStore? unlocked;
      while (unlocked == null && DateTime.now().isBefore(died)) {
        try {
          unlocked = SqliteInstallationStore.openExisting(installation);
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      expect(unlocked, isNotNull);
      unlocked!.close();
      expect(
        FileSystemEntity.typeSync(
          '$installation/engine.sock',
          followLinks: false,
        ),
        isNot(FileSystemEntityType.notFound),
      );
      final recovered = await Process.run(
        clientBinary,
        [installation, author.value, 'sibling'],
        workingDirectory: root.path,
        environment: environment,
      ).timeout(const Duration(seconds: 20));
      expect(recovered.exitCode, 0);
      expect(recovered.stderr, isEmpty);
      expect(recovered.stdout, isNot('$oldInstance\n'));
      expect(File('${root.path}/launches').readAsStringSync(), 'xx');
    } finally {
      control ??= await LocalEngineClient.connect(
        root: installation,
        profile: author,
        clientName: 'Disposable engine cleanup',
      );
      await control.call(const ShutdownEngineRequest());
      await control.close();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      SqliteInstallationStore? retained;
      while (retained == null && DateTime.now().isBefore(deadline)) {
        try {
          retained = SqliteInstallationStore.openExisting(installation);
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      expect(
        retained,
        isNotNull,
        reason: 'Shutdown must release installation ownership',
      );
      retained!.close();
      expect(
        FileSystemEntity.typeSync(
          '$installation/engine.sock',
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
