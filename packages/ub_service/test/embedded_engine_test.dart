@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/embedded_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('embedded startup refuses missing authority without creating an installation', () async {
    final parent = Directory.systemTemp.createTempSync('ub-embedded-missing-');
    final path = '${parent.path}/absent';
    try {
      await expectLater(
        EmbeddedSqliteEngine.start(path),
        throwsA(
          isA<EmbeddedEngineException>().having(
            (e) => e.toString(),
            'redacted diagnostic',
            'EmbeddedEngineException(unavailable)',
          ),
        ),
      );
      expect(Directory(path).existsSync(), isFalse);
    } finally {
      parent.deleteSync(recursive: true);
    }
  });

  test('embedded service authenticates, retains drafts across worker restart and releases ownership', () async {
    final root = Directory.systemTemp.createTempSync('ub-embedded-');
    final catalog = SqliteInstallationStore.create(root.path);
    final profile = InstallationAuthority(catalog).initializeAuthor();
    final instance = catalog.instanceId;
    catalog.close();
    EmbeddedSqliteEngine? engine;
    LoopbackEngineClient? client;
    Future<LoopbackEngineClient> connect() => LoopbackEngineClient.connectLocal(
      endpoint: engine!.endpoint,
      root: root.path,
      profile: profile,
      clientName: 'Embedded application test',
    );
    try {
      engine = await EmbeddedSqliteEngine.start(root.path);
      expect(engine.isClosed, isFalse);
      expect(File('${root.path}/engine.sock').existsSync(), isFalse);
      client = await connect();
      expect(client.welcome.principal, profile);
      await expectLater(
        EmbeddedSqliteEngine.start(root.path),
        throwsA(isA<EmbeddedEngineException>()),
      );
      final created = WireFields(
        await client.call(
          const CreateUniverseEngineRequest(
            name: 'Mobile local',
            start: GregorianUniverseStart('2042-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final universe = UniverseId.parse(created.string('universe_id')),
          continuity = ContinuityId.parse(created.string('continuity_id'));
      final content = DraftContent(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: RecordId.parse(created.string('context_id')),
        operations: [],
        rationale: '未完 😀\r\n',
      );
      final draft = SavedDraft.fromWire(
        await client.call(
          SaveDraftEngineRequest(
            universe: const Selector('Mobile local'),
            continuityId: continuity,
            expectedVersion: BigInt.zero,
            content: content,
          ),
        ),
      );
      await client.close();
      client = null;
      await Future.wait([engine.close(), engine.close()]);
      await engine.done;
      expect(engine.isClosed, isTrue);
      expect(engine.failure, isNull);
      expect(File('${root.path}/engine-http.json').existsSync(), isFalse);
      engine = await EmbeddedSqliteEngine.start(root.path);
      client = await connect();
      final loaded = SavedDraft.fromWire(
        await client.call(
          LoadDraftEngineRequest(
            universe: const Selector('Mobile local'),
            continuityId: continuity,
          ),
        ),
      );
      expect(loaded.toWire().toText(), draft.toWire().toText());
      final library = WireFields(
        await client.call(const StatusEngineRequest()),
        {
          'instance_id',
          'backend',
          'universes',
          'service_instance',
          'principal',
          'author',
          'canonical_commit',
          'max_requests_per_principal',
          'universe_queue_capacity',
        },
      );
      expect(library.string('instance_id'), instance.value);
      expect(library.string('backend'), 'sqlite');
      expect(
        library.array('universes').single.toText(),
        contains(universe.value),
      );
      // The existing service shutdown command ends the worker as well.
      await client.call(const ShutdownEngineRequest());
      await engine.done;
      expect(engine.isClosed, isTrue);
      await engine.close();
    } finally {
      await client?.close();
      await engine?.close();
      root.deleteSync(recursive: true);
    }
  });
}
