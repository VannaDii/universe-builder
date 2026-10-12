// Keep the maintained executable name produced by dart build cli.
// ignore_for_file: file_names
import 'dart:io';

import 'package:ub_mcp/mcp_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runMcp(
    arguments,
    input: stdin,
    write: (bytes) async {
      stdout.add(bytes);
      await stdout.flush().timeout(const Duration(seconds: 5));
    },
    error: stderr.writeln,
  );
}
