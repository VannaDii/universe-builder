@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('embedded app connection initializes once and recovers private fields after session restart', () async {
    final temporary = Directory.systemTemp.createTempSync('ub-embedded-app-');
    final root = '${temporary.path}/installation';
    var pathRequests = 0;
    String? selectedImage;
    final released = <String>[];
    final device = DeviceConnection(
      ['--engine=/nonexistent/helper'],
      embeddedLocal: true,
      pickImagePath: () async => selectedImage,
      releaseImagePath: (source) async {
        released.add(source);
        File(source).deleteSync();
      },
      installationRoot: () async {
        pathRequests++;
        return root;
      },
    );
    expect(device.available, isTrue);
    expect(device.supportsLocalSettings, isFalse);
    AppSession? session;
    try {
      session = await device.connect();
      expect(session.author, isTrue);
      expect(pathRequests, 1);
      final principal = session.principal;
      final initial = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      expect(initial.backend, ConnectedBackend.sqlite);
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'On device',
            start: GregorianUniverseStart('2042-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      expect(await session.pickImage!(const Selector('On device')), isNull);
      expect(released, isEmpty);
      final image = File('${temporary.path}/portrait.png')
        ..writeAsBytesSync(
          base64.decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
          ),
        );
      selectedImage = image.path;
      final staged = (await session.pickImage!(const Selector('On device')))!;
      expect(staged.asset.originalName, 'portrait.png');
      expect(staged.asset.width, 2);
      expect(image.existsSync(), isFalse);
      expect(released, [image.path]);
      final invalid = File('${temporary.path}/invalid.png')
        ..writeAsStringSync('not an image');
      selectedImage = invalid.path;
      await expectLater(
        session.pickImage!(const Selector('On device')),
        throwsA(isA<ProtocolError>()),
      );
      expect(invalid.existsSync(), isFalse);
      expect(released, [image.path, invalid.path]);
      final scope = EditorFormScope(
        instance: initial.instance,
        profile: principal,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      final input = UnfinishedSecretForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: 'unfinished mobile secret',
        concealment: '私的 😀\r\n',
        hasConcealment: true,
      );
      await session.saveSecretForm(scope, input, BigInt.zero);
      await session.close();
      session = null;
      expect(File('$root/engine-http.json').existsSync(), isFalse);
      // A fresh app-side connection has no retained profile argument or helper.
      final restarted = DeviceConnection([
        '--installation',
        root,
      ], embeddedLocal: true);
      session = await restarted.connect();
      expect(session.principal, principal);
      final library = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      expect(library.instance, initial.instance);
      expect(library.universes.single.id, scope.universe);
      expect(
        (await session.loadSecretForm(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await session.loadSecretForm(scope))!.form.readerDisclosed,
        isNull,
      );
    } finally {
      await session?.close();
      temporary.deleteSync(recursive: true);
    }
  });
}
