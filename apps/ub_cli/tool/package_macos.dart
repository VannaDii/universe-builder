// Local development assembly only; signing/notarization and release publication
// remain separate operator actions. Run with the workspace's pinned SDKs.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    stdout.writeln(
      'Usage: dart run apps/ub_cli/tool/package_macos.dart [--mode debug|release]',
    );
    return;
  }
  var mode = 'debug';
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 ||
        arguments[0] != '--mode' ||
        !{'debug', 'release'}.contains(arguments[1])) {
      stderr.writeln('Expected --mode debug or --mode release.');
      exitCode = 2;
      return;
    }
    mode = arguments[1];
  }
  if (!Platform.isMacOS) {
    stderr.writeln('This assembly command requires macOS.');
    exitCode = 2;
    return;
  }
  final root = File.fromUri(Platform.script)
      .absolute
      .parent
      .parent
      .parent
      .parent;
  try {
    await _package(root, mode);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<void> _run(String executable, List<String> arguments, String cwd) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await process.exitCode != 0) {
    throw StateError('Build or signing command failed: $executable');
  }
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _copyTree(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entry in source.list(followLinks: false)) {
    final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
    if (entry is File) {
      await entry.copy('${destination.path}/$name');
    } else if (entry is Directory) {
      await _copyTree(entry, Directory('${destination.path}/$name'));
    } else {
      throw const FileSystemException(
        'Build assets must be regular files or directories',
      );
    }
  }
}

Future<void> _package(Directory root, String mode) async {
  final app = Directory('${root.path}/apps/ub_app');
  final configuration = mode == 'debug' ? 'Debug' : 'Release';
  final bundle = Directory(
    '${app.path}/build/macos/Build/Products/$configuration/Universe Builder.app',
  );
  final contents = '${bundle.path}/Contents';
  const helpers = {
    'universe-engine': 'ub_engine',
    'universe-mcp': 'ub_mcp',
    'universe': 'ub_cli',
    'multiverse-mcp': 'ub_cli',
  };
  // An app or helper from this exact build destination must be stopped before
  // replacing it. Never stop a user's process or touch their installation here.
  final processes = await Process.run('/bin/ps', ['-ww', '-axo', 'command=']);
  if (processes.exitCode != 0) {
    throw StateError('Could not check running bundle processes');
  }
  final executables = [
    'Universe Builder',
    ...helpers.keys,
    'universe-engine-sandbox',
  ].map((name) => '$contents/MacOS/$name');
  if (const LineSplitter()
      .convert(processes.stdout as String)
      .any(
        (line) => executables.any(
          (path) => line.trim() == path || line.trim().startsWith('$path '),
        ),
      )) {
    throw StateError(
      'Stop this bundle’s app and helpers before rebuilding. Installation data is retained.',
    );
  }
  final flutter = await Process.run('flutter', ['--version', '--machine']);
  if (flutter.exitCode != 0) throw StateError('Flutter is unavailable');
  final sdk = jsonDecode(flutter.stdout as String) as Map<String, dynamic>;
  final pinnedFlutter = File('${root.path}/.flutter-version')
      .readAsStringSync()
      .trim();
  if (sdk['frameworkVersion'] != pinnedFlutter ||
      sdk['dartSdkVersion'] != '3.13.4') {
    throw StateError(
      'Use Flutter $pinnedFlutter with Dart 3.13.4 from the approved toolchain.',
    );
  }
  for (final helper in helpers.entries) {
    await _run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target',
      'bin/${helper.key}.dart',
      '--output',
      '${root.path}/target/dart-macos/$mode/${helper.key}',
      '--verbosity=error',
    ], '${root.path}/apps/${helper.value}');
  }
  await _run('flutter', ['build', 'web', '--no-pub'], app.path);
  await _run('flutter', ['build', 'macos', '--$mode', '--no-pub'], app.path);
  final libraryDirectory = Directory('$contents/lib');
  if (libraryDirectory.existsSync()) {
    await libraryDirectory.delete(recursive: true);
  }
  await libraryDirectory.create();
  final copiedLibraries = <String, String>{};
  for (final helper in helpers.keys) {
    final native = '${root.path}/target/dart-macos/$mode/$helper/bundle';
    final binary = await File('$native/bin/$helper')
        .copy('$contents/MacOS/$helper');
    await _run('/bin/chmod', ['755', binary.path], root.path);
    await for (final library in Directory(
      '$native/lib',
    ).list(followLinks: false)) {
      if (library is! File) {
        throw const FileSystemException('Unexpected native asset');
      }
      final name = library.uri.pathSegments.last;
      final digest = await _digest(library);
      if (copiedLibraries.containsKey(name) &&
          copiedLibraries[name] != digest) {
        throw StateError('Native helpers disagree on library $name');
      }
      if (!copiedLibraries.containsKey(name)) {
        await library.copy('${libraryDirectory.path}/$name');
        copiedLibraries[name] = digest;
      }
    }
  }
  // Keep one compiled engine implementation. Only the launch signature differs
  // between the app's sandbox child and the independently launched CLI service.
  await File('$contents/MacOS/universe-engine')
      .copy('$contents/MacOS/universe-engine-sandbox');
  await _run('/bin/chmod', [
    '755',
    '$contents/MacOS/universe-engine-sandbox',
  ], root.path);
  final packagedHelpers = [...helpers.keys, 'universe-engine-sandbox'];
  await File('${root.path}/assets/branding/universe-builder.icns')
      .copy('$contents/Resources/AppIcon.icns');
  final web = Directory('$contents/Resources/web');
  if (web.existsSync()) await web.delete(recursive: true);
  await _copyTree(Directory('${app.path}/build/web'), web);

  final temporary = Directory.systemTemp.createTempSync('ub-helper-signing-');
  try {
    final entitlements = File('${temporary.path}/helper.plist');
    await entitlements.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.inherit</key><true/>
</dict></plist>
''');
    for (final name in copiedLibraries.keys) {
      await _run('/usr/bin/codesign', [
        '--force',
        '--sign',
        '-',
        '${libraryDirectory.path}/$name',
      ], root.path);
    }
    for (final helper in packagedHelpers) {
      await _run('/usr/bin/codesign', [
        '--force',
        '--sign',
        '-',
        if (helper == 'universe-engine-sandbox') ...[
          '--entitlements',
          entitlements.path,
        ],
        '$contents/MacOS/$helper',
      ], root.path);
    }
  } finally {
    await temporary.delete(recursive: true);
  }
  final version = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Print :CFBundleShortVersionString',
    '$contents/Info.plist',
  ]);
  if (version.exitCode != 0) throw StateError('Bundle version unavailable');
  final manifest = {
    'format': 1,
    'version': (version.stdout as String).trim(),
    'channel': 'local-development',
    'helpers': {
      for (final helper in packagedHelpers)
        helper: await _digest(File('$contents/MacOS/$helper')),
    },
    'desktop_integrity': 'Sealed by the bundle code signature',
    'release_accepted': false,
  };
  await File(
    '$contents/Resources/release-manifest.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  final runnerEntitlements = mode == 'debug'
      ? 'DebugProfile.entitlements'
      : 'Release.entitlements';
  await _run('/usr/bin/codesign', [
    '--force',
    '--sign',
    '-',
    '--entitlements',
    '${app.path}/macos/Runner/$runnerEntitlements',
    bundle.path,
  ], root.path);
  await _run('/usr/bin/codesign', [
    '--verify',
    '--deep',
    '--strict',
    bundle.path,
  ], root.path);
  stdout.writeln(bundle.path);
}
