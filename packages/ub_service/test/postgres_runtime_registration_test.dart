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
    'PostgreSQL namespace registration',
    () {
      late Directory directory;
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late ProfileId authorId, writerId;
      final universes = <UniverseId>[];
      const secret = 'disposable-registration-profile';
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
        clientName: 'Disposable registration client',
      );
      Map<String, CanonicalValue> fields(CanonicalValue value) =>
          Map.fromEntries((value as CanonicalObject).fields);
      String text(CanonicalValue value, String name) =>
          wireString(fields(value)[name]!);
      String control() => postgresAuthorityNamespace(store.instanceId);
      Future<UniverseId> unregistered(NativePostgresConnection author) async {
        final created = await author.execute(
          CreateUniverseEngineRequest(
            realWorld: false,
            name: OperationId.generate().value,
            start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        );
        final universe = UniverseId.parse(text(created, 'universe_id'));
        universes.add(universe);
        await store.transaction((session) async {
          await session
              .workflows(universe)
              .put(
                'cursor:retained',
                CanonicalValue.parseJson(
                  '{"binding":"existing namespace binding","offset":0}',
                ),
              );
          // A disposable existing namespace whose catalog visibility was retired.
          // No universe bytes are dropped; registration must recover these in place.
          await session.authority.retireUniverse(
            actor: authorId,
            universe: universe,
          );
        });
        return universe;
      }

      Future<CanonicalValue> register(
        NativePostgresConnection author,
        UniverseId universe,
        String name,
      ) => author.execute(
        RegisterUniverseEngineRequest(path: 'ub_${universe.value}', name: name),
      );
      setUp(() async {
        universes.clear();
        directory = Directory.systemTemp.createTempSync(
          'universe-builder-registration-',
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

      test('registration recovers an existing namespace in place without deactivating evidence and survives restart', () async {
        var author = await runtime.connect(hello(authorId));
        final universe = await unregistered(author);
        final heads = await store.transaction(
          (session) => session.kernel(universe).journal.heads(),
        );
        final result = await register(author, universe, 'Recovered campaign');
        expect(text(result, 'universe_id'), universe.value);
        await store.transaction((session) async {
          await session.verifyUniverse(universe, complete: true);
          expect(await session.kernel(universe).journal.heads(), heads);
          expect(
            await session.workflows(universe).get('cursor:retained'),
            isNotNull,
          );
        });
        await expectLater(
          register(author, universe, 'Duplicate identity'),
          throwsA(isA<NameUnavailableError>()),
        );
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
          const LibraryEngineRequest(universe: Selector('Recovered campaign')),
        );
      });

      test('registration denies writers file locators malformed namespace IDs and retained name conflicts', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final universe = await unregistered(author);
        await expectLater(
          register(writer, universe, 'Denied'),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        for (final path in [
          '${directory.path}/source.sqlite',
          'ub_unv_invalid;DROP SCHEMA public',
        ]) {
          await expectLater(
            author.execute(
              RegisterUniverseEngineRequest(
                path: path,
                name: 'Invalid locator',
              ),
            ),
            throwsFormatException,
          );
        }
        await register(author, universe, 'Reserved name');
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Current name',
          ),
        );
        final other = await unregistered(author);
        await expectLater(
          register(author, other, 'Reserved name'),
          throwsA(isA<NameUnavailableError>()),
        );
        await store.transaction((session) async {
          expect(
            (await session.authority.catalog(
              authorId,
              epochSeconds: BigInt.zero,
            )).single.universeId,
            universe,
          );
          await session.verifyUniverse(other, complete: true);
        });
      });

      test('registration failure rolls back visibility and recovery while preserving the original namespace for retry', () async {
        final author = await runtime.connect(hello(authorId));
        final universe = await unregistered(author);
        final generation = (await observer.execute(
          'SELECT generation FROM ${postgresUniverseSchema(universe)}.projection_state',
        )).single.single;
        await observer.execute(
          'CREATE FUNCTION ${control()}.reject_register() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.action=\'register\' THEN RAISE EXCEPTION \'Disposable registration failure\'; END IF; RETURN NEW; END \$\$',
        );
        await observer.execute(
          'CREATE TRIGGER reject_register BEFORE INSERT ON ${control()}.audit FOR EACH ROW EXECUTE FUNCTION ${control()}.reject_register()',
        );
        await store.transaction((session) async {
          await expectLater(
            session.registerNamespace(
              actor: authorId,
              namespace: 'ub_${universe.value}',
              name: 'Recovered',
            ),
            throwsA(isA<ServerException>()),
          );
          expect(
            await session.authority.catalog(
              authorId,
              epochSeconds: BigInt.zero,
            ),
            isEmpty,
          );
        });
        expect(
          (await observer.execute(
            'SELECT generation FROM ${postgresUniverseSchema(universe)}.projection_state',
          )).single.single,
          generation,
        );
        await observer.execute(
          'DROP TRIGGER reject_register ON ${control()}.audit',
        );
        await observer.execute('DROP FUNCTION ${control()}.reject_register()');
        await register(author, universe, 'Recovered');
        await store.transaction(
          (session) => session.verifyUniverse(universe, complete: true),
        );
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}
