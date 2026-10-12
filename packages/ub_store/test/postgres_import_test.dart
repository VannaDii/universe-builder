@TestOn('vm')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/sqlite.dart' as local;
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL archive admission',
    () {
      late Directory directory;
      late local.OwnedSqliteDatabase source;
      late local.VerifiedLogicalArchive archive;
      late PostgresInstallationStore store;
      late Connection observer;
      late UniverseId universe;
      late ContinuityId continuity, branch;
      late RevisionId genesis, branchHead;
      late ProfileId author, writer;
      final admitted = <UniverseId>[];
      const cursor = 'cursor:retained';
      final evidence = CanonicalValue.parseJson(
        '{"binding":"é😀 exact","offset":0}',
      );
      setUp(() async {
        admitted.clear();
        directory = Directory.systemTemp.createTempSync(
          'universe-builder-import-',
        );
        source = local.OwnedSqliteDatabase.create(
          '${directory.path}/source.sqlite',
        );
        universe = UniverseId.generate();
        continuity = ContinuityId.generate();
        branch = ContinuityId.generate();
        source.database.execute('BEGIN IMMEDIATE');
        final journal = local.SqliteJournal(source.database, universe);
        final principal = PrincipalId.generate();
        genesis = journal.initialize('Transfer é😀', continuity, principal);
        branchHead = journal.branch(branch, continuity, genesis, principal);
        local.WorkflowStorage(source.database).put(cursor, evidence);
        source.database.execute('COMMIT');
        source.exportCompleteHistory('${directory.path}/archive.sqlite');
        archive = local.OwnedSqliteDatabase.stageLogicalArchive(
          '${directory.path}/archive.sqlite',
          directory.path,
        );
        final endpoint = Endpoint(
          host: '127.0.0.1',
          port: port!,
          database: 'ub_disposable',
          username: 'postgres',
        );
        const settings = ConnectionSettings(sslMode: SslMode.disable);
        observer = await Connection.open(endpoint, settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint,
          settings: settings,
        );
        author = ProfileId.generate();
        writer = ProfileId.generate();
        await store.transaction((session) async {
          await session.authority.enroll(id: author, credentialHash: '0' * 64);
          await session.authority.enroll(
            id: writer,
            credentialHash: '1' * 64,
            actor: author,
          );
        });
      });
      tearDown(() async {
        await store.close();
        try {
          for (final id in admitted) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(id)} CASCADE',
            );
          }
          await observer.execute(
            'DROP SCHEMA ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
          archive.close();
          source.close();
          directory.deleteSync(recursive: true);
        }
      });
      Future<UniverseId> import({
        ProfileId? actor,
        String name = 'Imported é😀',
        UniverseId? clone,
      }) => store.transaction(
        (session) => session.importUniverse(
          actor: actor ?? author,
          archive: archive,
          scratch: directory.path,
          name: name,
          clone: clone,
        ),
      );
      Future<bool> exists(UniverseId id) async =>
          (await observer.execute(
                'SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname=\$1)',
                parameters: ['ub_${id.value}'],
              )).single.single
              as bool;

      test(
        'canon-only transfer reconstructs an identity-preserving universe',
        () async {
          final path = '${directory.path}/canon.sqlite';
          source.exportLogical(path);
          final canon = local.OwnedSqliteDatabase.stageLogicalArchive(
            path,
            directory.path,
          );
          try {
            admitted.add(universe);
            await store.transaction((session) async {
              expect(
                await session.importUniverse(
                  actor: author,
                  archive: canon,
                  scratch: directory.path,
                  name: 'Canon-only',
                ),
                universe,
              );
              await session.verifyUniverse(universe, complete: true);
              expect(
                await session.workflows(universe).evidence(cursor),
                isNull,
              );
              expect(
                await session
                    .workflows(universe)
                    .keys('logical-import-origin:'),
                hasLength(1),
              );
              expect(
                await session.kernel(universe).journal.heads(),
                isNotEmpty,
              );
            });
            expect(local.SqliteJournal(source.database, universe).heads(), {
              continuity: genesis,
              branch: branchHead,
            });
          } finally {
            canon.close();
          }
        },
      );

      test('retained branch history and inactive cursor survive restore and reopen', () async {
        admitted.add(universe);
        expect(await import(), universe);
        await store.transaction((session) async {
          await session.verifyUniverse(universe, complete: true);
          expect(await session.kernel(universe).journal.heads(), {
            continuity: genesis,
            branch: branchHead,
          });
          expect(await session.workflows(universe).get(cursor), isNull);
          expect(
            (await session.workflows(universe).evidence(cursor))!.toText(),
            evidence.toText(),
          );
          expect(
            (await session.authority.catalog(
              author,
              epochSeconds: BigInt.zero,
            )).single.name,
            'Imported é😀',
          );
        });
        final instance = store.instanceId;
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        expect(store.instanceId, instance);
        await store.transaction(
          (session) => session.verifyUniverse(universe, complete: true),
        );
        expect(
          local.SqliteJournal(source.database, universe).head(continuity),
          genesis,
        );
      });

      test('writer denial has no schema or scratch side effects', () async {
        final before = directory.listSync().map((f) => f.path).toSet();
        await expectLater(
          import(actor: writer),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.denied,
            ),
          ),
        );
        expect(await exists(universe), isFalse);
        expect(directory.listSync().map((f) => f.path).toSet(), before);
      });

      test('catalog conflict rolls back copied namespace even when caught by caller', () async {
        final other = UniverseId.generate();
        admitted.add(other);
        await import(clone: other, name: 'Occupied name');
        await store.transaction((session) async {
          await expectLater(
            session.importUniverse(
              actor: author,
              archive: archive,
              scratch: directory.path,
              name: 'Occupied name',
            ),
            throwsA(
              isA<InstallationException>().having(
                (e) => e.failure,
                'failure',
                InstallationFailure.denied,
              ),
            ),
          );
          expect(
            (await session.authority.catalog(
              author,
              epochSeconds: BigInt.zero,
            )).map((v) => v.universeId),
            [other],
          );
        });
        expect(await exists(universe), isFalse);
        admitted.add(universe);
        expect(await import(name: 'Retry after rollback'), universe);
      });

      test(
        'outer rollback leaves original archive and no registered target',
        () async {
          final bytes = File('${directory.path}/archive.sqlite')
              .readAsBytesSync();
          await expectLater(
            store.transaction((session) async {
              await session.importUniverse(
                actor: author,
                archive: archive,
                scratch: directory.path,
                name: 'Interrupted import',
              );
              throw StateError('disposable interruption');
            }),
            throwsStateError,
          );
          expect(await exists(universe), isFalse);
          expect(
            File('${directory.path}/archive.sqlite').readAsBytesSync(),
            orderedEquals(bytes),
          );
          expect(
            await store.transaction(
              (session) =>
                  session.authority.catalog(author, epochSeconds: BigInt.zero),
            ),
            isEmpty,
          );
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}
