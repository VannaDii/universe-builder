import 'dart:async';
import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart' show Credential;

import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/ub_service.dart'
    show
        BackendConfiguration,
        PostgresConfiguration,
        ConfigurationException,
        ConfigurationFailure;
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/local_settings.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_domain/ub_domain.dart';

const _usage = '''Usage: universe-engine --installation <path> [--initialize | --device-profile]

--initialize creates the local installation and its approval-owner profile,
or initializes an existing empty installation. It prints the profile ID only.
Otherwise, serve an existing installation until author shutdown or a signal.
--http-only omits the transitional Unix socket for HTTP clients.
--web-assets <path> serves a local Flutter web build from the engine origin.
--https-origin <https://host:port> --https-bind <IP address>
--tls-certificate <absolute chain path> --tls-private-key <absolute key path>
explicitly add a TLS listener to the same instance. Supply all four options;
initialization/device setup cannot expose a listener. Port 0 selects a free port.
The local administration endpoint stays available. HTTPS mode stays running
until author shutdown or a signal. Certificate/key errors never fall back to HTTP.
Installed bundles use their adjacent web assets when present.
--device-profile explicitly sets up the local device workspace if needed and
prints its retained owner profile ID. It never prints credentials.
UB_USE_POSTGRES selects SQLite (false/default) or PostgreSQL (true).
UB_POSTGRES_ENDPOINT supplies the PostgreSQL connection URI; saved encrypted
settings are used when the corresponding environment value is absent.
--allow-loopback-postgres-development explicitly allows unverified TLS for a
loopback development database. Other hosts still require verified TLS.
PostgreSQL serves HTTP; the transitional Unix socket is SQLite-only.
Fixture options are not part of this persistent Dart engine.''';

