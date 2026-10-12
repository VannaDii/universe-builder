@TestOn('vm')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/catalog.dart';
import 'package:ub_store/src/candidate_foundation.dart';
import 'package:ub_store/src/postgres_candidate_admission.dart';
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
    'PostgreSQL shared factual admission',
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
      Future<void> probe(
        List<StoredVersion> records, {
        bool accepted = false,
      }) => expectLater(
        connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          final membership = await journal.stageVersions(input(records));
          await PostgresCandidateAdmission(journal).validate(membership);
          throw StateError('Discard admitted fixture');
        }),
        accepted ? throwsStateError : throwsFormatException,
      );

      test('frozen semantic records retain digests and their duplicate selectors are rejected', () async {
        expect(selected.length, 48);
        await expectLater(
          connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            final membership = await journal.stageVersions(input(selected));
            final records = [
              for (final version in membership.values)
                await journal.load(version),
            ];
            validateCandidateFoundationRecords(records);
            await expectLater(
              PostgresCandidateAdmission(journal).validate(membership),
              throwsA(
                isA<FormatException>().having(
                  (e) => e.message,
                  'message',
                  'Duplicate world selector',
                ),
              ),
            );
            for (final record in selected) {
              expect(
                (await journal.load(record.versionId)).toCanonical().toText(),
                record.toCanonical().toText(),
              );
            }
            throw StateError('Discard frozen semantic fixture');
          }),
          throwsStateError,
        );
        // Admission alone is not publication: it does not advance head or create
        // a receipt, exact approval or semantic/initialization evidence.
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          expect(await journal.head(continuity), genesis);
          expect(await journal.receipt(input(selected)), isNull);
        });
      });

      test('definition ancestry and classification remain selected-candidate checks', () async {
        final types = selected
            .where((r) => r.identity.recordKind == RecordKind.entityType)
            .toList();
        final root = types.firstWhere(
          (r) => objectFields(r.payload)['parent'] is CanonicalNull,
        );
        final child = types.firstWhere((r) {
          final parent = objectFields(r.payload)['parent'];
          return parent is CanonicalString &&
              parent.value == root.identity.recordId.value;
        });
        List<StoredVersion> changed(StoredVersion replacement) => [
          for (final record in selected)
            record.identity.recordId == replacement.identity.recordId
                ? replacement
                : record,
        ];
        await probe(
          changed(
            replace(root, {'parentResolution': CanonicalString('resolved')}),
          ),
        );
        await probe(
          changed(
            replace(root, {
              'parentResolution': CanonicalString('resolved'),
              'parent': CanonicalString(child.identity.recordId.value),
            }),
          ),
        );
        final entity = selected.firstWhere(
          (r) => r.identity.recordKind == RecordKind.entity,
        );
        await probe(
          changed(
            replace(child, {
              'parent': CanonicalString(entity.identity.recordId.value),
            }),
          ),
        );
        await probe(
          changed(
            replace(entity, {
              'classification': CanonicalString(RecordId.generate().value),
              'classificationResolution': CanonicalString('resolved'),
            }),
          ),
        );
        expect(
          (await connection.execute(
            'SELECT count(*) FROM $schema.record_versions',
          )).single.single,
          0,
        );
      });

      test('pinned editions remain usable without current membership and enforce identity/kind', () async {
        final workId = RecordId.generate(), editionId = RecordId.generate();
        final work = make(
          workId,
          CanonicalValue.parseJson(
            '{"record_kind":"work","kind":"novel","title":"Test novel","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]}',
          ),
        );
        final edition = make(
          editionId,
          CanonicalValue.parseJson(
            '{"record_kind":"work_version","work":{"universe":"${universe.value}","record":"${workId.value}"},"versionLabel":"Original","binding":{"kind":"unbound"}}',
          ),
        );
        StoredVersion scene(RecordId target, RecordVersionId version) => make(
          RecordId.generate(),
          CanonicalValue.parseJson(
            '{"record_kind":"scene_ref","sceneId":"scene-one","depictedEvents":[],"worldAssociations":[],"workVersion":{"universe":"${universe.value}","record":"${target.value}","version":"${version.value}"}}',
          ),
        );
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          await journal.stageVersions(input([work, edition]));
          final admission = PostgresCandidateAdmission(journal);
          final correct = await journal.stageVersions(
            input([scene(editionId, edition.versionId)]),
          );
          await admission.validate(correct);
          final mismatch = await journal.stageVersions(
            input([scene(RecordId.generate(), edition.versionId)]),
          );
          await expectLater(
            admission.validate(mismatch),
            throwsFormatException,
          );
          final wrongKind = await journal.stageVersions(
            input([scene(workId, work.versionId)]),
          );
          await expectLater(
            admission.validate(wrongKind),
            throwsFormatException,
          );
        });
      });

      test('work bindings use the named continuity rather than a matching revision elsewhere', () async {
        final workId = RecordId.generate();
        final work = make(
          workId,
          CanonicalValue.parseJson(
            '{"record_kind":"work","kind":"novel","title":"Test novel","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]}',
          ),
        );
        StoredVersion edition(ContinuityId id) => make(
          RecordId.generate(),
          CanonicalValue.parseJson(
            '{"record_kind":"work_version","work":{"universe":"${universe.value}","record":"${workId.value}"},"versionLabel":"Original","binding":{"kind":"bound","continuity":"${id.value}","revision":"${genesis.value}"}}',
          ),
        );
        await probe([work, edition(continuity)], accepted: true);
        await probe([work, edition(ContinuityId.generate())]);
      });

      test('typed unit/world aliases and declared current references preserve namespace guards', () async {
        final unit = selected.firstWhere(
          (r) => r.identity.recordKind == RecordKind.unit,
        );
        final world = make(
          RecordId.generate(),
          CanonicalValue.parseJson(
            '{"record_kind":"world","selector":"Distinct setting"}',
          ),
        );
        final unitAlias =
            'unit_${unit.identity.recordId.value.substring(RecordId.prefix.length)}';
        final worldAlias =
            'wld_${world.identity.recordId.value.substring(RecordId.prefix.length)}';
        final entityBody = CanonicalValue.parseJson(
          '{"record_kind":"entity","names":[],"classification":null,"classificationResolution":"unclassified","worldAssociations":[],"labels":{},"metadata":{}}',
        );
        final visitor = make(
          RecordId.generate(),
          CanonicalValue.parseJson(
            '{"record_kind":"entity","names":[],"classification":null,"classificationResolution":"unclassified","worldAssociations":[{"world":"$worldAlias","role":"setting","validity":{"kind":"unspecified"},"qualifiers":{}}],"labels":{"en":"rec_000000000000000000000099"},"metadata":{"distance":{"kind":"quantity","unit":"$unitAlias","value":{"kind":"decimal","digits":"30.00"}}}}',
          ),
        );
        await probe([unit, world, visitor], accepted: true);
        await probe([make(unit.identity.recordId, entityBody), world, visitor]);
        await probe([unit, make(world.identity.recordId, entityBody), visitor]);
        for (final scope in [universe, UniverseId.generate()]) {
          final missing = replace(visitor, {
            'metadata': CanonicalValue.parseJson(
              '{"current":{"kind":"record_ref","ref":{"universe":"${scope.value}","record":"rec_000000000000000000000099"}}}',
            ),
          });
          await probe([unit, world, missing]);
        }
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
