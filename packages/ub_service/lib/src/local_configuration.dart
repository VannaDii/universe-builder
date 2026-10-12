import 'package:ub_store/local_settings.dart';

import 'configuration.dart';
import 'endpoint_encryption.dart';
import 'installation_key_store.dart';

/// Resolves startup configuration without creating settings, storing environment
/// credentials, regenerating missing keys or starting/transferring a database.
final class LocalBackendConfiguration {
  static Future<BackendConfiguration> resolve({
    required Map<String, String> environment,
    LocalSettingsStore? settings,
    Future<InstallationEncryptionKey?> Function(String reference)? readKey,
    bool allowLoopbackDevelopment = false,
  }) async {
    bool? savedUsePostgres;
    // An explicit selection, including invalid input, is handled by the one
    // shared resolver before attempting any saved settings access.
    if (!environment.containsKey('UB_USE_POSTGRES') && settings != null) {
      try {
        savedUsePostgres = settings.readBackendSelection();
      } on Object {
        throw const ConfigurationException(
          ConfigurationFailure.savedSettingsUnavailable,
        );
      }
    }
    return BackendConfiguration.resolve(
      environment: environment,
      savedUsePostgres: savedUsePostgres,
      allowLoopbackDevelopment: allowLoopbackDevelopment,
      readSavedEndpoint: settings == null
          ? null
          : () async {
              final saved = settings.read();
              final encrypted = saved.endpoint;
              if (encrypted == null) return null;
              final key =
                  await (readKey ?? const NativeInstallationKeyStore().read)(
                    encrypted.keyReference,
                  );
              if (key == null) {
                throw const ConfigurationException(
                  ConfigurationFailure.savedEndpointUnavailable,
                );
              }
              return PostgresEndpointEncryption().decrypt(
                encrypted: encrypted,
                installationId: saved.installationId,
                key: key,
              );
            },
    );
  }
}
