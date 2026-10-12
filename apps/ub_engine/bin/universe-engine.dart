// Keep the maintained executable name produced by dart build cli.
// ignore_for_file: file_names
import 'dart:async';
import 'dart:io';

import 'package:ub_engine/engine_cli.dart';

Future<void> main(List<String> arguments) async {
  final stop = Completer<void>();
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    if (!Platform.isWindows) {
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
        signals.add(
          signal.watch().listen((_) {
            if (!stop.isCompleted) stop.complete();
          }),
        );
      }
    }
    exitCode = await runEngine(
      arguments,
      environment: Platform.environment,
      output: stdout.writeln,
      error: stderr.writeln,
      stop: stop.future,
    );
  } finally {
    for (final signal in signals) {
      await signal.cancel();
    }
  }
}
