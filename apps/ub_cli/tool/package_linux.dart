import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  const usage =
      'Usage: dart run apps/ub_cli/tool/package_linux.dart --output NEW_DIRECTORY';
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    stdout.writeln(usage);
    return;
  }
  try {
    if (arguments.length != 2 || arguments.first != '--output') {
      throw const FormatException(usage);
    }
    if (!Platform.isLinux) {
      throw UnsupportedError('Linux assembly requires Linux');
    }
    final architecture = Abi.current() == Abi.linuxArm64
        ? 'arm64'
        : Abi.current() == Abi.linuxX64
        ? 'x64'
        : null;
    if (architecture == null) {
      throw UnsupportedError('Supported Linux architectures are arm64 and x64');
    }
    final root = File.fromUri(Platform.script)
        .absolute
        .parent
        .parent
        .parent
        .parent;
    final app = '${root.path}/apps/ub_app';
    final output = Directory(arguments[1]).absolute;
    if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Choose a fresh output directory');
    }
    final flutter = await Process.run('flutter', ['--version', '--machine']);
    if (flutter.exitCode != 0) throw StateError('Flutter unavailable');
    final sdk = jsonDecode(flutter.stdout as String) as Map<String, dynamic>;
    final pinned = File('${root.path}/.flutter-version')
        .readAsStringSync()
        .trim();
    if (sdk['frameworkVersion'] != pinned ||
        sdk['dartSdkVersion'] != '3.13.4') {
      throw StateError('Use pinned Flutter $pinned and Dart 3.13.4');
    }
    await output.parent.create(recursive: true);
    final temporary = await output.parent.createTemp('.ub-linux-assembly-');
    try {
      final assembled = Directory('${temporary.path}/package');
      await _run(Platform.resolvedExecutable, [
        '${root.path}/apps/ub_cli/tool/package_headless.dart',
        '--output',
        assembled.path,
      ], root.path);
      await _run('flutter', ['build', 'linux', '--release', '--no-pub'], app);
      await _run('flutter', ['build', 'web', '--no-pub'], app);
      await _copy(
        Directory('$app/build/linux/$architecture/release/bundle'),
        Directory('${assembled.path}/desktop'),
      );
      await _run('/bin/chmod', [
        '755',
        '${assembled.path}/desktop/universe_builder',
      ], root.path);
      await _copy(
        Directory('$app/build/web'),
        Directory('${assembled.path}/bin/web'),
      );
      final icons = await Directory('${assembled.path}/desktop/data/icons')
          .create(recursive: true);
      await File('${root.path}/assets/branding/universe-builder-symbol-4k.png')
          .copy('${icons.path}/universe-builder.png');
      await _run('/bin/chmod', ['755', icons.path], root.path);
      await _run('/bin/chmod', [
        '644',
        '${icons.path}/universe-builder.png',
      ], root.path);
      final manifestFile = File('${assembled.path}/release-manifest.json');
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      manifest['desktop'] = {
        'binary': 'desktop/universe_builder',
        'sha256':
            (await sha256
                    .bind(
                      File('${assembled.path}/desktop/universe_builder')
                          .openRead(),
                    )
                    .first)
                .toString(),
        'flutter': pinned,
      };
      manifest['web_assets'] = 'bin/web';
      await manifestFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      );
      if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Output already exists');
      }
      await assembled.rename(output.path);
      stdout.writeln(output.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<void> _run(String executable, List<String> arguments, String cwd) async {
  final child = await Process.start(
    executable,
    arguments,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await child.exitCode != 0) {
    throw StateError('Assembly command failed: $executable');
  }
}

Future<void> _copy(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await _run('/bin/chmod', ['755', destination.path], source.path);
  final files = <String>[];
  await for (final entry in source.list(followLinks: false)) {
    final path =
        '${destination.path}/${entry.uri.pathSegments.where((p) => p.isNotEmpty).last}';
    if (entry is Directory) {
      await _copy(entry, Directory(path));
    } else if (entry is File) {
      await entry.copy(path);
      files.add(path);
    } else {
      throw const FileSystemException('Unexpected nonregular build asset');
    }
  }
  if (files.isNotEmpty) {
    await _run('/bin/chmod', ['644', ...files], source.path);
  }
}
