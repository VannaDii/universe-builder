@TestOn('vm')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/postgres_candidate_admission.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_projection_recovery.dart';
import 'package:ub_store/src/postgres_projection_schema.dart';
import 'package:ub_store/src/postgres_projections.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  final universe = UniverseId.parse('unv_000000000000000000000001');
  final continuity = ContinuityId.generate();
  final principal = PrincipalId.generate();
  final record = RecordId.parse('rec_000000000000000000000001');
  final schema = postgresUniverseSchema(universe);
  late Connection connection;
  late RevisionId genesis;
  Future<Connection> connect() => Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: port!,
      database: 'ub_disposable',
      username: 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  StoredVersion entity(
    String label, {
    RecordId? identity,
    Map<String, DomainValue> metadata = const {},
    Iterable<WorldAssociation> worlds = const [],
  }) => StoredVersion.build(
    RecordVersionId.generate(),
    RecordIdentity(
      universeId: universe,
      recordId: identity ?? record,
      recordKind: RecordKind.entity,
    ),
    EntityRecord(
      names: [],
      classificationResolution: ClassificationResolution.unclassified,
      worldAssociations: worlds,
      labels: {'en': label},
      metadata: metadata,
    ).toWire(),
  );
  CommitInput input(
    RevisionId head,
    String key,
    StoredVersion? next, {
    RecordVersionId? expected,
  }) => CommitInput(
    universe: universe,
    continuity: continuity,
    expectedHead: head,
    principal: principal,
    decision: 'Already admitted disposable fixture',
    reason: 'Projection checks',
    idempotencyKey: key,
    changes: [Assignment(recordId: record, expected: expected, next: next)],
  );
  // Internal test primitives; author rights/exact approval belong to the service.
  Future<RevisionId> publish(CommitInput input) => connection.runTx((tx) async {
    final journal = PostgresJournal(tx, universe);
    await journal.lockUniverse();
    final candidate = await journal.stageVersions(input);
    await PostgresCandidateAdmission(journal).validate(candidate);
    final revision = await journal.append(input);
    await journal.advanceHead(
      continuity,
      input.expectedHead,
      revision,
      candidate,
    );
    final generation =
        (await tx.execute('SELECT generation FROM $schema.projection_state'))
                .single
                .single
            as int;
    for (final change in input.changes) {
      if (change.next != null) {
        await PostgresRecordProjections(
          tx,
          universe,
        ).project(generation, change.next!);
      }
    }
    await journal.writeReceipt(input, revision);
    return revision;
  });
  Future<List<StoredVersion>> search(ContinuityId c, RevisionId r, String q) =>
      connection.runTx(
        (tx) => PostgresProjectionRecovery(tx, universe).search(c, r, q),
      );
  Future<void> rebuild({
    void Function()? afterProjection,
    void Function()? beforeCompletion,
  }) => connection.runTx(
    (tx) => PostgresProjectionRecovery(tx, universe).rebuild(
      afterProjection: afterProjection,
      beforeCompletion: beforeCompletion,
    ),
  );
  Future<int> generation() async =>
      (await connection.execute(
            'SELECT generation FROM $schema.projection_state',
          )).single.single
          as int;
  Future<int> count(String table) async =>
      (await connection.execute('SELECT count(*) FROM $schema.$table'))
              .single
              .single
          as int;

  group(
    'PostgreSQL projections and pinned search',
    () {
      setUp(() async {
        connection = await connect();
        genesis = await connection.runTx((tx) async {
          await tx.execute('CREATE SCHEMA $schema');
          for (final sql in [
            ...postgresBodySchema(universe),
            ...postgresKernelSchema(universe),
            ...postgresProjectionSchema(universe),
          ]) {
            await tx.execute(sql);
          }
          return PostgresJournal(
            tx,
            universe,
          ).initialize('Disposable projection fixture', continuity, principal);
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });

      test('rebuild and reconnect preserve pinned branches, literal phrases and tombstones', () async {
        final original = entity('Original cedar');
        final first = await publish(input(genesis, 'original', original));
        final alternate = ContinuityId.generate();
        final fork = await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          return journal.branch(alternate, continuity, first, principal);
        });
        final corrected = entity('Latest elm');
        final latest = await publish(
          input(first, 'corrected', corrected, expected: original.versionId),
        );
        for (final table in [
          'reference_index',
          'typed_projection',
          'world_projection',
          'narrative_projection',
          'search_index',
          'head_membership',
          'projection_heads',
        ]) {
          await connection.execute('DELETE FROM $schema.$table');
        }
        await rebuild();
        expect(await generation(), 1);
        expect(await count('search_index'), 2);
        expect(await count('projection_heads'), 2);
        expect(await count('head_membership'), 2);
        expect(
          (await search(continuity, first, 'Original cedar')).single.versionId,
          original.versionId,
        );
        expect(await search(continuity, latest, 'Original'), isEmpty);
        expect(await search(continuity, first, 'Latest'), isEmpty);
        expect(
          (await search(alternate, fork, 'Original')).single.versionId,
          original.versionId,
        );
        expect(
          (await search(continuity, latest, '')).single.versionId,
          corrected.versionId,
        );
        expect(await search(continuity, latest, 'Latest OR Original'), isEmpty);
        expect(await search(continuity, latest, 'elm Latest'), isEmpty);
        expect(await search(continuity, latest, '"Latest elm"'), hasLength(1));
        await expectLater(
          search(continuity, latest, 'é' * 513),
          throwsFormatException,
        );
        final future = entity('Future ash');
        final third = await publish(
          input(latest, 'future', future, expected: corrected.versionId),
        );
        expect(
          (await search(continuity, third, 'Future')).single.versionId,
          future.versionId,
        );
        final removed = await publish(
          input(third, 'remove', null, expected: future.versionId),
        );
        await rebuild();
        expect(await generation(), 2);
        expect(await search(continuity, removed, ''), isEmpty);
        expect(
          (await search(alternate, fork, 'Original')).single.versionId,
          original.versionId,
        );
        expect(
          (await connection.execute(
            'SELECT DISTINCT generation FROM $schema.search_index',
          )).single.single,
          2,
        );
        await connection.close();
        connection = await connect();
        expect(
          (await search(continuity, latest, 'Latest')).single.digest,
          corrected.digest,
        );
        await expectLater(
          search(alternate, latest, 'Latest'),
          throwsFormatException,
        );
      });

      test('failed projection generation switches preserve previous rows and head caches', () async {
        final original = entity('Original');
        final first = await publish(input(genesis, 'original', original));
        for (final phase in ['projection', 'beforeCompletion']) {
          await expectLater(
            rebuild(
              afterProjection: phase == 'projection'
                  ? () => throw StateError('Interrupted projection')
                  : null,
              beforeCompletion: phase == 'beforeCompletion'
                  ? () => throw StateError('Interrupted switch')
                  : null,
            ),
            throwsStateError,
          );
          expect(await generation(), 0);
          expect(await count('search_index'), 1);
          expect(
            (await connection.execute(
              'SELECT revision_id FROM $schema.projection_heads',
            )).single.single,
            first.value,
          );
          expect(
            (await search(continuity, first, 'Original')).single.versionId,
            original.versionId,
          );
        }
        await rebuild();
        expect(await generation(), 1);
      });

      test('exact authored names, scalar paths, world and narrative dependencies survive indexing', () async {
        const label = '\ufeffCafé\u0000 red cedar 🌲';
        const key = 'é\u0000field';
        const value = '\ufeffexact\u0000value';
        final world = WorldId.parse('wld_000000000000000000000002');
        final association = WorldAssociation(
          world: world,
          role: 'inhabits',
          validity: const UnspecifiedValidity(),
          qualifiers: {},
        );
        final enriched = entity(
          label,
          metadata: {key: TextValue(value)},
          worlds: [association],
        );
        final work = StoredVersion.build(
          RecordVersionId.generate(),
          RecordIdentity(
            universeId: universe,
            recordId: RecordId.generate(),
            recordKind: RecordKind.work,
          ),
          WorkRecord(
            kind: WorkKind.novel,
            title: 'Cedar history',
            labels: {},
            sourceRefs: [],
            versions: [],
            worldAssociations: [association],
          ).toWire(),
        );
        // Exercise typed projection storage directly; neither this fixture nor
        // indexing bypasses candidate admission in the publication coordinator.
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          final request = CommitInput(
            universe: universe,
            continuity: continuity,
            expectedHead: genesis,
            principal: principal,
            decision: 'Disposable projection rows',
            reason: 'Exact projection bytes',
            idempotencyKey: 'exact',
            changes: [
              for (final r in [enriched, work])
                Assignment(recordId: r.identity.recordId, next: r),
            ],
          );
          final membership = await journal.stageVersions(request);
          final revision = await journal.append(request);
          await journal.advanceHead(continuity, genesis, revision, membership);
          final projections = PostgresRecordProjections(tx, universe);
          await projections.project(0, enriched);
          await projections.project(0, work);
          expect(
            (await PostgresProjectionRecovery(
              tx,
              universe,
            ).search(continuity, revision, 'red cedar')).single.digest,
            enriched.digest,
          );
          expect(
            (await PostgresProjectionRecovery(
              tx,
              universe,
            ).search(continuity, revision, 'café')).single.versionId,
            enriched.versionId,
          );
        });
        final stored =
            (await connection.execute(
                  'SELECT text FROM $schema.search_index WHERE version_id=\$1',
                  parameters: [enriched.versionId.value],
                )).single.single
                as List<int>;
        expect(readPostgresAuthoredText(stored), label);
        final scalar = await connection.execute(
          'SELECT path,value FROM $schema.typed_projection WHERE path=\$1',
          parameters: [postgresAuthoredText('/metadata/$key/kind')],
        );
        expect(scalar, hasLength(1));
        expect(
          readPostgresAuthoredText(scalar.single[0] as List<int>),
          '/metadata/$key/kind',
        );
        expect(readPostgresAuthoredText(scalar.single[1] as List<int>), 'text');
        final prose = await connection.execute(
          'SELECT value FROM $schema.typed_projection WHERE path=\$1',
          parameters: [postgresAuthoredText('/metadata/$key/text')],
        );
        expect(prose, isEmpty);
        final references = await connection.execute(
          'SELECT target_record,path FROM $schema.reference_index WHERE version_id=\$1',
          parameters: [work.versionId.value],
        );
        expect(references.single[0], 'rec_000000000000000000000002');
        expect(
          readPostgresAuthoredText(references.single[1] as List<int>),
          '/worldAssociations/0/world',
        );
        expect(await count('world_projection'), 2);
        expect(await count('narrative_projection'), 1);
        final indexes = await connection.execute(
          "SELECT indexdef FROM pg_catalog.pg_indexes WHERE schemaname=\$1 AND indexname='search_document'",
          parameters: ['ub_${universe.value}'],
        );
        expect(
          indexes.single.single as String,
          contains('USING gin (document)'),
        );
        await expectLater(
          connection.runTx(
            (tx) => PostgresRecordProjections(
              tx,
              UniverseId.generate(),
            ).project(0, enriched),
          ),
          throwsFormatException,
        );
      });

      test(
        'matching IDs in another namespace cannot enter pinned search',
        () async {
          final own = entity('Own cedar');
          final first = await publish(input(genesis, 'own', own));
          final other = UniverseId.generate();
          final otherSchema = postgresUniverseSchema(other);
          try {
            await connection.runTx((tx) async {
              await tx.execute('CREATE SCHEMA $otherSchema');
              for (final sql in [
                ...postgresBodySchema(other),
                ...postgresKernelSchema(other),
                ...postgresProjectionSchema(other),
              ]) {
                await tx.execute(sql);
              }
              final journal = PostgresJournal(tx, other);
              final base = await journal.initialize(
                'Other fixture',
                continuity,
                principal,
              );
              final foreign = StoredVersion.build(
                own.versionId,
                RecordIdentity(
                  universeId: other,
                  recordId: record,
                  recordKind: RecordKind.entity,
                ),
                EntityRecord(
                  names: [],
                  classificationResolution:
                      ClassificationResolution.unclassified,
                  worldAssociations: [],
                  labels: {'en': 'Private visitor'},
                  metadata: {},
                ).toWire(),
              );
              final request = CommitInput(
                universe: other,
                continuity: continuity,
                expectedHead: base,
                principal: principal,
                decision: 'Other fixture',
                reason: 'Namespace check',
                idempotencyKey: 'own',
                changes: [Assignment(recordId: record, next: foreign)],
              );
              final candidate = await journal.stageVersions(request);
              final revision = await journal.append(request);
              await journal.advanceHead(continuity, base, revision, candidate);
              await PostgresRecordProjections(tx, other).project(0, foreign);
              // A hostile session namespace cannot redirect qualified reads or
              // the PostgreSQL parser configuration into another universe.
              await tx.execute('SET LOCAL search_path=$otherSchema,pg_catalog');
              final ownSearch = PostgresProjectionRecovery(tx, universe);
              expect(
                await ownSearch.search(continuity, first, 'Private'),
                isEmpty,
              );
              expect(
                (await ownSearch.search(continuity, first, '')).single.digest,
                own.digest,
              );
              final foreignSearch = PostgresProjectionRecovery(tx, other);
              expect(
                await foreignSearch.search(continuity, revision, 'Own'),
                isEmpty,
              );
              expect(
                (await foreignSearch.search(
                  continuity,
                  revision,
                  'Private',
                )).single.digest,
                foreign.digest,
              );
            });
          } finally {
            await connection.execute(
              'DROP SCHEMA IF EXISTS $otherSchema CASCADE',
            );
          }
        },
      );

      test('canonical corruption refuses rebuild without replacing disposable generation', () async {
        final original = entity('Original');
        final first = await publish(input(genesis, 'original', original));
        await expectLater(
          connection.runTx((tx) async {
            await tx.execute(
              'ALTER TABLE $schema.record_versions DISABLE TRIGGER immutable_history',
            );
            await tx.execute(
              'UPDATE $schema.record_versions SET digest=\$1',
              parameters: ['0' * 64],
            );
            await PostgresProjectionRecovery(tx, universe).rebuild();
          }),
          throwsFormatException,
        );
        expect(await generation(), 0);
        expect(await count('search_index'), 1);
        expect(
          (await search(continuity, first, 'Original')).single.digest,
          original.digest,
        );
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
