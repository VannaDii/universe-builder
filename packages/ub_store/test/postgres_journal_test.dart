@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL canonical journal',
    () {
      late Connection connection;
      late UniverseId universe;
      late ContinuityId continuity;
      late PrincipalId principal;
      late RevisionId genesis;
      late String schema;
      final record = RecordId.generate();
      Future<Connection> open() => Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: port!,
          database: 'ub_disposable',
          username: 'postgres',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      Future<void> provision(TxSession tx, UniverseId id) async {
        await tx.execute('CREATE SCHEMA ${postgresUniverseSchema(id)}');
        for (final statement in [
          ...postgresBodySchema(id),
          ...postgresKernelSchema(id),
        ]) {
          await tx.execute(statement);
        }
      }

      setUp(() async {
        universe = UniverseId.generate();
        continuity = ContinuityId.generate();
        principal = PrincipalId.generate();
        schema = postgresUniverseSchema(universe);
        connection = await open();
        genesis = await connection.runTx((tx) async {
          await provision(tx, universe);
          return PostgresJournal(
            tx,
            universe,
          ).initialize('\uFEFFDisposable universe', continuity, principal);
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });
      StoredVersion entity(RecordVersionId version, {UniverseId? scope}) =>
          StoredVersion.build(
            version,
            RecordIdentity(
              universeId: scope ?? universe,
              recordId: record,
              recordKind: RecordKind.entity,
            ),
            EntityRecord(
              names: [],
              classification: null,
              classificationResolution: ClassificationResolution.unclassified,
              worldAssociations: [],
              labels: {'en': '\uFEFFcafé\u0000😀\r\n'},
              metadata: {},
            ).toWire(),
          );
      CommitInput input(
        String key,
        List<Assignment> changes, {
        RevisionId? head,
        ContinuityId? branch,
      }) => CommitInput(
        universe: universe,
        continuity: branch ?? continuity,
        expectedHead: head ?? genesis,
        principal: principal,
        decision: '\uFEFFApproved fixture\u0000',
        reason: '\uFEFFMemory\u0000😀\r\n',
        idempotencyKey: key,
        changes: changes,
      );
      // Admitted fixture data only. The application kernel must additionally run
      // factual/definition/initialization, workflow and authority checks.
      Future<RevisionId> appendAdmitted(CommitInput value, {int? fault}) =>
          connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            final receipt = await journal.receipt(value);
            if (receipt != null) return receipt;
            final membership = await journal.stageVersions(value);
            if (fault == 0) throw StateError('Interrupted versions');
            final revision = await journal.append(value);
            if (fault == 1) throw StateError('Interrupted append');
            await journal.advanceHead(
              value.continuity,
              value.expectedHead,
              revision,
              membership,
            );
            if (fault == 2) throw StateError('Interrupted head');
            await journal.writeReceipt(value, revision);
            if (fault == 3) throw StateError('Interrupted receipt');
            return revision;
          });

      test('batched versions preserve order and duplicates across chunks after reconnect', () async {
        final rows = [
          for (var n = 0; n < 64; n++)
            StoredVersion.build(
              RecordVersionId.generate(),
              RecordIdentity(
                universeId: universe,
                recordId: RecordId.generate(),
                recordKind: RecordKind.entity,
              ),
              entity(RecordVersionId.generate()).payload,
            ),
        ];
        await appendAdmitted(
          input('batch-read', [
            for (final row in rows)
              Assignment(recordId: row.identity.recordId, next: row),
          ]),
        );
        await connection.close();
        connection = await open();
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          final ids = [
            for (final row in rows.reversed) row.versionId,
            rows.first.versionId,
            rows.last.versionId,
          ];
          final batch = await journal.loadMany(ids).toList();
          final independent = [for (final id in ids) await journal.load(id)];
          expect(
            batch.map((v) => v.toCanonical().toText()),
            independent.map((v) => v.toCanonical().toText()),
          );
          await expectLater(
            journal.loadMany([RecordVersionId.generate()]).toList(),
            throwsFormatException,
          );
          expect(await journal.loadMany([]).toList(), isEmpty);
        });
      });
      test('exact bodies, history and active receipts survive reconnect', () async {
        final version = RecordVersionId.generate();
        final request = input('\uFEFFkey\u0000', [
          Assignment(recordId: record, next: entity(version)),
        ]);
        final revision = await appendAdmitted(request);
        await connection.close();
        connection = await open();
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          expect(await journal.head(continuity), revision);
          expect(await journal.heads(), {continuity: revision});
          expect(await journal.snapshot(continuity, genesis), isEmpty);
          expect(await journal.snapshot(continuity, revision), {
            record: version,
          });
          expect(
            (await journal.load(version)).toCanonical().toText(),
            entity(version).toCanonical().toText(),
          );
          expect(await journal.receipt(request), revision);
          final history = await journal.recordHistory(
            continuity,
            revision,
            record,
          );
          final fields = {
            for (final field in history.single.fields) field.key: field.value,
          };
          expect((fields['reason'] as CanonicalString).value, request.reason);
          expect(
            fields['record']!.toText(),
            entity(version).toCanonical().toText(),
          );
          final row = (await tx.execute(
            'SELECT decision,reason FROM $schema.commits WHERE id=\$1',
            parameters: [revision.value],
          )).single;
          expect(
            readPostgresAuthoredText(row[0] as Uint8List),
            request.decision,
          );
          expect(readPostgresAuthoredText(row[1] as Uint8List), request.reason);
        });
        expect(await appendAdmitted(request), revision);
        await expectLater(
          appendAdmitted(
            input(request.idempotencyKey, [
              Assignment(recordId: record, expected: version),
            ], head: revision),
          ),
          throwsFormatException,
        );
        await connection.execute(
          "INSERT INTO $schema.historical_receipt VALUES(\$1,\$2,'commit',\$3)",
          parameters: [
            universe.value,
            principal.value,
            postgresAuthoredText(request.idempotencyKey),
          ],
        );
        await connection.runTx((tx) async {
          expect(await PostgresJournal(tx, universe).receipt(request), isNull);
        });
        await expectLater(appendAdmitted(request), throwsFormatException);
      });

      test('every history write boundary rolls back and missing locks refuse writes', () async {
        final request = input('rollback', [
          Assignment(
            recordId: record,
            next: entity(RecordVersionId.generate()),
          ),
        ]);
        await connection.runTx((tx) async {
          await expectLater(
            PostgresJournal(tx, universe).stageVersions(request),
            throwsStateError,
          );
        });
        for (var fault = 0; fault < 4; fault++) {
          await expectLater(
            appendAdmitted(request, fault: fault),
            throwsStateError,
          );
          await connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            expect(await journal.head(continuity), genesis);
            expect(await journal.receipt(request), isNull);
            for (final table in [
              'record_identities',
              'record_versions',
              'commit_changes',
              'operation_receipts',
              'head_membership',
            ]) {
              expect(
                (await tx.execute('SELECT count(*) FROM $schema.$table'))
                    .single
                    .single,
                0,
              );
            }
            expect(
              (await tx.execute('SELECT count(*) FROM $schema.commits'))
                  .single
                  .single,
              1,
            );
          });
        }
      });

      test('pinned branches retain baseline and tombstone history', () async {
        final first = RecordVersionId.generate(),
            second = RecordVersionId.generate();
        final firstHead = await appendAdmitted(
          input('first', [Assignment(recordId: record, next: entity(first))]),
        );
        final fork = ContinuityId.generate();
        final forkGenesis = await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          return journal.branch(fork, continuity, firstHead, principal);
        });
        final mainHead = await appendAdmitted(
          input('second', [
            Assignment(recordId: record, expected: first, next: entity(second)),
          ], head: firstHead),
        );
        final removed = await appendAdmitted(
          input(
            'remove',
            [Assignment(recordId: record, expected: first)],
            branch: fork,
            head: forkGenesis,
          ),
        );
        await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          expect(await journal.snapshot(fork, forkGenesis), {record: first});
          expect(await journal.snapshot(fork, removed), isEmpty);
          expect(await journal.snapshot(continuity, mainHead), {
            record: second,
          });
          final history = await journal.recordHistory(fork, removed, record);
          expect(history.length, 2);
          expect(
            history.first.fields.firstWhere((e) => e.key == 'record').value,
            isA<CanonicalNull>(),
          );
          expect(
            history.last.fields
                .firstWhere((e) => e.key == 'record')
                .value
                .toText(),
            entity(first).toCanonical().toText(),
          );
          await journal.lockUniverse();
          expect(
            await journal.branch(fork, continuity, firstHead, principal),
            forkGenesis,
          );
          await expectLater(
            journal.branch(fork, continuity, mainHead, principal),
            throwsFormatException,
          );
          await expectLater(
            journal.snapshot(fork, mainHead),
            throwsFormatException,
          );
        });
        for (final sql in [
          'UPDATE $schema.continuities SET baseline_commit=NULL WHERE id=\$1',
          'UPDATE $schema.commits SET sequence=99 WHERE continuity_id=\$1',
          'DELETE FROM $schema.record_versions WHERE universe_id=\$1',
        ]) {
          await expectLater(
            connection.execute(
              sql,
              parameters: [
                sql.contains('record_versions') ? universe.value : fork.value,
              ],
            ),
            throwsA(
              isA<ServerException>().having((e) => e.code, 'code', '55000'),
            ),
          );
        }
        // Circular genesis references defer to commit, but cannot bind a head
        // from another continuity. A failed commit restores the previous head.
        await expectLater(
          connection.runTx(
            (tx) => tx.execute(
              'UPDATE $schema.continuities SET head_commit=\$1 WHERE id=\$2',
              parameters: [mainHead.value, fork.value],
            ),
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23503'),
          ),
        );
        await connection.runTx((tx) async {
          expect(await PostgresJournal(tx, universe).head(fork), removed);
        });
      });

      test('universe locks serialize connections and other namespaces stay independent', () async {
        final other = UniverseId.generate(),
            otherContinuity = ContinuityId.generate();
        final otherSchema = postgresUniverseSchema(other);
        final contender = await open();
        try {
          await connection.runTx((tx) async {
            await provision(tx, other);
            await PostgresJournal(
              tx,
              other,
            ).initialize('Other universe', otherContinuity, principal);
          });
          final sharedVersion = RecordVersionId.generate();
          final winner = input('winner', [
            Assignment(recordId: record, next: entity(sharedVersion)),
          ]);
          await appendAdmitted(winner);
          await connection.runTx((tx) async {
            final main = PostgresJournal(tx, universe);
            await main.lockUniverse();
            await expectLater(
              contender.runTx((otherTx) async {
                await otherTx.execute("SET LOCAL lock_timeout='100ms'");
                await PostgresJournal(otherTx, universe).lockUniverse();
              }),
              throwsA(
                isA<ServerException>().having((e) => e.code, 'code', '55P03'),
              ),
            );
            await contender.runTx((otherTx) async {
              await otherTx.execute("SET LOCAL lock_timeout='100ms'");
              final journal = PostgresJournal(otherTx, other);
              await journal.lockUniverse();
              await expectLater(
                journal.load(sharedVersion),
                throwsFormatException,
              );
              expect((await journal.heads()).keys, [otherContinuity]);
              final base = await journal.head(otherContinuity);
              final otherInput = CommitInput(
                universe: other,
                continuity: otherContinuity,
                expectedHead: base,
                principal: principal,
                decision: winner.decision,
                reason: winner.reason,
                idempotencyKey: winner.idempotencyKey,
                changes: [
                  Assignment(
                    recordId: record,
                    next: entity(sharedVersion, scope: other),
                  ),
                ],
              );
              final membership = await journal.stageVersions(otherInput);
              final revision = await journal.append(otherInput);
              await journal.advanceHead(
                otherContinuity,
                base,
                revision,
                membership,
              );
              await journal.writeReceipt(otherInput, revision);
              expect(
                (await journal.load(sharedVersion)).identity.universeId,
                other,
              );
            });
            expect(
              (await main.load(sharedVersion)).identity.universeId,
              universe,
            );
          });
          final stale = input('stale', [
            Assignment(
              recordId: record,
              next: entity(RecordVersionId.generate()),
            ),
          ]);
          await expectLater(
            contender.runTx((tx) async {
              final journal = PostgresJournal(tx, universe);
              await journal.lockUniverse();
              await journal.stageVersions(stale);
            }),
            throwsFormatException,
          );
        } finally {
          await contender.close();
          await connection.execute(
            'DROP SCHEMA IF EXISTS $otherSchema CASCADE',
          );
        }
      });

      test('former world selectors stay reserved after removal', () async {
        final firstVersion = RecordVersionId.generate();
        StoredVersion world(
          RecordId id,
          RecordVersionId version,
          String name,
        ) => StoredVersion.build(
          version,
          RecordIdentity(
            universeId: universe,
            recordId: id,
            recordKind: RecordKind.world,
          ),
          CanonicalObject([
            MapEntry('record_kind', CanonicalString('world')),
            MapEntry('selector', CanonicalString(name)),
            MapEntry('aliases', CanonicalArray([])),
            MapEntry('labels', CanonicalObject([])),
            MapEntry('metadata', CanonicalObject([])),
          ]),
        );
        final firstHead = await appendAdmitted(
          input('world', [
            Assignment(
              recordId: record,
              next: world(record, firstVersion, 'Original'),
            ),
          ]),
        );
        final head = await appendAdmitted(
          input('remove-world', [
            Assignment(recordId: record, expected: firstVersion),
          ], head: firstHead),
        );
        final replacement = RecordId.generate();
        await expectLater(
          appendAdmitted(
            input('reuse', [
              Assignment(
                recordId: replacement,
                next: world(
                  replacement,
                  RecordVersionId.generate(),
                  'ORIGINAL',
                ),
              ),
            ], head: head),
          ),
          throwsFormatException,
        );
        expect(
          (await connection.execute(
            'SELECT count(*) FROM $schema.world_name_reservations',
          )).single.single,
          1,
        );
        expect(
          (await connection.execute(
            'SELECT count(*) FROM $schema.record_versions',
          )).single.single,
          1,
        );
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
