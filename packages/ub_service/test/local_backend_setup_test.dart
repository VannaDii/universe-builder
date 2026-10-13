@TestOn('vm && mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/native_credentials.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_settings.dart';
import 'package:ub_store/postgres_installation.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  test('explicit setup encrypts PostgreSQL settings and preserves them on failed setup or key loss', () async {
    final root = Directory('/tmp').createTempSync('ub-backend-setup-');
    final sqlite = SqliteInstallationStore.create(root.path);
    final sqliteInstance = sqlite.instanceId;
    sqlite.close();
    final database =
        'ub_setup_${OperationId.generate().value.replaceAll('-', '')}';
    final observer = await Connection.open(
      Endpoint(
        host: '127.0.0.1',
        port: port!,
        database: 'ub_disposable',
        username: 'postgres',
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    const keys = NativeInstallationKeyStore();
    String? reference;
    var created = false;
    SavedLocalSettings read() {
      final settings = LocalSettingsStore.openExisting(
        '${root.path}/settings.sqlite',
      );
      try {
        return settings.read();
      } finally {
        settings.close();
      }
    }

    try {
      await observer.execute('CREATE DATABASE $database');
      created = true;
      final store = await PostgresInstallationStore.create(
        Endpoint(
          host: '127.0.0.1',
          port: port,
          database: database,
          username: 'postgres',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final instance = store.instanceId;
      await store.close();
      final endpoint =
          'postgresql://postgres:disposable_saved_credential@127.0.0.1:$port/$database?sslmode=disable';
      final configuration = PostgresConfiguration(
        Credential(endpoint),
        allowLoopbackDevelopment: true,
      );
      expect(
        await saveLocalBackendConfiguration(
          root: root.path,
          configuration: configuration,
        ),
        instance,
      );
      var saved = read();
      reference = saved.endpoint!.keyReference;
      expect(saved.usePostgres, isTrue);
      await expectLater(
        saveLocalBackendConfiguration(
          root: root.path,
          configuration: configuration,
          expectedInstance: OperationId.generate(),
        ),
        throwsA(isA<ConfigurationException>()),
      );
      expect(read().endpoint!.ciphertext, saved.endpoint!.ciphertext);
      expect(
        await saveLocalBackendConfiguration(
          root: root.path,
          configuration: configuration,
        ),
        instance,
      );
      final updated = read();
      expect(updated.installationId, saved.installationId);
      expect(updated.endpoint!.keyReference, reference);
      expect(updated.endpoint!.nonce, isNot(saved.endpoint!.nonce));
      saved = updated;
      expect(
        utf8.decode(
          File('${root.path}/settings.sqlite').readAsBytesSync(),
          allowMalformed: true,
        ),
        isNot(contains('disposable_saved_credential')),
      );
      final reopened = LocalSettingsStore.openExisting(
        '${root.path}/settings.sqlite',
      );
      try {
        final resolved = await LocalBackendConfiguration.resolve(
          environment: {},
          settings: reopened,
          allowLoopbackDevelopment: true,
        );
        expect((resolved as PostgresConfiguration).endpoint.expose(), endpoint);
      } finally {
        reopened.close();
      }
      final active = OwnedFileLock.acquire('${root.path}/service.lock');
      try {
        await expectLater(
          saveLocalBackendConfiguration(
            root: root.path,
            configuration: configuration,
          ),
          throwsA(
            isA<ConfigurationException>().having(
              (e) => e.failure,
              'failure',
              ConfigurationFailure.backendSetupFailed,
            ),
          ),
        );
      } finally {
        active.close();
      }
      expect(read().endpoint!.ciphertext, saved.endpoint!.ciphertext);
      await expectLater(
        saveLocalBackendConfiguration(
          root: root.path,
          configuration: PostgresConfiguration(
            Credential(
              'postgresql://postgres@127.0.0.1:$port/${database}_absent?sslmode=disable',
            ),
            allowLoopbackDevelopment: true,
          ),
        ),
        throwsA(isA<ConfigurationException>()),
      );
      expect(read().endpoint!.ciphertext, saved.endpoint!.ciphertext);
      await keys.remove(reference);
      await expectLater(
        saveLocalBackendConfiguration(
          root: root.path,
          configuration: configuration,
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.failure,
            'failure',
            ConfigurationFailure.savedEndpointUnavailable,
          ),
        ),
      );
      expect(read().endpoint!.ciphertext, saved.endpoint!.ciphertext);
      expect(
        await saveLocalBackendConfiguration(
          root: root.path,
          configuration: const SqliteConfiguration(),
        ),
        sqliteInstance,
      );
      expect(read().usePostgres, isFalse);
      expect(read().endpoint!.ciphertext, saved.endpoint!.ciphertext);
      expect(read().installationId, saved.installationId);
    } finally {
      try {
        if (reference != null) await keys.remove(reference);
      } finally {
        try {
          if (created) await observer.execute('DROP DATABASE $database');
        } finally {
          await observer.close();
          root.deleteSync(recursive: true);
        }
      }
    }
  }, skip: port == null ? 'Requires disposable UB_TEST_POSTGRES_PORT' : false);
}
