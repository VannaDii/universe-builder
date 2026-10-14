@TestOn('vm')
library;

import 'dart:io';

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
    final device = DeviceConnection(
      ['--engine=/nonexistent/helper'],
      embeddedLocal: true,
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
