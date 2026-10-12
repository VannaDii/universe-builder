@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_cli/launcher.dart';

void main() {
  test('compiled launcher forwards streams and signals outside workspace with empty PATH', () async {
    final root = Directory('/tmp').createTempSync('ub-launch-bin-');
    Process? child;
    try {
      final built = await Process.run(Platform.resolvedExecutable, [
        'build',
        'cli',
        '--target',
        'bin/multiverse-mcp.dart',
        '--output',
        '${root.path}/compiled',
        '--verbosity=error',
      ]);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      final bin = '${root.path}/compiled/bundle/bin';
      final launcher = '$bin/multiverse-mcp';
      final helper = File('$bin/universe');
      helper.writeAsStringSync(
        '#!/bin/sh\n'
        'printf "%s\\n" "\$@"\nexit 17\n',
      );
      expect(
        (await Process.run('/bin/chmod', ['755', helper.path])).exitCode,
        0,
      );
      final result = await Process.run(
        launcher,
        ['admin', '--help', '/tmp/a b;\$(touch ${root.path}/must-not-exist)'],
        workingDirectory: root.path,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 17);
      expect(
        result.stdout,
        '--help\n/tmp/a b;\$(touch ${root.path}/must-not-exist)\n',
      );
      expect(result.stderr, isEmpty);
      expect(File('${root.path}/must-not-exist').existsSync(), isFalse);

      helper.writeAsStringSync(
        '#!/bin/sh\n'
        "trap 'exit 23' TERM\n"
        "printf 'ready\\n'\n"
        'while :; do /bin/sleep 0.05; done\n',
      );
      child = await Process.start(
        launcher,
        ['admin'],
        workingDirectory: root.path,
        environment: {'PATH': ''},
      );
      final errors = child.stderr.toList();
      final lines = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      expect(await lines.first.timeout(const Duration(seconds: 5)), 'ready');
      expect(child.kill(ProcessSignal.sigterm), isTrue);
      expect(await child.exitCode.timeout(const Duration(seconds: 5)), 23);
      expect((await errors).expand((bytes) => bytes), isEmpty);
    } finally {
      child?.kill();
      if (child != null) await child.exitCode;
      root.deleteSync(recursive: true);
    }
  });
  test('help, version and invalid commands do not resolve helpers', () async {
    var resolved = false;
    final output = <String>[], errors = <String>[];
    Future<int> run(List<String> args) => runLauncher(
      args,
      output: output.add,
      error: errors.add,
      engineHelper: () async {
        resolved = true;
        throw StateError('must not resolve');
      },
    );
    expect(await run(['--help']), 0);
    expect(output.single, contains('serve'));
    output.clear();
    expect(await run(['--version']), 0);
    expect(output.single, startsWith('multiverse-mcp '));
    for (final args in <List<String>>[
      [],
      ['unknown'],
      ['ux'],
      ['shortcut'],
    ]) {
      expect(await run(args), 2);
    }
    expect(resolved, isFalse);
  });

  test(
    'forwards exact helper arguments and exit status without shell expansion',
    () async {
      final root = Directory('/tmp').createTempSync('ub-launch-');
      final captured = '${root.path}/arguments';
      final errors = <String>[];
      try {
        for (final name in ['universe', 'universe-mcp']) {
          final helper = File('${root.path}/$name');
          helper.writeAsStringSync(
            '#!/bin/sh\n'
            'printf "%s\\n" "\$@" > "$captured"\nexit 17\n',
          );
          expect(
            (await Process.run('/bin/chmod', ['755', helper.path])).exitCode,
            0,
          );
        }
        for (final command in ['serve', 'admin']) {
          final args = [
            '--installation',
            '/tmp/a b;\$(touch ${root.path}/must-not-exist)',
            '--profile',
            "'quoted'",
            '--help',
            '--',
            'literal',
          ];
          expect(
            await runLauncher(
              [command, ...args],
              output: (_) => fail('protocol output must come only from helper'),
              error: errors.add,
              engineHelper: () async => '${root.path}/universe-engine',
            ),
            17,
          );
          expect(File(captured).readAsLinesSync(), args);
          expect(File('${root.path}/must-not-exist').existsSync(), isFalse);
        }
        expect(errors, isEmpty);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('missing or relative helpers return redacted failure', () async {
    for (final path in [
      'relative/universe-engine',
      '/absent/universe-engine',
    ]) {
      final output = <String>[], errors = <String>[];
      expect(
        await runLauncher(
          ['admin', '--help'],
          output: output.add,
          error: errors.add,
          engineHelper: () async => path,
        ),
        1,
      );
      expect(output, isEmpty);
      expect(
        errors.single,
        'Installed launcher helper unavailable or interrupted.',
      );
    }
  });
}
