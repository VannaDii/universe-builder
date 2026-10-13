@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_cli/universe_cli.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_settings.dart';

void main() {
  test(
    'configure saves SQLite explicitly without a profile or engine launch',
    () async {
      final root = Directory('/tmp').createTempSync('ub-configure-cli-');
      final store = SqliteInstallationStore.create(root.path);
      final instance = store.instanceId;
      store.close();
      final output = <String>[], errors = <String>[];
      try {
        expect(
          await runUniverseCli(
            ['--installation', root.path, 'configure', 'sqlite'],
            output: output.add,
            error: errors.add,
            engineHelper: () async => throw StateError('must not launch'),
            readInput: () async => throw StateError('must not read secret'),
          ),
          0,
        );
        expect(output.single, contains(instance.value));
        expect(errors, isEmpty);
        final settings = LocalSettingsStore.openExisting(
          '${root.path}/settings.sqlite',
        );
        try {
          expect(settings.readBackendSelection(), isFalse);
        } finally {
          settings.close();
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );
  test('invalid secret input and options neither save nor launch', () async {
    final root = Directory('/tmp').createTempSync('ub-configure-invalid-');
    try {
      for (final arguments in <List<String>>[
        ['configure', 'postgres'],
        ['configure', 'unknown'],
        ['configure', 'sqlite', '--allow-loopback-postgres-development'],
      ]) {
        final errors = <String>[];
        expect(
          await runUniverseCli(
            ['--installation', root.path, ...arguments],
            output: (_) => fail('must not print secret'),
            error: errors.add,
            engineHelper: () async => throw StateError('must not launch'),
            readInput: () async =>
                Uint8List.fromList(utf8.encode('invalid private_password\n')),
          ),
          isNot(0),
        );
        expect(errors.join(), isNot(contains('private_password')));
        expect(File('${root.path}/settings.sqlite').existsSync(), isFalse);
        expect(File('${root.path}/installation.sqlite').existsSync(), isFalse);
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
