@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_store/local_settings.dart';

void main() {
  late Directory directory;
  late LocalSettingsStore settings;
  late InstallationEncryptionKey key;
  const endpoint = Credential(
    'postgresql://disposable_user:disposable_password@localhost/db',
  );
  final cipher = PostgresEndpointEncryption();
  setUp(() async {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-local-startup-',
    );
    settings = LocalSettingsStore.create(
      '${directory.path}/settings.sqlite',
      installationId: 'disposable-startup-installation',
    );
    key = await InstallationEncryptionKey.generate();
    settings.save(
      usePostgres: true,
      endpoint: await cipher.encrypt(
        endpoint: endpoint,
        installationId: settings.read().installationId,
        keyReference: 'disposable-key-ref',
        key: key,
      ),
    );
  });
  tearDown(() {
    settings.close();
    directory.deleteSync(recursive: true);
  });

  Matcher failure(ConfigurationFailure expected) => throwsA(
    isA<ConfigurationException>().having((e) => e.failure, 'failure', expected),
  );

  test(
    'Finder-style startup uses saved selection and exact OS key reference',
    () async {
      var reads = 0;
      final resolved = await LocalBackendConfiguration.resolve(
        environment: {},
        settings: settings,
        readKey: (reference) async {
          reads++;
          expect(reference, 'disposable-key-ref');
          return key;
        },
      ) as PostgresConfiguration;
      expect(resolved.endpoint.expose(), endpoint.expose());
      expect(reads, 1);
    },
  );

  test('saved SQLite never unlocks retained PostgreSQL credentials', () async {
    settings.save(usePostgres: false, endpoint: settings.read().endpoint);
    var reads = 0;
    final resolved = await LocalBackendConfiguration.resolve(
      environment: {},
      settings: settings,
      readKey: (_) async {
        reads++;
        throw StateError('Disposable key store unavailable');
      },
    );
    expect(resolved, isA<SqliteConfiguration>());
    expect(reads, 0);
    expect(settings.read().endpoint, isNotNull);
  });

  test(
    'explicit environment selections avoid saved settings access entirely',
    () async {
      settings.close();
      var reads = 0;
      Future<InstallationEncryptionKey?> readKey(String _) async {
        reads++;
        throw StateError('Unexpected key lookup');
      }

      expect(
        await LocalBackendConfiguration.resolve(
          environment: {'UB_USE_POSTGRES': 'false'},
          settings: settings,
          readKey: readKey,
        ),
        isA<SqliteConfiguration>(),
      );
      final resolved = await LocalBackendConfiguration.resolve(
        environment: {
          'UB_USE_POSTGRES': 'true',
          'UB_POSTGRES_ENDPOINT': endpoint.expose(),
        },
        settings: settings,
        readKey: readKey,
      ) as PostgresConfiguration;
      expect(resolved.endpoint.expose(), endpoint.expose());
      await expectLater(
        LocalBackendConfiguration.resolve(
          environment: {'UB_USE_POSTGRES': 'invalid'},
          settings: settings,
          readKey: readKey,
        ),
        failure(ConfigurationFailure.invalidBackendFlag),
      );
      await expectLater(
        LocalBackendConfiguration.resolve(
          environment: {'UB_USE_POSTGRES': 'true', 'UB_POSTGRES_ENDPOINT': ''},
          settings: settings,
          readKey: readKey,
        ),
        failure(ConfigurationFailure.missingPostgresEndpoint),
      );
      expect(reads, 0);
    },
  );

  test(
    'missing, unavailable and wrong saved keys fail without changing settings',
    () async {
      final before = settings.read();
      final wrong = await InstallationEncryptionKey.generate();
      for (final readKey
          in <Future<InstallationEncryptionKey?> Function(String)>[
            (_) async => null,
            (_) async => throw StateError('disposable_password key error'),
            (_) async => wrong,
          ]) {
        await expectLater(
          LocalBackendConfiguration.resolve(
            environment: {},
            settings: settings,
            readKey: readKey,
          ),
          failure(ConfigurationFailure.savedEndpointUnavailable),
        );
        expect(
          settings.read().endpoint!.ciphertext,
          before.endpoint!.ciphertext,
        );
        expect(settings.read().usePostgres, isTrue);
      }
    },
  );

  test(
    'saved metadata errors are redacted and do not infer a backend',
    () async {
      settings.close();
      await expectLater(
        LocalBackendConfiguration.resolve(environment: {}, settings: settings),
        failure(ConfigurationFailure.savedSettingsUnavailable),
      );
    },
  );

  test(
    'absent settings default to SQLite and selected missing credentials fail',
    () async {
      expect(
        await LocalBackendConfiguration.resolve(environment: {}),
        isA<SqliteConfiguration>(),
      );
      await expectLater(
        LocalBackendConfiguration.resolve(
          environment: {'UB_USE_POSTGRES': 'true'},
        ),
        failure(ConfigurationFailure.missingPostgresEndpoint),
      );
      settings.save(usePostgres: false, endpoint: null);
      await expectLater(
        LocalBackendConfiguration.resolve(
          environment: {'UB_USE_POSTGRES': 'true'},
          settings: settings,
        ),
        failure(ConfigurationFailure.missingPostgresEndpoint),
      );
    },
  );

  test(
    'explicit loopback TLS policy is passed through the shared resolver',
    () async {
      final environment = {
        'UB_USE_POSTGRES': 'true',
        'UB_POSTGRES_ENDPOINT': '${endpoint.expose()}?sslmode=disable',
      };
      await expectLater(
        LocalBackendConfiguration.resolve(environment: environment),
        failure(ConfigurationFailure.unverifiedTls),
      );
      final resolved = await LocalBackendConfiguration.resolve(
        environment: environment,
        allowLoopbackDevelopment: true,
      ) as PostgresConfiguration;
      expect(resolved.connection.tlsMode, PostgresTlsMode.disable);
    },
  );

  test('environment endpoint override never unlocks or persists a different secret', () async {
    final before = settings.read();
    const override =
        'postgresql://another_disposable_user:another_disposable_password@localhost/other';
    final resolved = await LocalBackendConfiguration.resolve(
      environment: {'UB_POSTGRES_ENDPOINT': override},
      settings: settings,
      readKey: (_) async => throw StateError('Unexpected key lookup'),
    ) as PostgresConfiguration;
    expect(resolved.endpoint.expose(), override);
    expect(settings.read().endpoint!.ciphertext, before.endpoint!.ciphertext);
    expect(settings.read().installationId, before.installationId);
  });
}
