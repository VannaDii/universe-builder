@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_mcp/mcp_cli.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import 'session_test.dart' show field, initialize, call;

void main() {
  test(
    'invalid options fail before helper resolution or authority creation',
    () async {
      var helpers = 0;
      for (final args in <List<String>>[
        [],
        ['--fixture'],
        ['--installation'],
        ['--installation=/absent', '--profile=invalid'],
        [
          '--installation=/absent',
          '--profile=x',
          '--advanced-tools',
          '--advanced-tools',
        ],
      ]) {
        final output = <List<int>>[], errors = <String>[];
        expect(
          await runMcp(
            args,
            input: const Stream.empty(),
            write: (bytes) async => output.add(bytes),
            error: errors.add,
            engineHelper: () async {
              helpers++;
              return '/missing/universe-engine';
            },
          ),
          2,
        );
        expect(output, isEmpty);
        expect(errors.single, startsWith('Usage:'));
      }
      expect(helpers, 0);
    },
  );

  test('stdio reaches real service; current rights and revocation remain authoritative', () async {
    final root = Directory('/tmp').createTempSync('ub-mcp-');
    LocalSqliteEngineServer? engine;
    LocalEngineClient? owner;
    final input = StreamController<List<int>>(),
        output = StreamController<List<int>>();
    final frames = StreamIterator(decodeMcpStdio(output.stream));
    Future<int>? running;
    final errors = <String>[];
    try {
      final store = SqliteInstallationStore.create(root.path);
      final authority = InstallationAuthority(store);
      final author = authority.initializeAuthor();
      final writer = authority.enroll(
        authority.authenticate(
          profile: author,
          credential: Credential(
            ProfileCredentialStore.read(root: root.path, profile: author),
          ),
        ),
      );
      store.close();
      engine = await LocalSqliteEngineServer.start(root.path);
      owner = await LocalEngineClient.connect(
        root: root.path,
        profile: author,
        clientName: 'Disposable MCP owner',
      );
      await owner.call(
        const CreateUniverseEngineRequest(
          name: 'Test',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      running = runMcp(
        ['--installation=${root.path}', '--profile=${author.value}'],
        input: input.stream,
        write: (bytes) async => output.add(bytes),
        error: errors.add,
        engineHelper: () async => '/missing/universe-engine',
      );
      input.add(encodeMcpStdio(initialize));
      expect(
        await frames.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      input.add(encodeMcpStdio(call('9223372036854775807')));
      expect(
        await frames.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final result = field(frames.current, 'result') as CanonicalObject;
      expect(field(result, 'isError').toText(), 'false');
      expect(field(frames.current, 'id').toText(), '9223372036854775807');
      expect(result.toText(), contains('contract_version'));
      await input.close();
      expect(await running, 0);
      expect(errors, isEmpty);

      // Fresh tool authentication must observe a revocation after MCP startup.
      final secondInput = StreamController<List<int>>(),
          secondOutput = StreamController<List<int>>();
      final secondFrames = StreamIterator(decodeMcpStdio(secondOutput.stream));
      final secondRun = runMcp(
        ['--installation', root.path, '--profile', writer.value],
        input: secondInput.stream,
        write: (bytes) async => secondOutput.add(bytes),
        error: errors.add,
        engineHelper: () async => '/missing/universe-engine',
      );
      try {
        secondInput.add(encodeMcpStdio(initialize));
        expect(await secondFrames.moveNext(), isTrue);
        secondInput.add(encodeMcpStdio(call('1')));
        expect(await secondFrames.moveNext(), isTrue);
        expect(
          secondFrames.current.toText(),
          contains('NOT_FOUND_OR_NOT_ACCESSIBLE'),
        );
        await owner.call(RevokeEngineRequest(profileId: writer));
        secondInput.add(encodeMcpStdio(call('2')));
        expect(await secondFrames.moveNext(), isTrue);
        expect(
          secondFrames.current.toText(),
          contains('Engine connection interrupted'),
        );
        expect(secondFrames.current.toText(), isNot(contains('credential')));
      } finally {
        await secondInput.close();
        expect(await secondRun, 0);
        await secondFrames.cancel();
        await secondOutput.close();
      }

      final bundle = '${root.path}/compiled';
      final built = await Process.run(Platform.resolvedExecutable, [
        'build',
        'cli',
        '--target',
        'bin/universe-mcp.dart',
        '--output',
        bundle,
        '--verbosity=error',
      ]);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      final child = await Process.start(
        '$bundle/bundle/bin/universe-mcp',
        ['--installation', root.path, '--profile', author.value],
        workingDirectory: root.path,
        environment: {'PATH': ''},
      );
      final childErrors = child.stderr.toList();
      final childFrames = StreamIterator(decodeMcpStdio(child.stdout));
      try {
        child.stdin.add(encodeMcpStdio(initialize));
        await child.stdin.flush();
        expect(
          await childFrames.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        child.stdin.add(encodeMcpStdio(call('"compiled"')));
        await child.stdin.flush();
        expect(
          await childFrames.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(field(childFrames.current, 'id').toText(), '"compiled"');
        expect(
          field(
            field(childFrames.current, 'result') as CanonicalObject,
            'isError',
          ).toText(),
          'false',
        );
        await child.stdin.close();
        expect(await child.exitCode.timeout(const Duration(seconds: 5)), 0);
        expect((await childErrors).expand((bytes) => bytes), isEmpty);
      } finally {
        child.kill();
        await childFrames.cancel();
        await child.exitCode;
      }
    } finally {
      if (!input.isClosed) await input.close();
      if (running != null) await running;
      await frames.cancel();
      await output.close();
      await owner?.close();
      await engine?.close();
      root.deleteSync(recursive: true);
    }
  });
}