Future<int> runEngine(
  List<String> arguments, {
  required Map<String, String> environment,
  required void Function(String) output,
  required void Function(String) error,
  Future<void>? stop,
}) async {
  try {
    String? root, webAssets;
    final httpsOptions = <String, String>{};
    var initialize = false;
    var deviceProfile = false;
    var httpOnly = false;
    var allowLoopbackDevelopment = false;
    for (var index = 0; index < arguments.length; index++) {
      final option = arguments[index];
      if (option == '--help' || option == '-h') {
        output(_usage);
        return 0;
      }
      if (option == '--allow-loopback-postgres-development') {
        if (allowLoopbackDevelopment) throw const _UsageError();
        allowLoopbackDevelopment = true;
      } else if (option == '--http-only') {
        if (httpOnly) throw const _UsageError();
        httpOnly = true;
      } else if (option == '--initialize' || option == '--device-profile') {
        if (initialize || deviceProfile) throw const _UsageError();
        initialize = option == '--initialize';
        deviceProfile = option == '--device-profile';
      } else if ({
        '--https-origin',
        '--https-bind',
        '--tls-certificate',
        '--tls-private-key',
      }.contains(option.split('=').first)) {
        final equal = option.indexOf('=');
        final key = equal < 0 ? option : option.substring(0, equal);
        if (httpsOptions.containsKey(key)) throw const _UsageError();
        final String value;
        if (equal < 0) {
          if (++index == arguments.length || arguments[index].startsWith('-')) {
            throw const _UsageError();
          }
          value = arguments[index];
        } else {
          value = option.substring(equal + 1);
        }
        if (value.isEmpty || value.contains('\u0000')) {
          throw const _UsageError();
        }
        httpsOptions[key] = value;
      } else if (option == '--web-assets' ||
          option.startsWith('--web-assets=')) {
        if (webAssets != null) throw const _UsageError();
        if (option == '--web-assets') {
          if (++index == arguments.length || arguments[index].startsWith('-')) {
            throw const _UsageError();
          }
          webAssets = arguments[index];
        } else {
          webAssets = option.substring('--web-assets='.length);
        }
        if (webAssets.isEmpty ||
            webAssets.contains('\u0000') ||
            !Directory(webAssets).isAbsolute) {
          throw const _UsageError();
        }
      } else if (option == '--installation' ||
          option.startsWith('--installation=')) {
        if (root != null) throw const _UsageError();
        if (option == '--installation') {
          if (++index == arguments.length || arguments[index].startsWith('-')) {
            throw const _UsageError();
          }
          root = arguments[index];
        } else {
          root = option.substring('--installation='.length);
        }
        if (root.isEmpty || root.contains('\u0000')) throw const _UsageError();
      } else {
        throw const _UsageError();
      }
    }
    if (root == null) throw const _UsageError();
    Uri? httpsOrigin;
    InternetAddress? bindAddress;
    SecurityContext? tlsContext;
    if (httpsOptions.isNotEmpty) {
      if (httpsOptions.length != 4 || initialize || deviceProfile) {
        throw const _UsageError();
      }
      httpsOrigin = Uri.tryParse(httpsOptions['--https-origin']!);
      bindAddress = InternetAddress.tryParse(httpsOptions['--https-bind']!);
      if (httpsOrigin == null ||
          bindAddress == null ||
          httpsOrigin.scheme != 'https' ||
          httpsOrigin.host.isEmpty ||
          httpsOrigin.userInfo.isNotEmpty ||
          httpsOrigin.hasQuery ||
          httpsOrigin.hasFragment ||
          !{'', '/'}.contains(httpsOrigin.path) ||
          httpsOrigin.port < 0 ||
          httpsOrigin.port > 65535 ||
          !File(httpsOptions['--tls-certificate']!).isAbsolute ||
          !File(httpsOptions['--tls-private-key']!).isAbsolute) {
        throw const _UsageError();
      }
      tlsContext = SecurityContext()
        ..useCertificateChain(httpsOptions['--tls-certificate']!)
        ..usePrivateKey(httpsOptions['--tls-private-key']!);
    }
    if (webAssets == null) {
      final executable = File(Platform.resolvedExecutable);
      final adjacent = Platform.isMacOS
          ? Directory('${executable.parent.parent.path}/Resources/web')
          : Directory('${executable.parent.path}/web');
      if (adjacent.existsSync()) webAssets = adjacent.path;
    }
    late BackendConfiguration configuration;
    LocalSettingsStore? settings;
    try {
      final selection = environment['UB_USE_POSTGRES'];
      // Explicit backend selection wins without touching unrelated saved state.
      // A saved endpoint is read only if the environment did not supply one.
      if (selection == null ||
          selection.trim().toLowerCase() == 'true' &&
              !environment.containsKey('UB_POSTGRES_ENDPOINT')) {
        final path = '$root/settings.sqlite';
        if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          try {
            settings = LocalSettingsStore.openExisting(path);
          } on Object {
            throw const ConfigurationException(
              ConfigurationFailure.savedSettingsUnavailable,
            );
          }
        }
      }
      configuration = await LocalBackendConfiguration.resolve(
        environment: environment,
        settings: settings,
        allowLoopbackDevelopment: allowLoopbackDevelopment,
      );
    } finally {
      settings?.close();
    }
    if (configuration case final PostgresConfiguration postgres) {
      if (initialize || deviceProfile) {
        final profile = await _setupPostgres(
          root,
          postgres,
          deviceProfile: deviceProfile,
        );
        output(profile.value);
        return 0;
      }
      final server = await LocalPostgresEngineServer.start(
        root,
        postgres,
        webAssets: webAssets,
        httpsOrigin: httpsOrigin,
        tlsContext: tlsContext,
        bindAddress: bindAddress,
      );
      try {
        if (server.httpsEndpoint != null) {
          output(
            CanonicalObject([
              MapEntry(
                'https_endpoint',
                CanonicalString(server.httpsEndpoint.toString()),
              ),
            ]).toText(),
          );
        }
        if (stop == null) {
          await server.done;
        } else {
          await Future.any([server.done, stop]);
        }
      } finally {
        await server.close();
      }
      return 0;
    }
    if (deviceProfile) {
      final profile =
          DeviceProfileStore.read(root) ??
          SqliteInstallationStore.withBootstrap<ProfileId>(root, (store) {
            final retained = DeviceProfileStore.read(store.root);
            if (retained != null) return retained;
            final id = store.hasProfiles
                ? store.currentAuthor()
                : InstallationAuthority(store).initializeAuthor();
            ProfileCredentialStore.read(root: store.root, profile: id);
            DeviceProfileStore.write(store.root, id);
            return id;
          });
      ProfileCredentialStore.read(root: root, profile: profile);
      output(profile.value);
      return 0;
    }
    if (initialize) {
      final profile = SqliteInstallationStore.withBootstrap(
        root,
        (store) => InstallationAuthority(store).initializeAuthor(),
      );
      output(profile.value);
      return 0;
    }
    final server = await LocalSqliteEngineServer.start(
      root,
      compatibilitySocket: !httpOnly,
      webAssets: webAssets,
      httpsOrigin: httpsOrigin,
      tlsContext: tlsContext,
      bindAddress: bindAddress,
    );
    try {
      if (server.httpsEndpoint != null) {
        output(
          CanonicalObject([
            MapEntry(
              'https_endpoint',
              CanonicalString(server.httpsEndpoint.toString()),
            ),
          ]).toText(),
        );
      }
      if (stop == null) {
        await server.done;
      } else {
        await Future.any([server.done, stop]);
      }
    } finally {
      await server.close();
    }
    return 0;
  } on _UsageError {
    error(_usage);
    return 2;
  } on ConfigurationException catch (failure) {
    error(failure.message);
    return 1;
  } on Object {
    error(
      'Engine operation failed; verify installation ownership, schema, current profiles and selected backend. Retained installation data was not replaced.',
    );
    return 1;
  }
}

