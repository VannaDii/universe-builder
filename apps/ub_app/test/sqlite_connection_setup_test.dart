@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_settings.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  test('explicit SQLite return restores its author, library and pending form without unlocking retained PostgreSQL settings', () async {
    final root = Directory('/tmp').createTempSync('ub-app-sqlite-setup-');
    final store = SqliteInstallationStore.create(root.path);
    final instance = store.instanceId;
    final author = InstallationAuthority(store).initializeAuthor();
    store.close();
    final settings = LocalSettingsStore.create(
      '${root.path}/settings.sqlite',
      installationId: 'Disposable backend settings',
    );
    final retained = EncryptedPostgresEndpoint(
      keyReference: 'ub-installation-key-v1-${'0' * 32}',
      ciphertext: [1, 2, 3],
      nonce: List.filled(12, 1),
      tag: List.filled(16, 2),
    );
    settings.save(usePostgres: true, endpoint: retained);
    settings.close();
    final device = DeviceConnection([
      '--installation',
      root.path,
      '--profile',
      author.value,
      '--engine=/nonexistent/universe-engine',
    ]);
    LocalSqliteEngineServer? server;
    AppSession? session;
    try {
      server = await LocalSqliteEngineServer.start(
        root.path,
        compatibilitySocket: false,
      );
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Local continuity',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
      );
      final form = UnfinishedWorldForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: RecordId.parse(created.string('context_id')),
        record: RecordId.generate(),
        selector: 'Unfinished local world',
        settingType: 'Autobiography setting',
        rationale: 'Retain notes and citations after switching.',
      );
      await session.saveWorldForm(scope, form, BigInt.zero);
      await session.call(const ShutdownEngineRequest());
      await session.close();
      session = null;
      await server.done;
      await server.close();
      server = null;
      final other = ProfileId.generate();
      device.profile = other.value;
      DeviceProfileStore.write(root.path, other);
      final tested = await device.testSqlite();
      expect(tested.instance, instance);
      expect(tested.profile, author);
      expect(DeviceProfileStore.read(root.path), other);
      final before = LocalSettingsStore.openExisting(
        '${root.path}/settings.sqlite',
      );
      try {
        expect(before.readBackendSelection(), isTrue);
      } finally {
        before.close();
      }
      await expectLater(
        device.saveSqlite(
          TestedSqliteConnection(
            instance: OperationId.generate(),
            profile: author,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await device.saveSqlite(tested);
      expect(DeviceProfileStore.read(root.path), author);
      final saved = LocalSettingsStore.openExisting(
        '${root.path}/settings.sqlite',
      );
      try {
        expect(saved.readBackendSelection(), isFalse);
        expect(saved.read().endpoint!.ciphertext, retained.ciphertext);
        expect(saved.read().endpoint!.keyReference, retained.keyReference);
      } finally {
        saved.close();
      }
      server = await LocalSqliteEngineServer.start(
        root.path,
        compatibilitySocket: false,
      );
      session = await device.connect();
      final library = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      expect(library.instance, instance);
      expect(library.backend, ConnectedBackend.sqlite);
      expect(library.universes.single.name, 'Local continuity');
      expect(session.principal, author);
      expect(
        (await session.loadWorldForm(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      await session.call(const ShutdownEngineRequest());
      await session.close();
      session = null;
      await server.done;
      await server.close();
      server = null;
      File('${root.path}/profiles/${author.value}.sqlite').deleteSync();
      await expectLater(
        device.testSqlite(),
        throwsA(isA<ProfileCredentialException>()),
      );
      expect(DeviceProfileStore.read(root.path), author);
    } finally {
      try {
        await session?.close();
      } finally {
        try {
          await server?.close();
        } finally {
          root.deleteSync(recursive: true);
        }
      }
    }
  });
}
