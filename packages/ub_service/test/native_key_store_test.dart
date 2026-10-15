@TestOn('vm && (mac-os || linux)')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/native_credentials.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_store/local_settings.dart';

void main() {
  const keys = NativeInstallationKeyStore();

  if (Platform.isLinux &&
      Platform.environment['UB_TEST_SECRET_SERVICE'] != 'true') {
    test(
      'Linux Secret Service fixture',
      () {},
      skip: 'Enable only on an isolated disposable session bus and keyring.',
    );
    return;
  }

  test(
    'headless OS key decrypts a restarted encrypted configuration',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'universe-builder-keychain-',
      );
      var settings = LocalSettingsStore.create(
        '${directory.path}/settings.sqlite',
        installationId: 'disposable-keychain-installation',
      );
      String? reference;
      try {
        final key = await InstallationEncryptionKey.generate();
        reference = await keys.storeNew(key);
        expect(reference, matches(r'^ub-installation-key-v1-[0-9a-f]{32}$'));
        final restored = await keys.read(reference);
        expect(restored, isNotNull);
        expect(
          await restored!.exportForCredentialStore(),
          await key.exportForCredentialStore(),
        );
        final cipher = PostgresEndpointEncryption();
        const endpoint = Credential(
          'postgresql://disposable_user:disposable_password@localhost/db',
        );
        settings.save(
          usePostgres: true,
          endpoint: await cipher.encrypt(
            endpoint: endpoint,
            installationId: settings.read().installationId,
            keyReference: reference,
            key: key,
          ),
        );
        settings.close();
        settings = LocalSettingsStore.openExisting(
          '${directory.path}/settings.sqlite',
        );
        final saved = settings.read();
        final resolved = await LocalBackendConfiguration.resolve(
          environment: {},
          settings: settings,
        ) as PostgresConfiguration;
        expect(resolved.endpoint.expose(), endpoint.expose());
        expect(await keys.remove(reference), isTrue);
        expect(await keys.read(reference), isNull);
        expect(await keys.remove(reference), isFalse);
        await expectLater(
          LocalBackendConfiguration.resolve(
            environment: {},
            settings: settings,
          ),
          throwsA(
            isA<ConfigurationException>().having(
              (e) => e.failure,
              'failure',
              ConfigurationFailure.savedEndpointUnavailable,
            ),
          ),
        );
        expect(settings.read().usePostgres, isTrue);
        expect(
          settings.read().endpoint!.ciphertext,
          saved.endpoint!.ciphertext,
        );
      } finally {
        if (reference != null) await keys.remove(reference);
        settings.close();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'compiled headless process reads the same OS key after restart',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'universe-builder-key-process-',
      );
      final path = '${directory.path}/settings.sqlite';
      final buildPath = '${directory.path}/build';
      final runtime = File(Platform.resolvedExecutable);
      final dart = runtime.uri.pathSegments.last == 'dartvm'
          ? '${runtime.parent.path}/dart'
          : runtime.path;
      String? executable;
      var created = false;
      try {
        final build = await Process.run(dart, [
          'build',
          'cli',
          '-o',
          buildPath,
          '--target',
          'test/helpers/key_store_process.dart',
        ]);
        expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
        executable = '$buildPath/bundle/bin/key_store_process';
        final creation = await Process.run(executable, ['create', path]);
        created = creation.exitCode == 0;
        expect(
          creation.exitCode,
          0,
          reason: '${creation.stdout}\n${creation.stderr}',
        );
        expect('${creation.stdout}'.trim(), 'created');
        final restarted = await Process.run(executable, ['read', path]);
        expect(
          restarted.exitCode,
          0,
          reason: '${restarted.stdout}\n${restarted.stderr}',
        );
        expect('${restarted.stdout}'.trim(), 'read');
        if (Platform.isLinux) {
          final unavailable = await Process.run(
            executable,
            ['read', path],
            environment: {
              'DBUS_SESSION_BUS_ADDRESS':
                  'unix:path=${directory.path}/absent-session-bus',
            },
          );
          expect(unavailable.exitCode, isNot(0));
          expect(unavailable.stdout, isEmpty);
          expect(unavailable.stderr, contains('savedEndpointUnavailable'));
          expect(unavailable.stderr, isNot(contains('disposable_password')));
          expect((await Process.run(executable, ['read', path])).exitCode, 0);
        }
      } finally {
        if (created && executable != null) {
          final removed = await Process.run(executable, ['remove', path]);
          expect(
            removed.exitCode,
            0,
            reason: '${removed.stdout}\n${removed.stderr}',
          );
        }
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('two installation keys remain isolated and cleanup removes only its account', () async {
    String? first;
    String? second;
    try {
      final firstKey = await InstallationEncryptionKey.generate();
      final secondKey = await InstallationEncryptionKey.generate();
      first = await keys.storeNew(firstKey);
      second = await keys.storeNew(secondKey);
      expect(first, isNot(second));
      expect(
        await (await keys.read(first))!.exportForCredentialStore(),
        await firstKey.exportForCredentialStore(),
      );
      expect(
        await (await keys.read(second))!.exportForCredentialStore(),
        await secondKey.exportForCredentialStore(),
      );
      await keys.remove(first);
      expect(await keys.read(first), isNull);
      expect(await keys.read(second), isNotNull);
    } finally {
      if (first != null) await keys.remove(first);
      if (second != null) await keys.remove(second);
    }
  });

  test(
    'locked Linux keyring refuses read, store and delete until explicit unlock',
    () async {
      final reference = await keys.storeNew(
        await InstallationEncryptionKey.generate(),
      );
      var locked = false;
      try {
        final alias = await Process.run('gdbus', [
          'call',
          '--session',
          '--dest',
          'org.freedesktop.secrets',
          '--object-path',
          '/org/freedesktop/secrets',
          '--method',
          'org.freedesktop.Secret.Service.ReadAlias',
          'default',
        ]);
        expect(alias.exitCode, 0);
        final collection = RegExp(r"objectpath '([^']+)'")
            .firstMatch(alias.stdout as String)!
            .group(1)!;
        final lock = await Process.run('gdbus', [
          'call',
          '--session',
          '--dest',
          'org.freedesktop.secrets',
          '--object-path',
          '/org/freedesktop/secrets',
          '--method',
          'org.freedesktop.Secret.Service.Lock',
          "['$collection']",
        ]);
        expect(lock.exitCode, 0);
        locked = true;
        final unavailable = throwsA(
          isA<InstallationKeyException>().having(
            (e) => e.failure,
            'failure',
            InstallationKeyFailure.unavailable,
          ),
        );
        await expectLater(keys.read(reference), unavailable);
        await expectLater(keys.remove(reference), unavailable);
        await expectLater(
          keys.storeNew(await InstallationEncryptionKey.generate()),
          unavailable,
        );
      } finally {
        if (locked) {
          // This test runs only against the explicitly enabled disposable bus
          // and keyring, created with this fixture password through stdin.
          final unlock = await Process.start('gnome-keyring-daemon', [
            '--replace',
            '--unlock',
            '--components=secrets',
          ]);
          final output = unlock.stdout.drain<void>();
          final errors = unlock.stderr.drain<void>();
          unlock.stdin.writeln('disposable-fixture-keyring');
          await unlock.stdin.close();
          expect(await unlock.exitCode, 0);
          await output;
          await errors;
        }
        expect(await keys.read(reference), isNotNull);
        await keys.remove(reference);
      }
    },
    skip: !Platform.isLinux,
  );

  test('invalid account references are rejected without OS access or diagnostic disclosure', () async {
    for (final reference in [
      '',
      'foreign-service-account',
      'ub-installation-key-v1-${'0' * 31}',
      'ub-installation-key-v1-${'0' * 32}\n',
    ]) {
      for (final operation in [
        () => keys.read(reference),
        () => keys.remove(reference),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<InstallationKeyException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  InstallationKeyFailure.invalidReference,
                )
                .having(
                  (e) => '$e',
                  'redaction',
                  isNot(contains(reference.isEmpty ? 'foreign' : reference)),
                ),
          ),
        );
      }
    }
  });
}
