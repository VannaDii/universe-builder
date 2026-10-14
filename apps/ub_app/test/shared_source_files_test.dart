@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  test(
    'a contributor is not offered owner-only shared source intake',
    () async {
      final root = Directory.systemTemp.createTempSync('ub-shared-access-');
      final store = SqliteInstallationStore.create(root.path);
      final authority = InstallationAuthority(store);
      final author = authority.initializeAuthor();
      final writer = authority.enroll(
        authority.authenticateHello(
          EngineHello(
            protocolVersion: protocolVersion,
            profileId: author,
            credential: Credential(
              ProfileCredentialStore.read(root: root.path, profile: author),
            ),
            clientName: 'Shared source setup',
          ),
        ),
      );
      store.close();
      AppSession? session;
      try {
        session = await DeviceConnection(
          ['--installation', root.path, '--profile', writer.value],
          embeddedLocal: true,
          pickSharedSourcePath: () async =>
              throw StateError('No shared file may be taken implicitly'),
        ).connect();
        expect(session.author, isFalse);
        expect(session.pickSharedSourceText, isNull);
      } finally {
        await session?.close();
        root.deleteSync(recursive: true);
      }
    },
  );
  test('shared source is consumed only by explicit choice, preserves exact text and releases invalid input', () async {
    final root = Directory.systemTemp.createTempSync('ub-shared-source-');
    const text = '\uFEFFMemory café 記憶 😀\r\nFirsthand account.\r\n';
    final source = File('${root.path}/Shared memoir.md')
      ..writeAsBytesSync(utf8.encode(text));
    String? pending = source.path;
    final released = <String>[];
    var choices = 0;
    final uiOnly = ReceivePort();
    final device = DeviceConnection(
      ['--installation', '${root.path}/Installation'],
      embeddedLocal: true,
      pickSharedSourcePath: () async {
        uiOnly.close(); // A UI callback is deliberately not isolate-sendable.
        choices++;
        return pending;
      },
      releasePickedPath: (path) async {
        released.add(path);
        pending = null;
        File(path).deleteSync();
      },
    );
    AppSession? session;
    try {
      session = await device.connect();
      expect(choices, 0);
      expect(source.existsSync(), isTrue);
      final picked = (await session.pickSharedSourceText!())!;
      expect(picked.name, 'Shared memoir.md');
      expect(picked.text, text);
      expect(released, [source.path]);
      expect(source.existsSync(), isFalse);
      expect(
        InstanceLibrary.fromWire(
          await session.call(const StatusEngineRequest()),
        ).universes,
        isEmpty,
      );
      final invalid = File('${root.path}/invalid.txt')
        ..writeAsBytesSync([0xc3, 0x28]);
      pending = invalid.path;
      await expectLater(session.pickSharedSourceText!(), throwsFormatException);
      expect(released.last, invalid.path);
      expect(invalid.existsSync(), isFalse);
      final oversized = File('${root.path}/too-large.txt')
        ..writeAsBytesSync(List.filled(maxFrameBytes + 1, 65));
      pending = oversized.path;
      await expectLater(session.pickSharedSourceText!(), throwsFormatException);
      expect(released.last, oversized.path);
      expect(oversized.existsSync(), isFalse);
      expect(await session.pickSharedSourceText!(), isNull);
    } finally {
      uiOnly.close();
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
