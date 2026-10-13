import 'dart:io';

import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_settings.dart';

import 'configuration.dart';
import 'endpoint_encryption.dart';
import 'installation_key_store.dart';
import 'postgres_open.dart';

/// Explicit device setup. Tests the selected existing installation, refuses an
/// active local engine, and saves settings without transferring or starting data.
/// The caller supplies the chosen configuration, not ambient environment values.
Future<OperationId> saveLocalBackendConfiguration({
  required String root,
  required BackendConfiguration configuration,
}) async {
  try {
    return await _save(root: root, configuration: configuration);
  } on ConfigurationException {
    rethrow;
  } on Object {
    throw const ConfigurationException(ConfigurationFailure.backendSetupFailed);
  }
}

Future<OperationId> _save({
  required String root,
  required BackendConfiguration configuration,
}) async {
  InstallationBootstrapLock? bootstrap;
  OwnedFileLock? ownership;
  SqliteInstallationStore? sqlite;
  LocalSettingsStore? settings;
  String? newKeyReference;
  var saved = false;
  const keys = NativeInstallationKeyStore();
  try {
    late OperationId instance;
    if (configuration case final PostgresConfiguration postgres) {
      final target = await openPostgresInstallation(postgres);
      try {
        instance = target.instanceId;
      } finally {
        await target.close();
      }
    }
    final directory = privateDirectory(root);
    bootstrap = InstallationBootstrapLock.acquireExisting(directory);
    if (configuration is PostgresConfiguration) {
      ownership = OwnedFileLock.acquire('$directory/service.lock');
    } else {
      sqlite = SqliteInstallationStore.openExisting(directory);
      instance = sqlite.instanceId;
    }
    final path = '$directory/settings.sqlite';
    settings =
        FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.notFound
        ? LocalSettingsStore.create(
            path,
            installationId: OperationId.generate().value,
          )
        : LocalSettingsStore.openExisting(path);
    final previous = settings.read();
    var encrypted = previous.endpoint;
    if (configuration case final PostgresConfiguration postgres) {
      final String reference;
      final InstallationEncryptionKey key;
      if (previous.endpoint case final existing?) {
        reference = existing.keyReference;
        final retained = await keys.read(reference);
        if (retained == null) {
          throw const ConfigurationException(
            ConfigurationFailure.savedEndpointUnavailable,
          );
        }
        key = retained;
        await PostgresEndpointEncryption().decrypt(
          encrypted: existing,
          installationId: previous.installationId,
          key: key,
        );
      } else {
        key = await InstallationEncryptionKey.generate();
        reference = await keys.storeNew(key);
        newKeyReference = reference;
      }
      encrypted = await PostgresEndpointEncryption().encrypt(
        endpoint: postgres.endpoint,
        installationId: previous.installationId,
        keyReference: reference,
        key: key,
      );
    }
    settings.save(usePostgres: configuration.usePostgres, endpoint: encrypted);
    saved = true;
    return instance;
  } finally {
    try {
      settings?.close();
    } finally {
      try {
        if (!saved && newKeyReference != null) {
          await keys.remove(newKeyReference);
        }
      } finally {
        try {
          sqlite?.close();
        } finally {
          try {
            ownership?.close();
          } finally {
            bootstrap?.close();
          }
        }
      }
    }
  }
}
