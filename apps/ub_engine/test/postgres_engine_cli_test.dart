@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  test(
    'compiled PostgreSQL launcher initializes, reconnects and shuts down without SQLite fallback',
    () async {
      final root = Directory('/tmp').createTempSync('ub-pg-launcher-');
      final database =
          'ub_engine_${OperationId.generate().value.replaceAll('-', '')}';
      final observer = await Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: port!,
          database: 'ub_disposable',
          username: 'postgres',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      var created = false;
      try {
        await observer.execute('CREATE DATABASE $database');
        created = true;
        final uri = await Isolate.resolvePackageUri(
          Uri.parse('package:ub_engine/engine_cli.dart'),
        );
        final source = File.fromUri(uri!).parent.parent.uri
            .resolve('bin/universe-engine.dart')
            .toFilePath();
        final build = await Process.run(Platform.resolvedExecutable, [
          'build',
          'cli',
          '--target',
          source,
          '--output',
          '${root.path}/compiled',
          '--verbosity=error',
        ]);
        expect(
          build.exitCode,
          0,
          reason: 'Standalone PostgreSQL engine compilation failed',
        );
        final binary = '${root.path}/compiled/bundle/bin/universe-engine';
        final installation = '${root.path}/installation';
        final env = {
          'PATH': '',
          'UB_USE_POSTGRES': 'true',
          'UB_POSTGRES_ENDPOINT':
              'postgresql://postgres@127.0.0.1:$port/$database?sslmode=disable',
        };
        final options = [
          '--installation',
          installation,
          '--allow-loopback-postgres-development',
        ];
        Future<ProcessResult> run(List<String> arguments) => Process.run(
          binary,
          arguments,
          workingDirectory: root.path,
          environment: env,
        );
        // Ordinary startup never provisions absent authority or local files.
        expect((await run(options)).exitCode, 1);
        expect(Directory(installation).existsSync(), isFalse);
        // Unverified TLS remains opt-in, even for a local database.
        expect(
          (await run(['--installation', installation, '--initialize']))
              .exitCode,
          1,
        );
        expect(Directory(installation).existsSync(), isFalse);
        final initialized = await run([...options, '--initialize']);
        expect(initialized.exitCode, 0);
        expect(initialized.stderr, isEmpty);
        final profile = ProfileId.parse((initialized.stdout as String).trim());
        final credential = ProfileCredentialStore.read(
          root: installation,
          profile: profile,
        );
        expect(initialized.stdout, isNot(contains(credential)));
        final repeated = await run([...options, '--initialize']);
        expect(repeated.exitCode, 1);
        expect(repeated.stdout, isEmpty);
        expect(repeated.stderr, isNot(contains(credential)));
        for (final stopping in ['author', 'terminate']) {
          final device = await run([...options, '--device-profile']);
          expect(device.exitCode, 0);
          expect((device.stdout as String).trim(), profile.value);
          expect(device.stderr, isEmpty);
          final process = await Process.start(
            binary,
            options,
            workingDirectory: root.path,
            environment: env,
          );
          final stdout = process.stdout.transform(utf8.decoder).join();
          final stderr = process.stderr.transform(utf8.decoder).join();
          int? ended;
          final exit = process.exitCode.then((value) {
            ended = value;
            return value;
          });
          LoopbackEngineClient? client;
          try {
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            while (client == null &&
                ended == null &&
                DateTime.now().isBefore(deadline)) {
              try {
                client = await LoopbackEngineClient.discover(
                  root: installation,
                  profile: profile,
                  clientName: 'Disposable PostgreSQL launcher client',
                );
              } on LocalEngineException catch (failure) {
                if (failure.failure != LocalEngineFailure.unavailable) rethrow;
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
            }
            expect(
              client,
              isNotNull,
              reason: 'PostgreSQL engine did not become available',
            );
            await client!.call(const StatusEngineRequest());
            // Retained authenticated device setup works while the service is active.
            final retained = await run([...options, '--device-profile']);
            expect(retained.exitCode, 0);
            expect((retained.stdout as String).trim(), profile.value);
            final competing = await run(options);
            expect(competing.exitCode, 1);
            await client.call(const StatusEngineRequest());
            if (stopping == 'author') {
              await client.call(const ShutdownEngineRequest());
            } else {
              expect(process.kill(ProcessSignal.sigterm), isTrue);
            }
            expect(await exit.timeout(const Duration(seconds: 10)), 0);
            expect(await stdout, isEmpty);
            expect(await stderr, isEmpty);
            expect(
              File('$installation/engine-http.json').existsSync(),
              isFalse,
            );
            expect(
              File('$installation/installation.sqlite').existsSync(),
              isFalse,
            );
          } finally {
            await client?.close();
            if (ended == null) {
              process.kill(ProcessSignal.sigkill);
              await exit.timeout(const Duration(seconds: 10));
            }
            expect(await stdout, isNot(contains(credential)));
            expect(await stderr, isNot(contains(credential)));
          }
        }
        expect(
          ProfileCredentialStore.read(root: installation, profile: profile),
          credential,
        );
        // Missing profile secrets fail visibly rather than enrolling a replacement.
        File('$installation/profiles/${profile.value}.sqlite').deleteSync();
        final missing = await run([...options, '--device-profile']);
        expect(missing.exitCode, 1);
        expect(missing.stdout, isEmpty);
        expect((await run([...options, '--initialize'])).exitCode, 1);
        await observer.execute('DROP DATABASE $database');
        created = false;
        await observer.execute('CREATE DATABASE $database');
        created = true;
        Directory(installation).deleteSync(recursive: true);
        final freshDevice = await run([...options, '--device-profile']);
        expect(freshDevice.exitCode, 0);
        expect(freshDevice.stderr, isEmpty);
        final freshProfile = ProfileId.parse(
          (freshDevice.stdout as String).trim(),
        );
        expect(freshProfile, isNot(profile));
        expect(DeviceProfileStore.read(installation), freshProfile);
        final reconnect = await run([...options, '--device-profile']);
        expect(reconnect.exitCode, 0);
        expect((reconnect.stdout as String).trim(), freshProfile.value);
        expect(File('$installation/installation.sqlite').existsSync(), isFalse);
      } finally {
        try {
          if (created) await observer.execute('DROP DATABASE $database');
        } finally {
          await observer.close();
          root.deleteSync(recursive: true);
        }
      }
    },
    skip: port == null ? 'Requires disposable UB_TEST_POSTGRES_PORT' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
