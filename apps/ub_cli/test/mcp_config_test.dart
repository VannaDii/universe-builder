@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final script = File('../../tool/mcp_config.dart').absolute.path;
  Future<ProcessResult> run(List<String> arguments) =>
      Process.run(Platform.resolvedExecutable, ['run', script, ...arguments]);

  test(
    'fixture host configuration preserves literal absolute arguments',
    () async {
      const helper = '/Applications/Universe Builder é/\$literal/universe-mcp';
      const socket = '/tmp/Universe 記憶 "quoted"/fixture.sock';
      final result = await run([helper, socket]);
      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout as String), {
        'mcpServers': {
          'universe-builder-fixture': {
            'command': helper,
            'args': ['--fixture', '--socket', socket],
          },
        },
      });
    },
  );

  test(
    'missing, extra and relative arguments produce no host configuration',
    () async {
      for (final arguments in <List<String>>[
        [],
        ['/absolute/helper'],
        ['/absolute/helper', '/absolute/socket', 'extra'],
        ['relative-helper', '/absolute/socket'],
        ['/absolute/helper', 'relative-socket'],
      ]) {
        final result = await run(arguments);
        expect(result.exitCode, 2);
        expect(result.stdout, isEmpty);
        expect(result.stderr, contains('ABSOLUTE_MCP_HELPER ABSOLUTE_SOCKET'));
      }
    },
  );
}
