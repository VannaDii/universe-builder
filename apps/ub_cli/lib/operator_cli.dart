import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';

const _commands = {
  'convert-package',
  'convert-installation',
  'convert-credential',
};
const _usage = '''Usage: universe --installation <path> [--profile <id>] <command> <source> <destination>

Offline operator commands:
  convert-package        Convert a retained serialized/relational universe package.
  convert-installation   Convert retained installation authority and credentials.
  convert-credential     Convert one retained version-1 JSON credential.

Each command requires a fresh destination and a clean offline source.
The installation/profile options preserve the existing command interface;
offline conversion does not authenticate, start an engine or register packages.
Author commands are available through the shared universe executable entry point.''';

/// Offline operator commands use the same verified store APIs as maintained
/// conversions. No engine or backend configuration is opened as a side effect.
int runOperatorCli(
  List<String> arguments, {
  required void Function(String) output,
  required void Function(String) error,
}) {
  try {
    String? installation, profile;
    var index = 0;
    while (index < arguments.length && arguments[index].startsWith('-')) {
      final option = arguments[index++];
      if (option == '--help' || option == '-h') {
        output(_usage);
        return 0;
      }
      final equals = option.indexOf('=');
      final name = equals < 0 ? option : option.substring(0, equals);
      if (name != '--installation' && name != '--profile') {
        throw const _UsageError();
      }
      final String value;
      if (equals >= 0) {
        value = option.substring(equals + 1);
      } else {
        if (index == arguments.length || arguments[index].startsWith('-')) {
          throw const _UsageError();
        }
        value = arguments[index++];
      }
      if (value.isEmpty || value.contains('\u0000')) throw const _UsageError();
      if (name == '--installation') {
        if (installation != null) throw const _UsageError();
        installation = value;
      } else {
        if (profile != null) throw const _UsageError();
        profile = value;
      }
    }
    if (index == arguments.length) throw const _UsageError();
    final command = arguments[index++];
    if (!_commands.contains(command)) throw const _UsageError();
    if (index < arguments.length &&
        (arguments[index] == '--help' || arguments[index] == '-h')) {
      if (index + 1 != arguments.length) throw const _UsageError();
      output(_usage);
      return 0;
    }
    if (installation == null) throw const _UsageError();
    final literalPaths = index < arguments.length && arguments[index] == '--';
    if (literalPaths) index++;
    if (arguments.length - index != 2 ||
        arguments
            .skip(index)
            .any(
              (value) =>
                  value.isEmpty ||
                  value.contains('\u0000') ||
                  !literalPaths && value.startsWith('-'),
            )) {
      throw const _UsageError();
    }
    final source = arguments[index], destination = arguments[index + 1];
    final report = switch (command) {
      'convert-package' => convertPackage(source, destination),
      'convert-installation' => convertInstallation(source, destination),
      'convert-credential' => convertCredential(source, destination),
      _ => throw const _UsageError(),
    };
    output(report.toText());
    return 0;
  } on _UsageError {
    error(_usage);
    return 2;
  } on InstallationConversionException catch (failure) {
    error(
      'Installation conversion failed: ${failure.failure.name}. Retain the original and any existing destination.',
    );
    return 1;
  } on CredentialConversionException catch (failure) {
    error(
      'Credential conversion failed: ${failure.failure.name}. Retain the original and any existing destination.',
    );
    return 1;
  } on Object {
    // Parser and driver errors can embed authored content or credentials.
    error(
      'Conversion failed. Retain the original and any existing destination.',
    );
    return 1;
  }
}

final class _UsageError implements Exception {
  const _UsageError();
}
