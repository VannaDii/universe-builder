import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const architectures = {
  'arm64': 'aarch64-apple-darwin',
  'x86_64': 'x86_64-apple-darwin',
};

String releaseVersion(String value) {
  if (!RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(value)) {
    throw const FormatException(
      'Expected a semantic version without the v prefix',
    );
  }
  return value;
}

String assetName(String version, String architecture) {
  final target = architectures[architecture];
  if (target == null) throw const FormatException('Unsupported architecture');
  return 'multiverse-mcp-${releaseVersion(version)}-$target.tar.gz';
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _run(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      command,
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
}

Future<File> archive(
  Directory bundle,
  Directory output,
  String tag, {
  bool allowDirty = false,
}) async {
  final manifest = jsonDecode(
    await File('${bundle.path}/Contents/Resources/release-manifest.json')
        .readAsString(),
  ) as Map<String, dynamic>;
  final version = releaseVersion(manifest['version'] as String);
  if (tag != 'v$version') {
    throw const FormatException(
      'Git tag must match the bundle version exactly',
    );
  }
  if (manifest['dirty_build'] != false && !allowDirty) {
    throw const FormatException(
      'Archives require a clean source tree; --allow-dirty is for local checks only',
    );
  }
  final name = bundle.absolute.uri.pathSegments.where((p) => p.isNotEmpty).last;
  if (name != 'Universe Builder.app' ||
      manifest['build_mode'] != 'release' ||
      manifest['channel'] != 'local-development' ||
      manifest['release_accepted'] != false) {
    throw const FormatException(
      'Use package_macos.dart --mode release to assemble the Flutter preview bundle',
    );
  }
  final asset = assetName(version, manifest['architecture'] as String);
  await _run('/usr/bin/codesign', [
    '--verify',
    '--deep',
    '--strict',
    bundle.absolute.path,
  ]);
  await output.create(recursive: true);
  final destination = File('${output.absolute.path}/$asset');
  // Keep framework symlinks and the complete sealed app at the archive root.
  await _run('/usr/bin/tar', [
    '-czf',
    destination.path,
    '-C',
    bundle.absolute.parent.path,
    '--',
    name,
  ]);
  await File('${destination.path}.sha256')
      .writeAsString('${await _digest(destination)}  $asset\n');
  return destination;
}

String _ruby(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('#', r'\#');

Future<String> formula(
  Directory assets,
  String version,
  File template, {
  String? repository,
  bool local = false,
}) async {
  releaseVersion(version);
  if ((repository != null &&
          !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) ||
      (!local && repository == null)) {
    throw const FormatException('Expected GitHub owner/repository');
  }
  final downloads = <String>[];
  final present = <String>[];
  for (final architecture in architectures.keys) {
    final name = assetName(version, architecture);
    final file = File('${assets.path}/$name');
    if (local && !await file.exists()) continue;
    final digest = await _digest(file);
    final url = local
        ? file.absolute.uri.toString()
        : 'https://github.com/$repository/releases/download/v$version/$name';
    final key = architecture == 'arm64' ? 'arm' : 'intel';
    downloads.add(
      '  on_$key do\n    url "${_ruby(url)}"\n    sha256 "$digest"\n  end\n',
    );
    present.add(architecture);
  }
  if (present.isEmpty) {
    throw const FileSystemException('No local release archives found');
  }
  final values = {
    'homepage': repository == null
        ? 'https://brew.sh'
        : 'https://github.com/$repository',
    'version': version,
    'bundle_name': 'Universe Builder.app',
    'downloads': downloads.join('\n'),
    'architecture_dependency': present.length == 1
        ? '  depends_on arch: :${present.single}\n'
        : '',
  };
  return (await template.readAsString()).replaceAllMapped(
    RegExp(r'\$([a-z_]+)'),
    (match) =>
        values[match[1]] ??
        (throw FormatException('Unknown template variable: ${match[1]}')),
  );
}
