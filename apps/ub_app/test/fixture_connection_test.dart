@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ub_app/fixture_connection_native.dart';
import 'package:ub_app/fixture_workspace.dart';
import 'package:ub_store/installation.dart';

void main() {
  test(
    'fixture arguments refuse persistent options before resolving a helper',
    () async {
      for (final args in [
        <String>[],
        ['--fixture', '--installation', '/unused'],
        ['--fixture', '--fixture'],
      ]) {
        await expectLater(
          FixtureDevice(
            args,
            engineHelper: () async => throw StateError('must not resolve'),
          ).start(),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'desktop owns a compiled disposable child and closes it without opening an installation',
    () async {
      final root = Directory('/tmp').createTempSync('ub-fixture-app-');
      final runtime = Directory('${root.path}/runtime');
      privateDirectory(runtime.path);
      FixtureTransport? transport;
      try {
        final engine = await Isolate.resolvePackageUri(
          Uri.parse('package:ub_engine/engine_cli.dart'),
        );
        final compiled = await Process.run(Platform.resolvedExecutable, [
          'build',
          'cli',
          '--target',
          File.fromUri(engine!).parent.parent.uri
              .resolve('bin/universe-engine.dart')
              .toFilePath(),
          '--output',
          '${root.path}/compiled',
          '--verbosity=error',
        ]);
        expect(
          compiled.exitCode,
          0,
          reason: 'Disposable engine compilation failed',
        );
        final device = FixtureDevice(
          ['--fixture'],
          engineHelper: () async =>
              '${root.path}/compiled/bundle/bin/universe-engine',
          temporaryDirectory: runtime,
        );
        transport = await device.start();
        final workspace = FixtureWorkspace(transport);
        await workspace.open();
        expect(workspace.hits, isNotEmpty);
        final draft = workspace.review('Fixture desktop Lamp', 'unspecified');
        final saved = await workspace.save(draft);
        expect(saved.canonical, isFalse);
        expect((await workspace.save(draft)).digest, saved.digest);
        await transport.close();
        expect(runtime.listSync(), isEmpty);
        await expectLater(workspace.open(), throwsStateError);
        transport = await device.start();
        final fresh = FixtureWorkspace(transport);
        await fresh.open();
        expect(fresh.hits.map((h) => h.label), isNot(contains(draft.label)));
      } finally {
        await transport?.close();
        root.deleteSync(recursive: true);
      }
    },
    skip: !Platform.isMacOS && !Platform.isLinux
        ? 'Native Unix fixture desktop'
        : false,
  );
}
