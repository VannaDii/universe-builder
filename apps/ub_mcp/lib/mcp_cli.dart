import 'dart:convert';

import 'package:ub_client/local_engine.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_domain/ub_domain.dart';

import 'local_backend.dart';
import 'session.dart';
import 'stdio.dart';

const _usage =
    'Usage: universe-mcp --installation <path> --profile <id> [--advanced-tools]';

Future<int> runMcp(
  List<String> arguments, {
  required Stream<List<int>> input,
  required Future<void> Function(List<int>) write,
  required void Function(String) error,
  Future<String> Function()? engineHelper,
}) async {
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    await write(utf8.encode('$_usage\n'));
    return 0;
  }
  String? root, profileText;
  var advanced = false;
  try {
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '--advanced-tools') {
        if (advanced) throw const FormatException('Duplicate option');
        advanced = true;
        continue;
      }
      final equal = argument.indexOf('=');
      final option = equal < 0 ? argument : argument.substring(0, equal);
      if (!{'--installation', '--profile'}.contains(option)) {
        throw const FormatException('Unknown option');
      }
      final value = equal < 0
          ? (++i < arguments.length ? arguments[i] : '')
          : argument.substring(equal + 1);
      if (value.isEmpty || value.startsWith('--') || value.contains('\u0000')) {
        throw const FormatException('Missing option value');
      }
      if (option == '--installation') {
        if (root != null) throw const FormatException('Duplicate option');
        root = value;
      } else {
        if (profileText != null) {
          throw const FormatException('Duplicate option');
        }
        profileText = value;
      }
    }
    if (root == null || profileText == null) {
      throw const FormatException('Installation and profile required');
    }
    final profile = ProfileId.parse(profileText);
    final helper = await (engineHelper ?? LocalEngineClient.siblingEngine)();
    final ready = await LoopbackEngineClient.ensureRunning(
      compatibilitySocket: false,
      root: root,
      profile: profile,
      helper: helper,
      clientName: 'mcp-adapter',
    );
    await ready.close();
    final session = McpSession(
      serverName: 'universe-mcp',
      serverVersion: '0.1.0',
      advanced: advanced,
      backend: (request, cancelled) => callLocalMcpTool(
        root: root!,
        profile: profile,
        request: request,
        cancelled: cancelled,
      ),
    );
    final success = await serveMcpStdio(
      input: input,
      write: write,
      session: session,
    );
    if (!success) {
      error(
        'MCP transport stopped; recover uncertain mutations with their original idempotency key.',
      );
    }
    return success ? 0 : 1;
  } on FormatException {
    error(_usage);
    return 2;
  } on Object {
    error('MCP startup failed. Check the selected installation and profile.');
    return 1;
  }
}
