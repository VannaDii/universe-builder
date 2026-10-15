@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../tool/src/distribution.dart';

void main() {
  late Directory temporary;
  final template = File('../../packaging/multiverse-mcp.rb.in');
  setUp(
    () => temporary = Directory.systemTemp.createTempSync('ub-distribution-'),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  test('formula uses each archive checksum and the Flutter bundle name', () async {
    for (final arch in architectures.keys) {
      File('${temporary.path}/${assetName('0.1.0', arch)}')
          .writeAsStringSync(arch);
    }
    final result = await formula(
      temporary,
      '0.1.0',
      template,
      repository: 'example/universe',
    );
    for (final arch in architectures.keys) {
      expect(
        result,
        contains(
          'https://github.com/example/universe/releases/download/v0.1.0/${assetName('0.1.0', arch)}',
        ),
      );
      expect(result, contains(sha256.convert(utf8.encode(arch)).toString()));
    }
    expect(
      result,
      contains('Universe Builder.app/Contents/MacOS/multiverse-mcp'),
    );
    expect(result, isNot(contains('Multiverse MCP.app')));
    final local = await formula(temporary, '0.1.0', template, local: true);
    expect(local, contains(temporary.absolute.uri.toString()));
    expect(local, isNot(contains('releases/download')));
  });

  test('local formula restricts architecture; remote requires both', () async {
    await expectLater(
      formula(temporary, '0.1.0', template, local: true),
      throwsA(isA<FileSystemException>()),
    );
    File('${temporary.path}/${assetName('0.1.0', 'arm64')}')
        .writeAsStringSync('local');
    final local = await formula(temporary, '0.1.0', template, local: true);
    expect(local, contains('depends_on arch: :arm64'));
    expect(local, isNot(contains('on_intel')));
    await expectLater(
      formula(temporary, '0.1.0', template, repository: 'example/universe'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('signed archive preserves links and rejects tampered resources', () async {
    Future<void> run(String executable, List<String> arguments) async {
      final result = await Process.run(executable, arguments);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    final bundle = Directory('${temporary.path}/Universe Builder.app');
    Directory('${bundle.path}/Contents/MacOS').createSync(recursive: true);
    Directory('${bundle.path}/Contents/Resources').createSync();
    File('/usr/bin/true').copySync('${bundle.path}/Contents/MacOS/fixture');
    File('${bundle.path}/Contents/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>fixture</string>
<key>CFBundleIdentifier</key><string>example.ub.distribution.fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
''');
    final metadata = File(
      '${bundle.path}/Contents/Resources/release-manifest.json',
    );
    metadata.writeAsStringSync(
      jsonEncode({
        'version': '0.1.0',
        'architecture': 'arm64',
        'dirty_build': false,
        'build_mode': 'release',
        'channel': 'local-development',
        'release_accepted': false,
      }),
    );
    Link('${bundle.path}/Contents/Resources/current.json')
        .createSync('release-manifest.json');
    await run('/usr/bin/codesign', ['--force', '--sign', '-', bundle.path]);
    final packed = await archive(
      bundle,
      Directory('${temporary.path}/assets'),
      'v0.1.0',
    );
    expect(
      File('${packed.path}.sha256').readAsStringSync(),
      '${sha256.convert(packed.readAsBytesSync())}  ${assetName('0.1.0', 'arm64')}\n',
    );
    final extracted = Directory('${temporary.path}/extracted')..createSync();
    await run('/usr/bin/tar', ['-xzf', packed.path, '-C', extracted.path]);
    final restored = '${extracted.path}/Universe Builder.app';
    expect(
      Link('$restored/Contents/Resources/current.json').targetSync(),
      'release-manifest.json',
    );
    await run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      restored,
    ]);
    metadata.writeAsStringSync('${metadata.readAsStringSync()}\n');
    await expectLater(
      archive(bundle, Directory('${temporary.path}/tampered'), 'v0.1.0'),
      throwsA(isA<ProcessException>()),
    );
  }, skip: !Platform.isMacOS);

  test('rejects version, architecture and Ruby injection', () async {
    for (final value in [
      '../1',
      'v0.1.0',
      '0.1',
      '0.1.0";system("id")',
      '0.1.0\n',
    ]) {
      expect(() => releaseVersion(value), throwsFormatException);
    }
    expect(() => assetName('0.1.0', '../arm64'), throwsFormatException);
    await expectLater(
      formula(temporary, '0.1.0', template, repository: 'owner/repo"'),
      throwsFormatException,
    );
  });

  test(
    'archive rejects wrong tag, dirty sources and debug before signing',
    () async {
      final bundle = Directory('${temporary.path}/Universe Builder.app');
      final metadata = File(
        '${bundle.path}/Contents/Resources/release-manifest.json',
      );
      metadata.parent.createSync(recursive: true);
      metadata.writeAsStringSync(
        jsonEncode({'version': '0.1.0', 'dirty_build': true}),
      );
      await expectLater(
        archive(bundle, temporary, 'v0.2.0'),
        throwsFormatException,
      );
      await expectLater(
        archive(bundle, temporary, 'v0.1.0'),
        throwsFormatException,
      );
      await expectLater(
        archive(bundle, temporary, 'v0.1.0', allowDirty: true),
        throwsFormatException,
      );
    },
  );
}
