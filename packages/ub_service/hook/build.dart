import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'ub_credentials',
      assetName: 'src/native_credentials.dart',
      sources: ['src/native/credentials.c'],
      frameworks: input.config.code.targetOS == OS.macOS
          ? ['Security', 'CoreFoundation']
          : [],
    ).run(input: input, output: output);
  });
}
