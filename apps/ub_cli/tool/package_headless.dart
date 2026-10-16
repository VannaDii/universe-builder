import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  const usage =
      'Usage: dart run apps/ub_cli/tool/package_headless.dart --output NEW_DIRECTORY';
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    stdout.writeln(usage);
    return;
  }
  try {
    if (arguments.length != 2 || arguments.first != '--output') {
      throw const FormatException(usage);
    }
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError(
        'This headless assembler currently supports macOS and Linux',
      );
    }
    if (!Platform.version.startsWith('3.13.4 ')) {
      throw StateError('Use the pinned Dart 3.13.4 toolchain');
    }
    final output = Directory(arguments[1]).absolute;
    if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Output already exists; choose a fresh directory',
        output.path,
      );
    }
    final root = File.fromUri(Platform.script)
        .absolute
        .parent
        .parent
        .parent
        .parent;
    await output.parent.create(recursive: true);
    final build = await output.parent.createTemp('.ub-headless-build-');
    const helpers = {
      'universe-engine': 'ub_engine',
      'universe-mcp': 'ub_mcp',
      'universe': 'ub_cli',
      'multiverse-mcp': 'ub_cli',
    };
    try {
      for (final helper in helpers.entries) {
        final child = await Process.start(
          Platform.resolvedExecutable,
          [
            'build',
            'cli',
            '--target',
            'bin/${helper.key}.dart',
            '--output',
            '${build.path}/${helper.key}',
            '--verbosity=error',
          ],
          workingDirectory: '${root.path}/apps/${helper.value}',
          mode: ProcessStartMode.inheritStdio,
        );
        if (await child.exitCode != 0) {
          throw StateError('Compilation failed: ${helper.key}');
        }
      }
      final bundle = Directory('${build.path}/assembled');
      await Directory('${bundle.path}/bin').create(recursive: true);
      await Directory('${bundle.path}/lib').create();
      final libraries = <String, String>{};
      final binaries = <String, String>{};
      for (final helper in helpers.keys) {
        final source = '${build.path}/$helper/bundle';
        final binary = await File('$source/bin/$helper')
            .copy('${bundle.path}/bin/$helper');
        final permissions = await Process.run('/bin/chmod', [
          '755',
          binary.path,
        ]);
        if (permissions.exitCode != 0) {
          throw StateError('Could not make $helper executable');
        }
        binaries[helper] = await _digest(binary);
        await for (final library in Directory(
          '$source/lib',
        ).list(followLinks: false)) {
          if (library is! File) throw StateError('Unexpected native asset');
          final name = library.uri.pathSegments.last;
          final digest = await _digest(library);
          if (libraries.containsKey(name) && libraries[name] != digest) {
            throw StateError('Native helpers disagree on library $name');
          }
          if (!libraries.containsKey(name)) {
            await library.copy('${bundle.path}/lib/$name');
            libraries[name] = digest;
          }
        }
      }
      final revision = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: root.path);
      final status = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: root.path);
      if (revision.exitCode != 0 || status.exitCode != 0) {
        throw StateError('Source revision unavailable');
      }
      final version = File('${root.path}/apps/ub_cli/pubspec.yaml')
          .readAsLinesSync()
          .singleWhere((line) => line.startsWith('version: '))
          .substring('version: '.length)
          .trim();
      final manifest = {
        'format': 1,
        'version': version,
        'target': Abi.current().toString(),
        'source_revision': (revision.stdout as String).trim(),
        'dirty_build': (status.stdout as String).isNotEmpty,
        'helpers': binaries,
        'native_libraries': libraries,
        'release_accepted': false,
      };
      await File('${bundle.path}/release-manifest.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      );
      // These are distributable software assets, not installation data. Their
      // permissions must work for the runtime user regardless of build umask.
      for (final mode in {
        '755': [bundle.path, '${bundle.path}/bin', '${bundle.path}/lib'],
        '644': [
          '${bundle.path}/release-manifest.json',
          for (final name in libraries.keys) '${bundle.path}/lib/$name',
        ],
      }.entries) {
        final permissions = await Process.run('/bin/chmod', [
          mode.key,
          ...mode.value,
        ]);
        if (permissions.exitCode != 0) {
          throw StateError('Could not set software asset permissions');
        }
      }
      // Publish a complete fresh directory only after every helper is assembled.
      await output.parent.create(recursive: true);
      if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('Output already exists', output.path);
      }
      await bundle.rename(output.path);
      stdout.writeln(output.path);
    } finally {
      await build.delete(recursive: true);
    }
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
