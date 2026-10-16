@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/universe_purge.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('purge requires current impact and exact confirmation, retaining other universes and external backups', () async {
    final root = Directory('/tmp').createTempSync('ub-purge-workflow-');
    final device = DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true);
    AppSession? session;
    try {
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Disposable 記憶 😀',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      await session.call(
        const CreateUniverseEngineRequest(
          realWorld: false,
          name: 'Retained universe',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      final universe = LibraryEntry(
        UniverseId.parse(created.string('universe_id')),
        created.string('name'),
      );
      final backup = File('${root.path}/external-backup.sqlite');
      await session.call(
        BackupEngineRequest(
          universe: Selector(universe.name),
          destination: backup.path,
        ),
      );
      final backupLength = backup.lengthSync();
      final preview = await previewUniversePurge(session, universe);
      expect(preview.universe, universe.id);
      expect(preview.continuities, 1);
      expect(preview.revisions, greaterThan(BigInt.zero));
      expect(preview.versions, greaterThan(BigInt.zero));
      expect(preview.scope, contains('all continuities'));
      expect(preview.retained, contains('external backups'));
      await expectLater(
        purgeUniverse(session, universe, preview, 'PURGE disposable'),
        throwsA(isA<ProtocolError>()),
      );
      await session.call(
        SaveDraftEngineRequest(
          universe: Selector(universe.name),
          continuityId: ContinuityId.parse(created.string('continuity_id')),
          expectedVersion: BigInt.zero,
          content: DraftContent(
            baseRevision: RevisionId.parse(created.string('revision')),
            representedContext: RecordId.parse(created.string('context_id')),
            operations: [],
            rationale: 'Retained unfinished draft changes the purge impact.',
          ),
        ),
      );
      await expectLater(
        purgeUniverse(session, universe, preview, 'PURGE ${universe.name}'),
        throwsA(isA<ProtocolError>()),
      );
      final updated = await previewUniversePurge(session, universe);
      expect(updated.digest, isNot(preview.digest));
      expect(updated.workflows, greaterThan(preview.workflows));
      final enrolled = WireFields(
        await session.call(const EnrollEngineRequest()),
        {'profile_id'},
      );
      final reader = ProfileId.parse(enrolled.string('profile_id'));
      await session.call(
        GrantEngineRequest(
          grant: GrantSpec(
            profileId: reader,
            universeId: universe.id,
            propose: false,
            edit: false,
            protected: false,
          ),
        ),
      );
      await session.close();
      session = await DeviceConnection([
        '--installation',
        root.path,
        '--profile',
        reader.value,
      ], embeddedLocal: true).connect();
      expect(session.author, isFalse);
      await expectLater(
        previewUniversePurge(session, universe),
        throwsA(isA<ProtocolError>()),
      );
      await expectLater(
        purgeUniverse(session, universe, updated, 'PURGE ${universe.name}'),
        throwsA(isA<ProtocolError>()),
      );
      await session.close();
      session = await device.connect();
      final current = await previewUniversePurge(session, universe);
      await purgeUniverse(session, universe, current, 'PURGE ${universe.name}');
      final catalog = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      expect(catalog.universes.map((row) => row.name), ['Retained universe']);
      expect(backup.existsSync(), isTrue);
      expect(backup.lengthSync(), backupLength);
      await session.close();
      session = await device.connect();
      expect(
        InstanceLibrary.fromWire(
          await session.call(const StatusEngineRequest()),
        ).universes.map((row) => row.name),
        ['Retained universe'],
      );
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
