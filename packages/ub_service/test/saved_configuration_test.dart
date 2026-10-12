@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_store/local_settings.dart';
import 'package:ub_service/ub_service.dart';

void main() {
  test('encrypted saved configuration unlocks after settings restart and preserves selection on key loss', () async {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-saved-config-',
    );
    final path = '${directory.path}/settings.sqlite';
    const endpoint = Credential(
      'postgresql://disposable_user:disposable_password@localhost/db',
    );
    final cipher = PostgresEndpointEncryption();
    final key = await InstallationEncryptionKey.generate();
    var store = LocalSettingsStore.create(
      path,
      installationId: 'disposable-installation',
    );
    try {
      final encrypted = await cipher.encrypt(
        endpoint: endpoint,
        installationId: store.read().installationId,
        keyReference: 'disposable-key-ref',
        key: key,
      );
      store.save(usePostgres: true, endpoint: encrypted);
      store.close();
      store = LocalSettingsStore.openExisting(path);
      final saved = store.read();
      final configured = await BackendConfiguration.resolve(
        environment: {},
        savedUsePostgres: saved.usePostgres,
        readSavedEndpoint: () => cipher.decrypt(
          encrypted: saved.endpoint!,
          installationId: saved.installationId,
          key: key,
        ),
      ) as PostgresConfiguration;
      expect(configured.endpoint.expose(), endpoint.expose());
      await expectLater(
        BackendConfiguration.resolve(
          environment: {},
          savedUsePostgres: saved.usePostgres,
          readSavedEndpoint: () async => cipher.decrypt(
            encrypted: saved.endpoint!,
            installationId: saved.installationId,
            key: await InstallationEncryptionKey.generate(),
          ),
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.failure,
            'failure',
            ConfigurationFailure.savedEndpointUnavailable,
          ),
        ),
      );
      expect(store.read().usePostgres, isTrue);
      expect(store.read().endpoint!.ciphertext, encrypted.ciphertext);
      for (final file in directory.listSync().whereType<File>()) {
        final bytes = file.readAsBytesSync();
        final raw = String.fromCharCodes(bytes);
        expect(raw, isNot(contains('disposable_password')));
        expect(raw, isNot(contains('disposable_user')));
      }
      var unlocks = 0;
      final overridden = await BackendConfiguration.resolve(
        environment: {'UB_USE_POSTGRES': 'false'},
        savedUsePostgres: saved.usePostgres,
        readSavedEndpoint: () async {
          unlocks++;
          return endpoint;
        },
      );
      expect(overridden, isA<SqliteConfiguration>());
      expect(unlocks, 0);
      expect(store.read().usePostgres, isTrue);
    } finally {
      store.close();
      directory.deleteSync(recursive: true);
    }
  });
}
