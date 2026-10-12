@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL durable source move quiescence',
    () {
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late ProfileId authorId, writerId;
      final universes = <UniverseId>[];
      const secret = 'disposable-move-profile';
      Endpoint endpoint() => Endpoint(
        host: '127.0.0.1',
        port: port!,
        database: 'ub_disposable',
        username: 'postgres',
      );
      const settings = ConnectionSettings(sslMode: SslMode.disable);
      EngineHello hello(ProfileId id) => EngineHello(
        protocolVersion: protocolVersion,
        profileId: id,
        credential: const Credential(secret),
        clientName: 'Disposable source move',
      );
      String text(CanonicalValue v, String key) =>
          wireString(Map.fromEntries((v as CanonicalObject).fields)[key]!);
      Future<CanonicalValue> create(
        NativePostgresConnection author,
        String name,
      ) async {
        final result = await author.execute(
          CreateUniverseEngineRequest(
            name: name,
            start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        );
        universes.add(UniverseId.parse(text(result, 'universe_id')));
        return result;
      }

      Future<void> quiesce(
        ProfileId actor,
        UniverseId universe,
        OperationId operation,
        OperationId target,
      ) => store.transaction((s) async {
        final authority = PostgresServiceAuthority(s.authority);
        final principal = await authority.authenticate(
          profile: actor,
          credential: const Credential(secret),
        );
        await authority.quiesceUniverseForMove(
          principal,
          universe: universe,
          operation: operation,
          targetInstance: target,
        );
      });
      setUp(() async {
        universes.clear();
        observer = await Connection.open(endpoint(), settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: settings,
        );
        authorId = ProfileId.generate();
        writerId = ProfileId.generate();
        await store.transaction((s) async {
          final hash = sha256.convert(utf8.encode(secret)).toString();
          await s.authority.enroll(id: authorId, credentialHash: hash);
          await s.authority.enroll(
            id: writerId,
            credentialHash: hash,
            actor: authorId,
          );
        });
        runtime = NativePostgresRuntime(store: store);
      });
      tearDown(() async {
        await runtime.close();
        await store.close();
        try {
          for (final universe in universes) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
            );
          }
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
        }
      });
      test('committed source guard blocks connected author and peer while retaining original grants aliases and data through restart', () async {
        var author = await runtime.connect(hello(authorId));
        final source = await create(author, 'Move source');
        final other = await create(author, 'Other universe');
        final universe = UniverseId.parse(text(source, 'universe_id'));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Renamed source',
          ),
        );
        final peerStore = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        final peerRuntime = NativePostgresRuntime(store: peerStore);
        try {
          final peer = await peerRuntime.connect(hello(authorId));
          final writer = await peerRuntime.connect(hello(writerId));
          expect(
            textArray(
              await writer.execute(const StatusEngineRequest()),
              'universes',
            ),
            hasLength(1),
          );
          SaveDraftEngineRequest save(CanonicalValue row, String name) =>
              SaveDraftEngineRequest(
                universe: Selector(name),
                continuityId: ContinuityId.parse(text(row, 'continuity_id')),
                expectedVersion: BigInt.zero,
                content: DraftContent(
                  baseRevision: RevisionId.parse(text(row, 'revision')),
                  representedContext: RecordId.parse(text(row, 'context_id')),
                  operations: const [],
                  rationale: 'Exact retained draft é😀',
                  proposal: null,
                ),
              );
          final request = save(source, 'Move source');
          final draft = await peer.execute(request);
          final operation = OperationId.generate(),
              target = OperationId.generate();
          await quiesce(authorId, universe, operation, target);
          await quiesce(authorId, universe, operation, target);
          for (final connection in [author, peer]) {
            await expectLater(
              connection.execute(request),
              throwsA(isA<NotFoundOrNotAccessibleError>()),
            );
          }
          final hidden = textArray(
            await writer.execute(const StatusEngineRequest()),
            'universes',
          );
          expect(hidden, isEmpty);
          await expectLater(
            quiesce(
              authorId,
              UniverseId.parse(text(other, 'universe_id')),
              operation,
              target,
            ),
            throwsFormatException,
          );
          await author.execute(save(other, 'Other universe'));
          final control = postgresAuthorityNamespace(store.instanceId);
          expect(
            (await observer.execute(
              'SELECT count(*) FROM $control.catalog WHERE id=\$1',
              parameters: [universe.value],
            )).single.single,
            1,
          );
          expect(
            (await observer.execute(
              'SELECT count(*) FROM $control.aliases WHERE universe=\$1',
              parameters: [universe.value],
            )).single.single,
            2,
          );
          expect(
            (await observer.execute(
              'SELECT count(*) FROM $control.grants WHERE universe=\$1',
              parameters: [universe.value],
            )).single.single,
            1,
          );
          expect(
            (await observer.execute(
              "SELECT count(*) FROM $control.audit WHERE action='quiesce_move'",
            )).single.single,
            1,
          );
          await store.transaction((s) async {
            expect(
              await s
                  .kernel(universe)
                  .journal
                  .head(ContinuityId.parse(text(source, 'continuity_id'))),
              RevisionId.parse(text(source, 'revision')),
            );
            final keys = await s
                .workflows(universe)
                .keys('draft:${authorId.value}:');
            expect(keys, hasLength(1));
            expect(
              (await s.workflows(universe).get(keys.single))!.toText(),
              draft.toText(),
            );
            await s.verifyUniverse(universe, complete: true);
          });
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          author = await runtime.connect(hello(authorId));
          await expectLater(
            author.execute(request),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          await expectLater(
            quiesce(authorId, universe, OperationId.generate(), target),
            throwsFormatException,
          );
          await expectLater(
            quiesce(authorId, universe, operation, OperationId.generate()),
            throwsFormatException,
          );
        } finally {
          await peerRuntime.close();
          await peerStore.close();
        }
      });
      test('writer self-target and rollback cannot suspend a source', () async {
        final author = await runtime.connect(hello(authorId));
        final source = await create(author, 'Move source');
        final universe = UniverseId.parse(text(source, 'universe_id'));
        final operation = OperationId.generate(),
            target = OperationId.generate();
        await expectLater(
          quiesce(writerId, universe, operation, target),
          throwsA(isA<InstallationException>()),
        );
        await expectLater(
          quiesce(authorId, universe, operation, store.instanceId),
          throwsFormatException,
        );
        await expectLater(
          store.transaction((s) async {
            await s.authority.quiesceUniverseForMove(
              actor: authorId,
              universe: universe,
              operation: operation,
              targetInstance: target,
            );
            throw StateError('Disposable move rollback');
          }),
          throwsStateError,
        );
        await author.execute(
          const LibraryEngineRequest(universe: Selector('Move source')),
        );
        expect(
          (await observer.execute(
            'SELECT count(*) FROM ${postgresAuthorityNamespace(store.instanceId)}.move_quiescence',
          )).single.single,
          0,
        );
      });
      test('missing move layout refuses existing installation without recreating it', () async {
        await runtime.close();
        await store.close();
        await observer.execute(
          'DROP TABLE ${postgresAuthorityNamespace(store.instanceId)}.move_quiescence',
        );
        await expectLater(
          PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          ),
          throwsA(isA<InstallationException>()),
        );
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}

List<CanonicalValue> textArray(CanonicalValue value, String key) =>
    (Map.fromEntries((value as CanonicalObject).fields)[key] as CanonicalArray)
        .items;
