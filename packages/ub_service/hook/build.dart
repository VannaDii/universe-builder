import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final includes = <String>[];
    final libraries = <String>[];
    final libraryDirectories = <String>[];
    final flags = <String>[];
    if (input.config.code.targetOS == OS.linux) {
      final pkg = await Process.run('pkg-config', [
        '--cflags',
        '--libs',
        'libsecret-1',
      ]);
      if (pkg.exitCode != 0) {
        throw StateError(
          'Linux builds require pkg-config and libsecret-1 development headers',
        );
      }
      for (final flag in (pkg.stdout as String).trim().split(RegExp(r'\s+'))) {
        if (flag.startsWith('-I')) {
          includes.add(flag.substring(2));
        } else if (flag.startsWith('-l')) {
          libraries.add(flag.substring(2));
        } else if (flag.startsWith('-L')) {
          libraryDirectories.add(flag.substring(2));
        } else {
          flags.add(flag);
        }
      }
    }
    await CBuilder.library(
      name: 'ub_credentials',
      assetName: 'src/native_credentials.dart',
      sources: ['src/native/credentials.c'],
      includes: includes,
      libraries: libraries,
      libraryDirectories: libraryDirectories,
      flags: flags,
      frameworks: input.config.code.targetOS == OS.macOS
          ? ['Security', 'CoreFoundation']
          : [],
    ).run(input: input, output: output);
  });
}
