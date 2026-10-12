import 'package:ub_contracts/ub_contracts.dart';

import 'configuration.dart';

/// Maps deliberately to the driver's three TLS modes, without approximating
/// libpq's opportunistic or CA-only modes. No connection is opened here.
enum PostgresTlsMode { verifyFull, require, disable }

final class PostgresConnectionOptions {
  const PostgresConnectionOptions._({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.tlsMode,
    required this.rootCertificate,
    required this.clientCertificate,
    required this.clientKey,
    required this.applicationName,
    required this.connectTimeout,
  });
  final String host, database;
  final int port;
  final String? username;
  final Credential? password;
  final PostgresTlsMode tlsMode;
  final String? rootCertificate, clientCertificate, clientKey, applicationName;
  final Duration? connectTimeout;

  factory PostgresConnectionOptions.parse(
    Credential endpoint, {
    bool allowLoopbackDevelopment = false,
  }) {
    try {
      return _parse(endpoint.expose(), allowLoopbackDevelopment);
    } on ConfigurationException {
      rethrow;
    } on Object {
      // URI and decoding exceptions can include the original secret-bearing URI.
      throw const ConfigurationException(ConfigurationFailure.invalidEndpoint);
    }
  }

  static PostgresConnectionOptions _parse(String raw, bool allowLoopback) {
    void invalid() => throw const ConfigurationException(
      ConfigurationFailure.invalidEndpoint,
    );
    if (raw.codeUnits.any((v) => v <= 0x20 || v == 0x7f || v == 0x5c) ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(raw)) {
      invalid();
    }
    final parts = RegExp(
      r'^postgres(?:ql)?://([^/?#]*)([^?#]*)(?:\?[^#]*)?$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (parts == null) invalid();
    final authority = parts!.group(1)!;
    final rawPath = parts.group(2)!;
    if (authority.split('@').length > 2 ||
        authority.endsWith(':') ||
        (rawPath.isNotEmpty &&
            (!rawPath.startsWith('/') || rawPath.substring(1).contains('/')))) {
      invalid();
    }
    final uri = Uri.parse(raw);
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.host.contains(',') ||
        uri.host.contains('/') ||
        uri.host.contains('%')) {
      invalid();
    }
    final query = uri.queryParametersAll;
    const allowed = {
      'user',
      'username',
      'password',
      'dbname',
      'database',
      'port',
      'sslmode',
      'sslrootcert',
      'sslcert',
      'sslkey',
      'application_name',
      'connect_timeout',
    };
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ConfigurationException(
        ConfigurationFailure.unsupportedConnectionOption,
      );
    }
    if (query.values.any((values) => values.length != 1) ||
        (query.containsKey('user') && query.containsKey('username')) ||
        (query.containsKey('dbname') && query.containsKey('database'))) {
      invalid();
    }
    String? option(String key) => query[key]?.single;
    final userInfo = uri.userInfo;
    final colon = userInfo.indexOf(':');
    final username =
        option('user') ??
        option('username') ??
        (userInfo.isEmpty
            ? null
            : Uri.decodeComponent(
                colon < 0 ? userInfo : userInfo.substring(0, colon),
              ));
    final password =
        option('password') ??
        (colon < 0 ? null : Uri.decodeComponent(userInfo.substring(colon + 1)));
    final database =
        option('dbname') ??
        option('database') ??
        (uri.pathSegments.length == 1 ? uri.pathSegments.single : null);
    if (database == null ||
        database.isEmpty ||
        [
          uri.host,
          database,
          ?username,
          ?password,
          ...query.values.map((v) => v.single),
        ].any((v) => v.codeUnits.any((c) => c == 0 || c < 0x20 || c == 0x7f))) {
      invalid();
    }
    int positive(String text, int maximum) {
      if (!RegExp(r'^[0-9]+$').hasMatch(text)) invalid();
      final n = BigInt.parse(text);
      if (n < BigInt.one || n > BigInt.from(maximum)) invalid();
      return n.toInt();
    }

    final port = option('port') != null
        ? positive(option('port')!, 65535)
        : uri.hasPort
        ? uri.port
        : 5432;
    if (port < 1 || port > 65535) invalid();
    final mode = switch (option('sslmode') ?? 'verify-full') {
      'verify-full' => PostgresTlsMode.verifyFull,
      'require' => PostgresTlsMode.require,
      'disable' => PostgresTlsMode.disable,
      _ => throw const ConfigurationException(
        ConfigurationFailure.unsupportedConnectionOption,
      ),
    };
    final loopback =
        uri.host == 'localhost' ||
        uri.host == '::1' ||
        RegExp(r'^127\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}$').hasMatch(uri.host) &&
            uri.host.split('.').every((s) => int.parse(s) <= 255);
    if (mode != PostgresTlsMode.verifyFull && !(allowLoopback && loopback)) {
      throw const ConfigurationException(ConfigurationFailure.unverifiedTls);
    }
    final root = option('sslrootcert');
    final cert = option('sslcert');
    final key = option('sslkey');
    if ((cert == null) != (key == null) ||
        [root, cert, key].any((v) => v != null && v.isEmpty) ||
        (mode == PostgresTlsMode.disable && (root != null || cert != null)) ||
        (mode == PostgresTlsMode.require && root != null)) {
      throw const ConfigurationException(
        ConfigurationFailure.unsupportedConnectionOption,
      );
    }
    return PostgresConnectionOptions._(
      host: uri.host,
      port: port,
      database: database!,
      username: username,
      password: password == null ? null : Credential(password),
      tlsMode: mode,
      rootCertificate: root,
      clientCertificate: cert,
      clientKey: key,
      applicationName: option('application_name'),
      connectTimeout: option('connect_timeout') == null
          ? null
          : Duration(seconds: positive(option('connect_timeout')!, 2147483647)),
    );
  }

  @override
  String toString() => 'PostgresConnectionOptions([redacted])';
}
