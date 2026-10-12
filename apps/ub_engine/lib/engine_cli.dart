import 'dart:async';
import 'dart:io';

import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/ub_service.dart'
    show ConfigurationException, ConfigurationFailure;
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_settings.dart';

const _usage = '''Usage: universe-engine --installation <path> [--initialize]

--initialize creates the local installation and its approval-owner profile,
or initializes an existing empty installation. It prints the profile ID only.
Otherwise, serve an existing installation until author shutdown or a signal.
SQLite is currently available; selecting PostgreSQL fails without fallback.
Fixture options are not part of this persistent Dart engine.''';

Future<int> runEngine(
  List<String> arguments, {
  required Map<String, String> environment,
  required void Function(String) output,
  required void Function(String) error,
  Future<void>? stop,
}) async {
  try {
    String? root;
    var initialize = false;
    for (var index = 0; index < arguments.length; index++) {
      final option = arguments[index];
      if (option == '--help' || option == '-h') {
        output(_usage);
        return 0;
      }
      if (option == '--initialize') {
        if (initialize) throw const _UsageError();
        initialize = true;
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
      final configuration = await LocalBackendConfiguration.resolve(
        environment: environment,
        settings: settings,
      );
      if (configuration.usePostgres) {
        error(
          'PostgreSQL runtime is not yet available in this Dart engine. No alternative backend was opened.',
        );
        return 1;
      }
    } finally {
      settings?.close();
    }
    if (initialize) {
      final profile = SqliteInstallationStore.withBootstrap(
        root,
        (store) => InstallationAuthority(store).initializeAuthor(),
      );
      output(profile.value);
      return 0;
    }
    final server = await LocalSqliteEngineServer.start(root);
    try {
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

final class _UsageError implements Exception {
  const _UsageError();
}
