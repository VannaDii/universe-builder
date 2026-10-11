import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'ub_ownership',
      assetName: 'src/native_ownership.dart',
      sources: ['src/native/ownership.c'],
    ).run(input: input, output: output);
  });
}
