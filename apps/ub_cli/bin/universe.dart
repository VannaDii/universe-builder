import 'dart:io';

import 'package:ub_cli/universe_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runUniverseCli(
    arguments,
    output: stdout.writeln,
    error: stderr.writeln,
  );
}
