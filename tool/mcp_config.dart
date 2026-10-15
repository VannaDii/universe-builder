import 'dart:convert';
import 'dart:io';

/// Prints a disposable fixture host configuration without connecting to the
/// engine, reading credentials or changing the host's settings.
void main(List<String> arguments) {
  if (arguments.length != 2 ||
      arguments.any((value) => value.contains('\u0000')) ||
      !File(arguments[0]).isAbsolute ||
      !File(arguments[1]).isAbsolute) {
    stderr.writeln(
      'Usage: dart run tool/mcp_config.dart ABSOLUTE_MCP_HELPER ABSOLUTE_SOCKET',
    );
    exitCode = 2;
    return;
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'universe-builder-fixture': {
          'command': arguments[0],
          'args': ['--fixture', '--socket', arguments[1]],
        },
      },
    }),
  );
}
