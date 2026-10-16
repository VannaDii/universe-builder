@TestOn('vm')
library;

import 'helpers/universe_creation.dart' as creation;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/sqlite.dart' as local;
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL portable backup and restore',
    () {
      late Directory directory;
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late ProfileId authorId, writerId;
      late UniverseId universe;
      late ContinuityId continuity, branch;
      late RevisionId genesis, branchHead;
      late String backup;
      const secret = 'disposable-backup-profile';
      const sourceText = '\uFEFFOriginal research é😀\u0000\r\n';
      final sourceDigest = sha256.convert(utf8.encode(sourceText)).toString();
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
        credential: Credential(secret),
        clientName: 'Disposable backup client',
      );
      Map<String, CanonicalValue> fields(CanonicalValue value) =>
          Map.fromEntries((value as CanonicalObject).fields);
      String text(CanonicalValue value, String name) =>
          wireString(fields(value)[name]!);
      String control() => postgresAuthorityNamespace(store.instanceId);
      Future<bool> exists() async =>
          (await observer.execute(
                'SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname=\$1)',
                parameters: ['ub_${universe.value}'],
              )).single.single
              as bool;
      Future<CanonicalValue> restore(
        NativePostgresConnection connection, {
        String name = 'Restored research',
      }) =>
          connection.execute(RestoreEngineRequest(source: backup, name: name));
      setUp(() async {
        directory = Directory.systemTemp.createTempSync(
          'universe-builder-backup-',
        );
        universe = UniverseId.generate();
        continuity = ContinuityId.generate();
        branch = ContinuityId.generate();
        backup = '${directory.path}/original.sqlite';
        final source = local.OwnedSqliteDatabase.create(
          '${directory.path}/source.sqlite',
        );
        try {
          source.database.execute('BEGIN IMMEDIATE');
          final journal = local.SqliteJournal(source.database, universe);
          final principal = PrincipalId.generate();
          genesis = journal.initialize(
            'Original research',
            continuity,
            principal,
          );
          branchHead = journal.branch(branch, continuity, genesis, principal);
          final workflow = local.WorkflowStorage(source.database);
          workflow.put(
            'cursor:original',
            CanonicalValue.parseJson(
              '{"binding":"exact original binding","offset":0}',
            ),
          );
          workflow.put('source:$sourceDigest', CanonicalString(sourceText));
          source.database.execute('COMMIT');
          creation.addFixtureRoot(source);
          genesis = journal.head(continuity);
          branchHead = journal.head(branch);
          source.backup(backup);
        } finally {
          source.close();
        }
        observer = await Connection.open(endpoint(), settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: settings,
        );
        authorId = ProfileId.generate();
        writerId = ProfileId.generate();
        await store.transaction((session) async {
          final hash = sha256.convert(utf8.encode(secret)).toString();
          await session.authority.enroll(id: authorId, credentialHash: hash);
          await session.authority.enroll(
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
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
          );
          await observer.execute('DROP SCHEMA IF EXISTS ${control()} CASCADE');
        } finally {
          await observer.close();
          directory.deleteSync(recursive: true);
        }
      });

      test('SQLite backup restores into PostgreSQL with exact branch source and historical workflow across restart', () async {
        var author = await runtime.connect(hello(authorId));
        final original = File(backup).readAsBytesSync();
        final result = await restore(author);
        expect(text(result, 'universe_id'), universe.value);
        expect((fields(result)['restored'] as CanonicalBool).value, isTrue);
        await store.transaction((session) async {
          await session.verifyUniverse(universe, complete: true);
          expect(await session.kernel(universe).journal.heads(), {
            continuity: genesis,
            branch: branchHead,
          });
          expect(
            await session.workflows(universe).get('cursor:original'),
            isNull,
          );
          expect(
            (await session.workflows(universe).evidence('source:$sourceDigest')
                    as CanonicalString)
                .value,
            sourceText,
          );
        });
        final snapshot = '${directory.path}/postgres-backup.sqlite';
        final backed = await author.execute(
          BackupEngineRequest(
            universe: const Selector('Restored research'),
            destination: snapshot,
          ),
        );
        expect(text(backed, 'backup'), snapshot);
        expect(text(backed, 'universe_id'), universe.value);
        expect((fields(backed)['verified'] as CanonicalBool).value, isTrue);
        final carrier = local.OwnedSqliteDatabase.openExisting(snapshot);
        try {
          expect(local.SqliteJournal(carrier.database, universe).heads(), {
            continuity: genesis,
            branch: branchHead,
          });
          expect(
            (local.WorkflowStorage(
              carrier.database,
            ).evidence('source:$sourceDigest') as CanonicalString).value,
            sourceText,
          );
          expect(
            carrier.database.select(
              "SELECT name FROM sqlite_master WHERE name='archive_integrity'",
            ),
            isEmpty,
          );
        } finally {
          carrier.close();
        }
        final instance = store.instanceId;
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(store.instanceId, instance);
        await author.execute(
          const LibraryEngineRequest(universe: Selector('Restored research')),
        );
        expect(File(backup).readAsBytesSync(), orderedEquals(original));
      });

      test('writers are denied before backup or restore IO and backup never overwrites an existing destination', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            const RestoreEngineRequest(
              source: '/absent/disposable.sqlite',
              name: 'Denied',
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await restore(author);
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
        final destination = '${directory.path}/private-backup.sqlite';
        final request = BackupEngineRequest(
          universe: const Selector('Restored research'),
          destination: destination,
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(File(destination).existsSync(), isFalse);
        await author.execute(request);
        final before = File(destination).readAsBytesSync();
        await expectLater(
          author.execute(request),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(destination).readAsBytesSync(), orderedEquals(before));
        expect(
          directory.listSync().where(
            (entry) => entry.uri.pathSegments.any(
              (part) =>
                  part.startsWith('.postgres-export-') ||
                  part.startsWith('.universe-backup-'),
            ),
          ),
          isEmpty,
        );
      });

      test('restore rejects identity conflicts and untrusted source schemas while preserving both originals', () async {
        final author = await runtime.connect(hello(authorId));
        final original = File(backup).readAsBytesSync();
        await restore(author);
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Renamed research',
          ),
        );
        await expectLater(
          restore(author, name: 'Other name'),
          throwsA(isA<NameUnavailableError>()),
        );
        final bad = '${directory.path}/untrusted.sqlite';
        final source = local.OwnedSqliteDatabase.create(bad);
        try {
          source.database.execute('CREATE TABLE untrusted_extra(data TEXT)');
        } finally {
          source.close();
        }
        await expectLater(
          author.execute(RestoreEngineRequest(source: bad, name: 'Untrusted')),
          throwsFormatException,
        );
        expect(await exists(), isTrue);
        expect(File(backup).readAsBytesSync(), orderedEquals(original));
        expect(
          (await store.transaction(
            (session) =>
                session.authority.catalog(authorId, epochSeconds: BigInt.zero),
          )).single.name,
          'Renamed research',
        );
      });

      test('registration failure and interruption roll back copied namespace and allow restore retry', () async {
        final author = await runtime.connect(hello(authorId));
        final original = File(backup).readAsBytesSync();
        await observer.execute(
          'CREATE FUNCTION ${control()}.reject_restore() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'Disposable restore failure\'; END \$\$',
        );
        await observer.execute(
          'CREATE TRIGGER reject_restore BEFORE INSERT ON ${control()}.catalog FOR EACH ROW EXECUTE FUNCTION ${control()}.reject_restore()',
        );
        await expectLater(restore(author), throwsA(isA<ServerException>()));
        expect(await exists(), isFalse);
        await observer.execute(
          'DROP TRIGGER reject_restore ON ${control()}.catalog',
        );
        await observer.execute('DROP FUNCTION ${control()}.reject_restore()');
        await expectLater(
          store.transaction((session) async {
            await session.restoreUniverse(
              actor: authorId,
              source: backup,
              name: 'Restored research',
            );
            throw StateError('disposable interruption before commit');
          }),
          throwsStateError,
        );
        expect(await exists(), isFalse);
        expect(
          await store.transaction(
            (session) =>
                session.authority.catalog(authorId, epochSeconds: BigInt.zero),
          ),
          isEmpty,
        );
        await restore(author);
        await store.transaction(
          (session) => session.verifyUniverse(universe, complete: true),
        );
        expect(File(backup).readAsBytesSync(), orderedEquals(original));
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}
