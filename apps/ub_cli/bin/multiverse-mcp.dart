// Keep the maintained executable name produced by dart build cli.
// ignore_for_file: file_names
import 'dart:io';

import 'package:ub_cli/launcher.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLauncher(
    arguments,
    output: stdout.writeln,
    error: stderr.writeln,
  );
}
