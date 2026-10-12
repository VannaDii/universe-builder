import 'dart:async';
import 'dart:io';

import 'package:ub_client/local_engine.dart';

const _usage =
    'Usage: multiverse-mcp <serve|admin> [arguments]\n'
    'serve forwards to the installed universe-mcp; admin forwards to universe.\n'
    'Dart desktop ux and shortcut commands are not available yet.';

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
  if (arguments.isEmpty || !{'serve', 'admin'}.contains(arguments.first)) {
    error(_usage);
    return 2;
  }
  final signals = <StreamSubscription<ProcessSignal>>[];
  Process? child;
  try {
    final engine = await (engineHelper ?? LocalEngineClient.siblingEngine)();
    if (!File(engine).isAbsolute) {
      throw const FormatException('Absolute installed helper required');
    }
    final name = arguments.first == 'serve' ? 'universe-mcp' : 'universe';
    final helper = '${File(engine).parent.path}/$name';
    if (FileSystemEntity.typeSync(helper, followLinks: true) !=
        FileSystemEntityType.file) {
      throw const FormatException('Installed helper unavailable');
    }
    child = await Process.start(
      helper,
      arguments.sublist(1),
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
