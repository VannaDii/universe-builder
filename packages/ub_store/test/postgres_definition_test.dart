@TestOn('vm')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/catalog.dart';
import 'package:ub_store/src/postgres_definition_index.dart';
import 'package:ub_store/src/postgres_semantic_schema.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  final oracle = objectFields(
    CanonicalValue.parseJson(
      File('../../docs/decisions/relational-storage/semantic-oracle.json')
          .readAsStringSync(),
    ),
  );
  final universe = UniverseId.parse(
    (oracle['universe'] as CanonicalString).value,
  );
  final versions = {
    for (final raw in (oracle['versions'] as CanonicalArray).items)
      (objectFields(raw)['version'] as CanonicalString).value: objectFields(
        raw,
      ),
  };
  final selected = [
    for (final version in objectFields(oracle['membership']!).values)
      StoredVersion(
        versionId: RecordVersionId.parse((version as CanonicalString).value),
        identity: RecordIdentity(
          universeId: universe,
          recordId: RecordId.parse(
            (versions[version.value]!['identity'] as CanonicalString).value,
          ),
          recordKind: RecordKind.parse(
            (versions[version.value]!['kind'] as CanonicalString).value,
          ),
        ),
        payload: versions[version.value]!['value']!,
        digest: (versions[version.value]!['digest'] as CanonicalString).value,
      ),
  ];
  group(
    'PostgreSQL semantic projections',
    () {
      late Connection connection;
      late ContinuityId continuity;
      late PrincipalId principal;
      late RevisionId genesis;
      final schema = postgresUniverseSchema(universe);
      setUp(() async {
        continuity = ContinuityId.generate();
        principal = PrincipalId.generate();
        connection = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        genesis = await connection.runTx((tx) async {
          await tx.execute('CREATE SCHEMA $schema');
          for (final statement in [
            ...postgresBodySchema(universe),
            ...postgresKernelSchema(universe),
            ...postgresSemanticSchema(universe),
          ]) {
            await tx.execute(statement);
          }
          return PostgresJournal(
            tx,
            universe,
          ).initialize('Disposable admission', continuity, principal);
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });
      CommitInput input(List<StoredVersion> records) => CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: genesis,
        principal: principal,
        decision: 'Fixture awaiting factual admission',
        reason: 'Candidate checks',
        idempotencyKey: 'candidate',
        changes: [
          for (final record in records)
            Assignment(recordId: record.identity.recordId, next: record),
        ],
      );
      StoredVersion make(RecordId id, CanonicalValue payload) =>
          StoredVersion.build(
            RecordVersionId.generate(),
            RecordIdentity(
              universeId: universe,
              recordId: id,
              recordKind: RecordKind.parse(
                (objectFields(payload)['record_kind'] as CanonicalString).value,
              ),
            ),
            payload,
          );
      StoredVersion replace(
        StoredVersion record,
        Map<String, CanonicalValue> fields,
      ) => make(
        record.identity.recordId,
        CanonicalObject({...objectFields(record.payload), ...fields}.entries),
      );

      StoredVersion named(String name) => selected.firstWhere((r) {
        final value = objectFields(r.payload)['name'];
        return value is CanonicalString && value.value == name;
      });
      StoredVersion ending(String suffix) => selected.firstWhere(
        (r) => r.identity.recordId.value.endsWith(suffix),
      );
      Future<int> count(String table) async =>
          (await connection.execute('SELECT count(*) FROM $schema.$table'))
                  .single
                  .single
              as int;

      test('frozen ancestry, classification and attribute modes retain exact versions', () async {
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          final membership = await journal.stageVersions(input(selected));
          final index = PostgresDefinitionIndex(tx, universe);
          for (final record in selected) {
            await index.index(record, membership);
            expect(
              (await journal.load(record.versionId)).digest,
              record.digest,
            );
          }
        });
        expect(await count('type_definition'), 7);
        expect(await count('instance_classification'), 5);
        expect(await count('definition_attribute'), 4);
        expect(await count('initialization_receipt'), 0);
        expect(await count('classification_evidence'), 0);
        final worlds = await connection.execute(
          'SELECT ordinal,world_id FROM $schema.type_world',
        );
        expect(worlds.single, [0, ending('00c').identity.recordId.value]);
        final cedar = named('Western red cedar');
        final rows = await connection.execute(
          'SELECT parent_id,parent_resolution FROM $schema.type_definition WHERE version_id=\$1',
          parameters: [cedar.versionId.value],
        );
        expect(rows.single, [
          named('Cedar').identity.recordId.value,
          'resolved',
        ]);
        final classification = await connection.execute(
          'SELECT type_id,resolution FROM $schema.instance_classification WHERE record_id=\$1',
          parameters: [ending('008').identity.recordId.value],
        );
        expect(classification.single, [
          cedar.identity.recordId.value,
          'resolved',
        ]);
        final definitions = await connection.execute(
          'SELECT mode,count(*) FROM $schema.definition_attribute GROUP BY mode ORDER BY mode',
        );
        expect(definitions.map((r) => r.toList()).toList(), [
          ['initial_value', 1],
          ['shared', 3],
        ]);
        // Semantic indexing is not publication or initialization authorization.
        await connection.runTx((tx) async {
          expect(await PostgresJournal(tx, universe).head(continuity), genesis);
        });
      });

      test('rename retains exact names and historical ancestry; definitions use selected proposition', () async {
        final cedar = named('Western red cedar');
        const exactName = '\ufeff Cedar\u0000 é🌲';
        final renamed = replace(cedar, {'name': CanonicalString(exactName)});
        final assertion = ending('01d');
        final proposition = ending('01c');
        final newer = replace(proposition, {
          'subject': RecordRef(
            universe: universe,
            record: named('Gun').identity.recordId,
          ).toCanonical(),
        });
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          final membership = await journal.stageVersions(input(selected));
          final index = PostgresDefinitionIndex(tx, universe);
          await index.index(cedar, membership);
          await journal.stageVersions(input([renamed, newer]));
          await index.index(renamed, membership);
          // A newer persisted version must not override the supplied candidate.
          await index.index(assertion, membership);
        });
        final names = await connection.execute(
          'SELECT name,parent_id FROM $schema.type_definition WHERE record_id=\$1 ORDER BY name',
          parameters: [cedar.identity.recordId.value],
        );
        expect(
          names.map((r) => readPostgresAuthoredText(r[0] as List<int>)).toSet(),
          {'Western red cedar', exactName},
        );
        expect(names.map((r) => r[1]).toSet(), {
          named('Cedar').identity.recordId.value,
        });
        final definition = await connection.execute(
          'SELECT subject_id,predicate_id,mode FROM $schema.definition_attribute',
        );
        expect(definition.single, [
          named('Tree').identity.recordId.value,
          ending('00e').identity.recordId.value,
          'shared',
        ]);
      });

      test('missing candidate reference rolls back canonical bodies and semantic rows', () async {
        await expectLater(
          connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            final membership = await journal.stageVersions(input(selected));
            final index = PostgresDefinitionIndex(tx, universe);
            await index.index(named('Cedar'), membership);
            final incomplete = Map<RecordId, RecordVersionId>.of(membership)
              ..remove(ending('01c').identity.recordId);
            await index.index(ending('01d'), incomplete);
          }),
          throwsFormatException,
        );
        expect(await count('type_definition'), 0);
        expect(await count('record_versions'), 0);
      });

      test('foreign keys and resolution constraints reject invalid semantic rows', () async {
        await expectLater(
          connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            final membership = await journal.stageVersions(input(selected));
            await PostgresDefinitionIndex(
              tx,
              universe,
            ).index(named('Tree'), membership);
            await tx.execute(
              'UPDATE $schema.type_definition SET parent_resolution=\$1 WHERE version_id=\$2',
              parameters: ['resolved', named('Tree').versionId.value],
            );
          }),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'check', '23514'),
          ),
        );
        expect(await count('record_versions'), 0);
        await expectLater(
          connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            await journal.stageVersions(input(selected));
            await tx.execute(
              'INSERT INTO $schema.definition_attribute VALUES(\$1,\$2,\$3,\$4,\$5)',
              parameters: [
                universe.value,
                ending('01d').versionId.value,
                RecordId.generate().value,
                ending('00e').identity.recordId.value,
                'shared',
              ],
            );
          }),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'foreign key',
              '23503',
            ),
          ),
        );
        expect(await count('record_versions'), 0);
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
