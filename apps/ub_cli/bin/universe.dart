import 'dart:io';

import 'package:ub_cli/operator_cli.dart';

void main(List<String> arguments) {
  exitCode = runOperatorCli(
    arguments,
    output: stdout.writeln,
    error: stderr.writeln,
  );
}
