@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_cli/desktop_launcher.dart';
import 'package:ub_cli/launcher.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('desktop connection options are complete, literal and validated before launch', () {
    final profile = ProfileId.generate();
    final parsed = DesktopOptions.parse([
      '--installation',
      'a b;\$(unexecuted)',
      '--profile=${profile.value}',
    ], shortcut: false);
    expect(parsed.arguments, [
      '--installation',
      Directory('a b;\$(unexecuted)').absolute.path,
      '--profile',
      profile.value,
    ]);
    expect(DesktopOptions.parse([], shortcut: false).arguments, isEmpty);
    for (final args in [
      ['--installation', '/tmp/only'],
      ['--profile', profile.value],
      ['--profile', 'invalid', '--installation', '/tmp/x'],
      ['--profile', profile.value, '--profile', profile.value],
      ['--launcher', '/tmp/not-ux'],
      ['--installation'],
    ]) {
      expect(
        () => DesktopOptions.parse(args, shortcut: false),
        throwsFormatException,
      );
    }
    final command = desktopCommand(
      '/tmp/Universe Builder.app/Contents/MacOS/universe-engine',
      parsed.arguments,
      macOS: true,
    );
    expect(command.executable, '/usr/bin/open');
    expect(command.arguments, [
      '-n',
      '/tmp/Universe Builder.app',
      '--args',
      ...parsed.arguments,
    ]);
  });

  test(
    'desktop application links preserve literal routes and reject unsafe URLs',
    () {
      const link = 'universe-builder:///help';
      for (final args in [
        ['--link', link],
        ['--link=$link'],
        [link],
      ]) {
        expect(DesktopOptions.parse(args, shortcut: false).arguments, [
          '--link',
          link,
        ]);
      }
      final profile = ProfileId.generate().value;
      expect(
        DesktopOptions.parse([
          '--installation',
          '/tmp/linked instance',
          '--profile',
          profile,
          link,
        ], shortcut: false).arguments,
        [
          '--installation',
          '/tmp/linked instance',
          '--profile',
          profile,
          '--link',
          link,
        ],
      );
      for (final args in [
        ['--link'],
        ['--link', link, link],
        ['--link', link, '--link', link],
        ['--fixture', '--link', link],
        for (final url in [
          'https:///help',
          'universe-builder://host/help',
          'universe-builder://user:password@host/help',
          'universe-builder:help',
          'universe-builder:///help?token=secret',
          'universe-builder:///help#fragment',
          'universe-builder:///help\u0000',
        ])
          ['--link', url],
      ]) {
        expect(
          () => DesktopOptions.parse(args, shortcut: false),
          throwsFormatException,
          reason: '$args',
        );
      }
      expect(
        () => DesktopOptions.parse(['--link', link], shortcut: true),
        throwsFormatException,
      );
    },
  );

  test(
    'fixture launch is explicit and cannot inherit a persistent connection',
    () {
      expect(DesktopOptions.parse(['--fixture'], shortcut: false).arguments, [
        '--fixture',
      ]);
      for (final args in [
        ['--fixture', '--installation', '/tmp/installation'],
        ['--fixture', '--profile', ProfileId.generate().value],
        ['--fixture', '--fixture'],
      ]) {
        expect(
          () => DesktopOptions.parse(args, shortcut: false),
          throwsFormatException,
        );
      }
      expect(
        () => DesktopOptions.parse(['--fixture'], shortcut: true),
        throwsFormatException,
      );
    },
  );

  test('unbundled desktop receives literal connection args and returns its exit status', () async {
    final root = Directory.systemTemp.createTempSync('ub-desktop-launch-');
    try {
      final capture = File('${root.path}/args');
      final gui = File('${root.path}/universe_builder');
      gui.writeAsStringSync(
        '#!/bin/sh\nprintf "%s\\n" "\$@" > "${capture.path}"\nexit 19\n',
      );
      expect((await Process.run('/bin/chmod', ['755', gui.path])).exitCode, 0);
      final profile = ProfileId.generate();
      final args = [
        '--installation',
        '${root.path}/a b;\$(touch bad)',
        '--profile',
        profile.value,
      ];
      expect(
        await runLauncher(
          ['ux', ...args],
          output: (_) {},
          error: fail,
          engineHelper: () async => '${root.path}/universe-engine',
        ),
        19,
      );
      expect(capture.readAsLinesSync(), args);
      expect(File('${root.path}/bad').existsSync(), isFalse);
    } finally {
      root.deleteSync(recursive: true);
    }
  }, skip: Platform.isWindows ? 'POSIX process fixture' : false);

  test('Finder shortcut uses exact icon, quotes literal args and refuses replacement', () async {
    final root = Directory.systemTemp.createTempSync('ub-shortcut-');
    try {
      final contents = Directory('${root.path}/Bundle.app/Contents');
      Directory('${contents.path}/MacOS').createSync(recursive: true);
      Directory('${contents.path}/Resources').createSync();
      final approved = File('../../assets/branding/universe-builder.icns');
      approved.copySync('${contents.path}/Resources/AppIcon.icns');
      final capture = File('${root.path}/received');
      final target = File("${root.path}/stable 'launcher");
      target.writeAsStringSync(
        '#!/bin/sh\nprintf "%s\\n" "\$@" > "${capture.path}"\n',
      );
      expect(
        (await Process.run('/bin/chmod', ['755', target.path])).exitCode,
        0,
      );
      final profile = ProfileId.generate();
      final options = DesktopOptions.parse([
        '--destination',
        '${root.path}/Finder',
        '--launcher',
        target.path,
        '--installation',
        "${root.path}/a 'b;\$(touch bad)",
        '--profile',
        profile.value,
      ], shortcut: true);
      final engine = '${contents.path}/MacOS/universe-engine';
      final app = await createFinderShortcut(engine: engine, options: options);
      final script = File('$app/Contents/MacOS/launch');
      final original = script.readAsStringSync();
      expect((await Process.run(script.path, [])).exitCode, 0);
      expect(capture.readAsLinesSync(), ['ux', ...options.arguments]);
      expect(
        File('$app/Contents/Resources/universe-builder.icns').readAsBytesSync(),
        approved.readAsBytesSync(),
      );
      await expectLater(
        createFinderShortcut(engine: engine, options: options),
        throwsFormatException,
      );
      expect(script.readAsStringSync(), original);
      expect(File('${root.path}/bad').existsSync(), isFalse);
      // A pre-existing link is also refused and its target remains untouched.
      Directory(app).renameSync('$app.saved');
      Link(app).createSync('$app.saved');
      await expectLater(
        createFinderShortcut(engine: engine, options: options),
        throwsFormatException,
      );
      expect(
        File('$app.saved/Contents/MacOS/launch').readAsStringSync(),
        original,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  }, skip: Platform.isMacOS ? false : 'Finder shortcut is macOS-only');
}
