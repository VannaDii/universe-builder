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
  test(
    'multiple PostgreSQL universe schemas retain isolated catalog and heads after restart',
    () async {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: port!,
        database: 'ub_disposable',
        username: 'postgres',
      );
      const settings = ConnectionSettings(sslMode: SslMode.disable);
      final observer = await Connection.open(endpoint, settings: settings);
      PostgresInstallationStore? store;
      NativePostgresRuntime? runtime;
      OperationId? instance;
      final author = ProfileId.generate(), reader = ProfileId.generate();
      const credential = 'disposable-catalog-workload';
      final created =
          <
            ({
              UniverseId id,
              ContinuityId continuity,
              RevisionId revision,
              String name,
            })
          >[];
      EngineHello hello(ProfileId profile) => EngineHello(
        protocolVersion: protocolVersion,
        profileId: profile,
        credential: const Credential(credential),
        clientName: 'Catalog workload',
      );
      Map<String, CanonicalValue> fields(CanonicalValue value) =>
          Map.fromEntries((value as CanonicalObject).fields);
      void measured(String phase, Stopwatch watch) => stdout.writeln(
        'catalog workload: $phase ${watch.elapsedMilliseconds} ms',
      );
      try {
        store = await PostgresInstallationStore.create(
          endpoint,
          settings: settings,
        );
        instance = store.instanceId;
        await store.transaction((session) async {
          final hash = sha256.convert(utf8.encode(credential)).toString();
          await session.authority.enroll(id: author, credentialHash: hash);
          await session.authority.enroll(
            id: reader,
            credentialHash: hash,
            actor: author,
          );
        });
        runtime = NativePostgresRuntime(store: store);
        var connection = await runtime.connect(hello(author));
        var phase = Stopwatch()..start();
        for (var n = 0; n < 20; n++) {
          final name = 'Catalog universe ${n.toString().padLeft(2, '0')} é😀';
          final value = fields(
            await connection.execute(
              CreateUniverseEngineRequest(
                name: name,
                start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
              ),
            ),
          );
          created.add((
            id: UniverseId.parse(wireString(value['universe_id']!)),
            continuity: ContinuityId.parse(wireString(value['continuity_id']!)),
            revision: RevisionId.parse(wireString(value['revision']!)),
            name: name,
          ));
        }
        measured('provision 20 universes', phase);
        expect(created.map((row) => row.id).toSet(), hasLength(20));
        final schemaNames = created.map((row) => 'ub_${row.id.value}').toList();
        final layout = (await observer.execute(
          'SELECT count(*) AS tables, coalesce(sum(pg_total_relation_size(c.oid)),0)::bigint AS bytes '
          'FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace '
          "WHERE n.nspname=ANY(\$1::text[]) AND c.relkind='r'",
          parameters: [schemaNames],
        )).single.toColumnMap();
        expect(layout['tables'] as int, greaterThanOrEqualTo(20 * 903));
        stdout.writeln(
          'catalog workload: 20 universe namespaces, '
          '${layout['tables']} tables, ${layout['bytes']} table/index bytes',
        );
        await runtime.close();
        runtime = null;
        await store.close();
        store = null;
        phase = Stopwatch()..start();
        store = await PostgresInstallationStore.openExisting(
          endpoint,
          settings: settings,
        );
        expect(store.instanceId, instance);
        runtime = NativePostgresRuntime(store: store);
        connection = await runtime.connect(hello(author));
        measured('reopen installation', phase);
        phase = Stopwatch()..start();
        final status = fields(
          await connection.execute(const StatusEngineRequest()),
        );
        final catalog = (status['universes'] as CanonicalArray).items
            .map(fields)
            .toList();
        expect(
          catalog.map((row) => wireString(row['id']!)).toSet(),
          created.map((row) => row.id.value).toSet(),
        );
        expect(
          catalog.map((row) => wireString(row['name']!)),
          created.map((row) => row.name),
        );
        measured('catalog read', phase);
        phase = Stopwatch()..start();
        for (final row in created) {
          final library = fields(
            await connection.execute(
              LibraryEngineRequest(universe: Selector(row.name)),
            ),
          );
          final storage = fields(library['storage']!);
          expect(wireString(storage['universe']!), row.id.value);
          expect(
            storage['heads']!.toText(),
            CanonicalArray([
              CanonicalArray([
                CanonicalString(row.continuity.value),
                CanonicalString(row.revision.value),
              ]),
            ]).toText(),
          );
        }
        measured('recover and read 20 libraries', phase);
        final restricted = await runtime.connect(hello(reader));
        expect(
          (fields(
                    await restricted.execute(const StatusEngineRequest()),
                  )['universes']
                  as CanonicalArray)
              .items,
          isEmpty,
        );
        await expectLater(
          restricted.execute(
            LibraryEngineRequest(universe: Selector(created.first.name)),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      } finally {
        try {
          await runtime?.close();
          await store?.close();
        } finally {
          try {
            for (final row in created) {
              await observer.execute(
                'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(row.id)} CASCADE',
              );
            }
            if (instance != null) {
              await observer.execute(
                'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(instance)} CASCADE',
              );
            }
          } finally {
            await observer.close();
          }
        }
      }
    },
    skip:
        port == null || Platform.environment['UB_RUN_STANDARD_WORKLOAD'] != '1'
        ? 'Set UB_TEST_POSTGRES_PORT and UB_RUN_STANDARD_WORKLOAD=1 for this disposable workload'
        : false,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