Future<ProfileId> _setupPostgres(
  String root,
  PostgresConfiguration configuration, {
  required bool deviceProfile,
}) async {
  PostgresInstallationStore? store;
  InstallationBootstrapLock? bootstrap;
  OwnedFileLock? ownership;
  try {
    var create = false;
    try {
      store = await openPostgresInstallation(configuration);
    } on InstallationException catch (failure) {
      if (failure.failure != InstallationFailure.identityNotInitialized) {
        rethrow;
      }
      create = true;
    }
    if (deviceProfile && store != null) {
      final retained = DeviceProfileStore.read(root);
      if (retained != null) {
        final credential = ProfileCredentialStore.read(
          root: root,
          profile: retained,
        );
        await store.transaction((session) async {
          final authority = PostgresServiceAuthority(session.authority);
          final principal = await authority.authenticate(
            profile: retained,
            credential: Credential(credential),
          );
          await authority.requireAuthor(principal);
        });
        return retained;
      }
    }
    final directory = privateDirectory(root);
    bootstrap = InstallationBootstrapLock.acquireExisting(directory);
    ownership = OwnedFileLock.acquire('$directory/service.lock');
    if (create) {
      store = await openPostgresInstallation(configuration, create: true);
    }
    final profile = await store!.transaction((session) async {
      if (deviceProfile && await session.authority.hasProfiles) {
        return session.authority.currentAuthor();
      }
      return PostgresServiceAuthority(session.authority)
          .initializeAuthor(profileRoot: directory);
    });
    ProfileCredentialStore.read(root: directory, profile: profile);
    if (deviceProfile) DeviceProfileStore.write(directory, profile);
    return profile;
  } finally {
    try {
      await store?.close();
    } finally {
      try {
        ownership?.close();
      } finally {
        bootstrap?.close();
      }
    }
  }
}

final class _UsageError implements Exception {
  const _UsageError();
}
