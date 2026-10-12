import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/native_credentials.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_store/local_settings.dart';

Future<void> main(List<String> args) async {
  const keys = NativeInstallationKeyStore();
  final cipher = PostgresEndpointEncryption();
  const endpoint = Credential(
    'postgresql://disposable_user:disposable_password@localhost/db',
  );
  final create = args[0] == 'create';
  final store = create
      ? LocalSettingsStore.create(
          args[1],
          installationId: 'disposable-process-installation',
        )
      : LocalSettingsStore.openExisting(args[1]);
  try {
    if (create) {
      final key = await InstallationEncryptionKey.generate();
      final reference = await keys.storeNew(key);
      try {
        store.save(
          usePostgres: true,
          endpoint: await cipher.encrypt(
            endpoint: endpoint,
            installationId: store.read().installationId,
            keyReference: reference,
            key: key,
          ),
        );
      } catch (_) {
        await keys.remove(reference);
        rethrow;
      }
      stdout.writeln('created');
    } else {
      final saved = store.read();
      if (args[0] == 'remove') {
        await keys.remove(saved.endpoint!.keyReference);
        stdout.writeln('removed');
      } else {
        final restored = await LocalBackendConfiguration.resolve(
          environment: {},
          settings: store,
        ) as PostgresConfiguration;
        if (restored.endpoint.expose() != endpoint.expose()) {
          throw StateError('Disposable endpoint mismatch');
        }
        stdout.writeln('read');
      }
    }
  } finally {
    store.close();
  }
}
