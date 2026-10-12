import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';

import 'configuration.dart';
import 'postgres_endpoint.dart';

/// Uses already-resolved environment/encrypted settings. Explicit setup creates
/// only an empty installation; ordinary opening never provisions missing data.
Future<PostgresInstallationStore> openPostgresInstallation(
  PostgresConfiguration configuration, {
  bool create = false,
}) async {
  try {
    final options = configuration.connection;
    SecurityContext? security;
    if (options.rootCertificate != null || options.clientCertificate != null) {
      security = SecurityContext(
        withTrustedRoots: options.rootCertificate == null,
      );
      if (options.rootCertificate case final String path) {
        security.setTrustedCertificates(path);
      }
      if (options.clientCertificate case final String path) {
        security.useCertificateChain(path);
        security.usePrivateKey(options.clientKey!);
      }
    }
    final endpoint = Endpoint(
      host: options.host,
      port: options.port,
      database: options.database,
      username: options.username,
      password: options.password?.expose(),
    );
    final settings = ConnectionSettings(
      sslMode: switch (options.tlsMode) {
        PostgresTlsMode.verifyFull => SslMode.verifyFull,
        PostgresTlsMode.require => SslMode.require,
        PostgresTlsMode.disable => SslMode.disable,
      },
      securityContext: security,
      applicationName: options.applicationName,
      connectTimeout: options.connectTimeout,
    );
    return await (create
        ? PostgresInstallationStore.create(endpoint, settings: settings)
        : PostgresInstallationStore.openExisting(endpoint, settings: settings));
  } on InstallationException {
    rethrow;
  } on Object {
    // File, TLS and driver failures may retain paths or access-bearing details.
    throw const InstallationException(InstallationFailure.unavailable);
  }
}
