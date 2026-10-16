@TestOn('vm && linux')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_cli/desktop_launcher.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'Linux menu entry preserves literal arguments and refuses replacement',
    () async {
      final root = Directory.systemTemp.createTempSync('ub-linux-shortcut-');
      try {
        final icons = Directory('${root.path}/desktop/data/icons')
          ..createSync(recursive: true);
        File('../../assets/branding/universe-builder-symbol-4k.png')
            .copySync('${icons.path}/universe-builder.png');
        Directory('${root.path}/bin').createSync();
        final capture = File('${root.path}/args');
        final launcher = File('${root.path}/${r'''stable '"\ $` %launcher'''}');
        launcher.writeAsStringSync(
          '#!/bin/sh\nprintf "%s\\n" "\$@" > "${capture.path}"\n',
        );
        expect(
          (await Process.run('/bin/chmod', ['755', launcher.path])).exitCode,
          0,
        );
        final options = DesktopOptions.parse([
          '--destination',
          '${root.path}/menu',
          '--launcher',
          launcher.path,
          '--installation',
          '${root.path}/${r'''a b;$(touch should-not-exist)"#%F\é'''}',
          '--profile',
          ProfileId.generate().value,
        ], shortcut: true);
        final engine = '${root.path}/bin/universe-engine';
        final path = await createLinuxShortcut(
          engine: engine,
          options: options,
        );
        final before = File(path).readAsStringSync();
        expect(before, contains('Icon=${icons.path}/universe-builder.png'));
        final launched = await Process.run('gio', ['launch', path]);
        expect(launched.exitCode, 0, reason: '${launched.stderr}');
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!capture.existsSync() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(capture.readAsLinesSync(), ['ux', ...options.arguments]);
        expect(before, contains('MimeType=x-scheme-handler/universe-builder;'));
        capture.deleteSync();
        const link = 'universe-builder:///help';
        final linked = await Process.run('gio', ['launch', path, link]);
        expect(linked.exitCode, 0, reason: '${linked.stderr}');
        final linkDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (!capture.existsSync() && DateTime.now().isBefore(linkDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(capture.readAsLinesSync(), ['ux', ...options.arguments, link]);
        expect(File('${root.path}/should-not-exist').existsSync(), isFalse);
        await expectLater(
          createLinuxShortcut(engine: engine, options: options),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(path).readAsStringSync(), before);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('Linux desktop executable is selected from its packaged directory', () {
    final root = Directory.systemTemp.createTempSync('ub-linux-layout-');
    try {
      Directory('${root.path}/desktop').createSync();
      File('${root.path}/desktop/universe_builder')
          .writeAsStringSync('fixture');
      final command = desktopCommand('${root.path}/bin/universe-engine', [
        '--fixture',
      ]);
      expect(command.executable, '${root.path}/desktop/universe_builder');
      expect(command.arguments, ['--fixture']);
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
