import 'dart:async';
import 'dart:io';

import 'package:ub_client/local_engine.dart';

import 'desktop_launcher.dart';

const _usage =
    'Usage: multiverse-mcp <serve|admin|ux|shortcut> [arguments]\n'
    'serve forwards to the installed universe-mcp; admin forwards to universe.\n'
    'ux [--installation <path> --profile <id> | --fixture] opens the desktop.\n'
    'shortcut [--destination <directory>] [--launcher <absolute path>] '
    '[--installation <path> --profile <id>] creates a Finder app on macOS or a menu entry on Linux.';

/// Installed public entry point. Arguments are passed as literal process
/// arguments, never through a shell or PATH lookup. The shared resolver verifies
/// a containing sealed macOS bundle before selecting sibling helpers.
Future<int> runLauncher(
  List<String> arguments, {
  required void Function(String) output,
  required void Function(String) error,
  Future<String> Function()? engineHelper,
}) async {
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    output(_usage);
    return 0;
  }
  if (arguments.length == 1 && arguments.single == '--version') {
    output('multiverse-mcp 0.1.0');
    return 0;
  }
  if (arguments.isEmpty ||
      !{'serve', 'admin', 'ux', 'shortcut'}.contains(arguments.first)) {
    error(_usage);
    return 2;
  }
  DesktopOptions? desktop;
  if ({'ux', 'shortcut'}.contains(arguments.first)) {
    if (arguments.length == 2 && {'--help', '-h'}.contains(arguments[1])) {
      output(_usage);
      return 0;
    }
    try {
      desktop = DesktopOptions.parse(
        arguments.sublist(1),
        shortcut: arguments.first == 'shortcut',
      );
    } on FormatException {
      error(_usage);
      return 2;
    }
  }
  final signals = <StreamSubscription<ProcessSignal>>[];
  Process? child;
  try {
    final engine = await (engineHelper ?? LocalEngineClient.siblingEngine)();
    if (!File(engine).isAbsolute) {
      throw const FormatException('Absolute installed helper required');
    }
    if (arguments.first == 'shortcut') {
      output(
        'Created ${await (Platform.isLinux ? createLinuxShortcut : createFinderShortcut)(engine: engine, options: desktop!)}',
      );
      return 0;
    }
    final ({String executable, List<String> arguments}) command;
    if (arguments.first == 'ux') {
      command = desktopCommand(engine, desktop!.arguments);
    } else {
      final name = arguments.first == 'serve' ? 'universe-mcp' : 'universe';
      command = (
        executable:
            '${File(engine).parent.path}/$name${Platform.isWindows ? '.exe' : ''}',
        arguments: arguments.sublist(1),
      );
    }
    if (FileSystemEntity.typeSync(command.executable, followLinks: true) !=
        FileSystemEntityType.file) {
      throw const FormatException('Installed helper unavailable');
    }
    child = await Process.start(
      command.executable,
      command.arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    if (!Platform.isWindows) {
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
        signals.add(
          signal.watch().listen((received) {
            child?.kill(received);
          }),
        );
      }
    }
    return await child.exitCode;
  } on Object {
    error('Installed launcher helper unavailable or interrupted.');
    child?.kill();
    if (child != null) await child.exitCode;
    return 1;
  } finally {
    for (final subscription in signals) {
      await subscription.cancel();
    }
  }
}
