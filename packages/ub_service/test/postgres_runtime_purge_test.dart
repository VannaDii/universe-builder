@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL exact purge dispatch',
    () {
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late Directory directory;
      late ProfileId authorId, writerId;
      final universes = <UniverseId>[];
      const secret = 'disposable-purge-profile';
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
        clientName: 'Disposable purge client',
      );
      Map<String, CanonicalValue> fields(CanonicalValue value) =>
          Map.fromEntries((value as CanonicalObject).fields);
      String text(CanonicalValue value, String name) =>
          wireString(fields(value)[name]!);
      String control() => postgresAuthorityNamespace(store.instanceId);
      Future<bool> exists(UniverseId id) async =>
          (await observer.execute(
                'SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname=\$1)',
                parameters: ['ub_${id.value}'],
              )).single.single
              as bool;
      Future<UniverseId> create(
        NativePostgresConnection author,
        String name,
      ) async {
        final result = await author.execute(
          CreateUniverseEngineRequest(
            realWorld: false,
            name: name,
            start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        );
        final universe = UniverseId.parse(text(result, 'universe_id'));
        universes.add(universe);
        return universe;
      }

      Future<CanonicalValue> preview(
        NativePostgresConnection author,
        String name,
      ) => author.execute(PreviewPurgeEngineRequest(universe: Selector(name)));
      Future<CanonicalValue> purge(
        NativePostgresConnection author,
        String name,
        CanonicalValue reviewed, {
        String? confirmation,
      }) => author.execute(
        PurgeEngineRequest(
          universe: Selector(name),
          digest: text(reviewed, 'digest'),
          confirmation: confirmation ?? 'PURGE $name',
        ),
      );
      setUp(() async {
        universes.clear();
        directory = Directory.systemTemp.createTempSync(
          'universe-builder-purge-',
        );
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
          for (final universe in universes) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
            );
          }
          await observer.execute('DROP SCHEMA IF EXISTS ${control()} CASCADE');
        } finally {
          await observer.close();
          directory.deleteSync(recursive: true);
        }
      });

      test('preview binds heads and retained counts and refuses changed workflow or confirmation', () async {
        final author = await runtime.connect(hello(authorId));
        final universe = await create(author, 'Campaign é😀');
        final reviewed = await preview(author, 'Campaign é😀');
        expect(
          text(reviewed, 'digest'),
          canonicalDigest(fields(reviewed)['impact']!),
        );
        final impact = fields(fields(reviewed)['impact']!);
        expect(wireString(impact['universe_id']!), universe.value);
        expect((impact['heads'] as CanonicalArray).items, hasLength(1));
        expect(impact['revisions']!.toText(), '2');
        expect(impact['record_versions']!.toText(), '4');
        expect(
          (await preview(author, 'Campaign é😀')).toText(),
          reviewed.toText(),
        );
        await expectLater(
          purge(
            author,
            'Campaign é😀',
            reviewed,
            confirmation: 'PURGE campaign é😀',
          ),
          throwsFormatException,
        );
        await author.execute(
          const StageSourceEngineRequest(
            universe: Selector('Campaign é😀'),
            label: 'Notes',
            text: '\uFEFFExact source bytes',
          ),
        );
        final changed = await preview(author, 'Campaign é😀');
        expect(text(changed, 'digest'), isNot(text(reviewed, 'digest')));
        await expectLater(
          purge(author, 'Campaign é😀', reviewed),
          throwsFormatException,
        );
        expect(await exists(universe), isTrue);
        await store.transaction((session) async {
          expect(
            (await session.authority.catalog(
              authorId,
              epochSeconds: BigInt.zero,
            )).single.universeId,
            universe,
          );
          expect(
            (await session.authority.audit(authorId))
                .where((entry) => entry.action == 'purge'),
            isEmpty,
          );
        });
        final head =
            ((impact['heads'] as CanonicalArray).items.single as CanonicalArray)
                .items;
        await author.execute(
          ForkContinuityEngineRequest(
            universe: const Selector('Campaign é😀'),
            name: 'Alternate continuity',
            continuityId: ContinuityId.generate(),
            source: ContinuityId.parse(wireString(head[0])),
            revision: RevisionId.parse(wireString(head[1])),
          ),
        );
        final branched = await preview(author, 'Campaign é😀');
        expect(
          (fields(fields(branched)['impact']!)['heads'] as CanonicalArray)
              .items,
          hasLength(2),
        );
        expect(text(branched, 'digest'), isNot(text(changed, 'digest')));
        await expectLater(
          purge(author, 'Campaign é😀', changed),
          throwsFormatException,
        );
        await purge(author, 'Campaign é😀', branched);
        expect(await exists(universe), isFalse);
      });

      test(
        'fully granted writer cannot preview or execute owner purge',
        () async {
          final author = await runtime.connect(hello(authorId));
          final writer = await runtime.connect(hello(writerId));
          final universe = await create(author, 'Owner universe');
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
          final reviewed = await preview(author, 'Owner universe');
          await expectLater(
            preview(writer, 'Owner universe'),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          await expectLater(
            purge(writer, 'Owner universe', reviewed),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          expect(await exists(universe), isTrue);
          expect(
            (await preview(author, 'Owner universe')).toText(),
            reviewed.toText(),
          );
        },
      );

      test('confirmed purge removes all target aliases grants and schema while retaining archives peer universe and identity', () async {
        var author = await runtime.connect(hello(authorId));
        final universe = await create(author, 'Original name');
        final peer = await create(author, 'Unrelated universe');
        final instance = store.instanceId;
        for (final id in [universe, peer]) {
          await author.execute(
            GrantEngineRequest(
              grant: GrantSpec(
                profileId: writerId,
                universeId: id,
                worlds: [WorldId.generate()],
                propose: true,
                edit: true,
                protected: true,
                limits: GrantLimits(
                  entities: [RecordId.generate()],
                  predicates: [RecordId.generate()],
                  continuities: [ContinuityId.generate()],
                ),
              ),
            ),
          );
        }
        final external = '${directory.path}/external.sqlite';
        await author.execute(
          ExportLogicalEngineRequest(
            universe: const Selector('Original name'),
            destination: external,
            recordIds: [],
            completeHistory: true,
          ),
        );
        final bytes = File(external).readAsBytesSync();
        final importReview = await author.execute(
          PreviewImportEngineRequest(
            source: external,
            name: 'Future clone',
            mode: ImportMode.clone,
          ),
        );
        final previewId = OperationId.parse(text(importReview, 'preview_id'));
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Current name',
          ),
        );
        final reviewed = await preview(author, 'Original name');
        expect(
          text(fields(reviewed)['impact']!, 'retained'),
          contains('reviewed import archives remain'),
        );
        await expectLater(
          purge(author, 'Original name', reviewed),
          throwsFormatException,
        );
        final result = await purge(
          author,
          'Original name',
          reviewed,
          confirmation: 'PURGE Current name',
        );
        expect(text(result, 'purged'), universe.value);
        expect(
          (fields(result)['external_copies_removed'] as CanonicalBool).value,
          isFalse,
        );
        expect(await exists(universe), isFalse);
        expect(await exists(peer), isTrue);
        for (final table in [
          'grant_worlds',
          'grant_entities',
          'grant_predicates',
          'grant_continuities',
          'grants',
          'aliases',
          'catalog',
        ]) {
          final column = table == 'catalog' ? 'id' : 'universe';
          expect(
            (await observer.execute(
              'SELECT count(*) FROM ${control()}.$table WHERE $column=\$1',
              parameters: [universe.value],
            )).single.single,
            0,
          );
        }
        expect(File(external).readAsBytesSync(), orderedEquals(bytes));
        await store.transaction((session) async {
          await session.verifyUniverse(peer, complete: true);
          expect((await session.authority.profiles(authorId)), hasLength(2));
          final audit = (await session.authority.audit(authorId))
              .where((entry) => entry.action == 'purge')
              .single;
          expect(audit.target, universe.value);
          await session.loadImport(
            actor: authorId,
            id: previewId,
            digest: text(importReview, 'digest'),
          );
        });
        for (final name in ['Original name', 'Current name']) {
          await expectLater(
            author.execute(LibraryEngineRequest(universe: Selector(name))),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
        }
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(store.instanceId, instance);
        expect(
          (fields(
                    await author.execute(const StatusEngineRequest()),
                  )['universes']
                  as CanonicalArray)
              .items,
          hasLength(1),
        );
        // Purge removes this installation's target, while the preserved external
        // archive remains eligible for a separately reviewed restore.
        final restoreReview = await author.execute(
          PreviewImportEngineRequest(
            source: external,
            name: 'Restored original',
            mode: ImportMode.restore,
          ),
        );
        await author.execute(
          AcceptImportEngineRequest(
            previewId: OperationId.parse(text(restoreReview, 'preview_id')),
            digest: text(restoreReview, 'digest'),
          ),
        );
        expect(await exists(universe), isTrue);
        await store.transaction(
          (session) => session.verifyUniverse(universe, complete: true),
        );
      });

      test('audit failure and interruption after schema removal roll back all purge effects', () async {
        final author = await runtime.connect(hello(authorId));
        final universe = await create(author, 'Transactional purge');
        final reviewed = await preview(author, 'Transactional purge');
        await observer.execute(
          'CREATE FUNCTION ${control()}.reject_purge() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.action=\'purge\' THEN RAISE EXCEPTION \'Disposable purge failure\'; END IF; RETURN NEW; END \$\$',
        );
        await observer.execute(
          'CREATE TRIGGER reject_purge BEFORE INSERT ON ${control()}.audit FOR EACH ROW EXECUTE FUNCTION ${control()}.reject_purge()',
        );
        await expectLater(
          purge(author, 'Transactional purge', reviewed),
          throwsA(isA<ServerException>()),
        );
        expect(await exists(universe), isTrue);
        expect(
          (await preview(author, 'Transactional purge')).toText(),
          reviewed.toText(),
        );
        await observer.execute(
          'DROP TRIGGER reject_purge ON ${control()}.audit',
        );
        await observer.execute('DROP FUNCTION ${control()}.reject_purge()');
        await expectLater(
          store.transaction((session) async {
            await session.purgeUniverse(
              actor: authorId,
              universe: universe,
              digest: text(reviewed, 'digest'),
            );
            throw StateError('disposable interruption after DROP SCHEMA');
          }),
          throwsStateError,
        );
        expect(await exists(universe), isTrue);
        expect(
          (await preview(author, 'Transactional purge')).toText(),
          reviewed.toText(),
        );
        await store.transaction((session) async {
          expect(
            (await session.authority.catalog(
              authorId,
              epochSeconds: BigInt.zero,
            )).single.universeId,
            universe,
          );
          expect(
            (await session.authority.audit(authorId))
                .where((entry) => entry.action == 'purge'),
            isEmpty,
          );
        });
        await purge(author, 'Transactional purge', reviewed);
        expect(await exists(universe), isFalse);
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}
