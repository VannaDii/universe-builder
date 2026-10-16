import 'package:ub_contracts/ub_contracts.dart';

import 'postgres_endpoint.dart';

/// Safe errors contain neither endpoint text nor underlying key-store errors.
enum ConfigurationFailure {
  invalidBackendFlag,
  backendSetupFailed,
  missingPostgresEndpoint,
  savedEndpointUnavailable,
  savedEndpointEncryptionFailed,
  savedSettingsUnavailable,
  invalidEndpoint,
  unsupportedConnectionOption,
  unverifiedTls,
}

final class ConfigurationException implements Exception {
  const ConfigurationException(this.failure);
  final ConfigurationFailure failure;
  String get message => switch (failure) {
    ConfigurationFailure.backendSetupFailed => 'Configuration setup failed. Stop the local engine and verify the selected installation, saved settings and credential-store access before retrying.',
    ConfigurationFailure.invalidBackendFlag =>
      'UB_USE_POSTGRES must be true or false.',
    ConfigurationFailure.missingPostgresEndpoint =>
      'PostgreSQL is selected but no endpoint is configured.',
    ConfigurationFailure.savedEndpointUnavailable =>
      'The saved PostgreSQL endpoint could not be unlocked.',
    ConfigurationFailure.savedEndpointEncryptionFailed =>
      'The PostgreSQL endpoint could not be encrypted for saving.',
    ConfigurationFailure.savedSettingsUnavailable =>
      'The saved local settings could not be read.',
    ConfigurationFailure.invalidEndpoint =>
      'Enter a valid PostgreSQL URI with an explicit host and database.',
    ConfigurationFailure.unsupportedConnectionOption => 'The PostgreSQL URI contains an unsupported or incompatible connection option.',
    ConfigurationFailure.unverifiedTls => 'Use verified TLS; unverified TLS requires explicit loopback development configuration.',
  };
  @override
  String toString() => 'ConfigurationException(${failure.name}): $message';
}

/// Resolved startup settings, before backend startup.
/// This resolver never creates a store, transfers data or saves credentials.
sealed class BackendConfiguration {
  const BackendConfiguration();
  bool get usePostgres;

  static Future<BackendConfiguration> resolve({
    required Map<String, String> environment,
    bool? savedUsePostgres,
    Future<Credential?> Function()? readSavedEndpoint,
    bool allowLoopbackDevelopment = false,
  }) async {
    final bool postgres;
    if (environment.containsKey('UB_USE_POSTGRES')) {
      postgres = switch (environment['UB_USE_POSTGRES']!.trim().toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => throw const ConfigurationException(
          ConfigurationFailure.invalidBackendFlag,
        ),
      };
    } else {
      postgres = savedUsePostgres ?? false;
    }
    if (!postgres) return const SqliteConfiguration();

    final Credential? endpoint;
    if (environment.containsKey('UB_POSTGRES_ENDPOINT')) {
      // An explicitly supplied empty value cannot fall back to a saved secret.
      endpoint = Credential(environment['UB_POSTGRES_ENDPOINT']!);
    } else if (readSavedEndpoint != null) {
      try {
        endpoint = await readSavedEndpoint();
      } on Object {
        throw const ConfigurationException(
          ConfigurationFailure.savedEndpointUnavailable,
        );
      }
    } else {
      endpoint = null;
    }
    if (endpoint == null || endpoint.expose().trim().isEmpty) {
      throw const ConfigurationException(
        ConfigurationFailure.missingPostgresEndpoint,
      );
    }
    return PostgresConfiguration(
      endpoint,
      allowLoopbackDevelopment: allowLoopbackDevelopment,
    );
  }
}

final class SqliteConfiguration extends BackendConfiguration {
  const SqliteConfiguration();
  @override
  bool get usePostgres => false;
  @override
  String toString() => 'SqliteConfiguration';
}

final class PostgresConfiguration extends BackendConfiguration {
  factory PostgresConfiguration(
    Credential endpoint, {
    bool allowLoopbackDevelopment = false,
  }) => PostgresConfiguration._(
    endpoint,
    PostgresConnectionOptions.parse(
      endpoint,
      allowLoopbackDevelopment: allowLoopbackDevelopment,
    ),
  );
  const PostgresConfiguration._(this.endpoint, this.connection);
  final Credential endpoint;
  final PostgresConnectionOptions connection;
  @override
  bool get usePostgres => true;
  @override
  String toString() => 'PostgresConfiguration(endpoint: [redacted])';
}
