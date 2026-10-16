@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/postgres_initialization.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel.dart';
import 'package:ub_store/src/postgres_projection_schema.dart';
import 'package:ub_store/src/postgres_workflow_schema.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_semantic_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  String id(String prefix, int n) =>
      '${prefix}_${n.toRadixString(16).padLeft(24, '0')}';
  final universe = UniverseId.parse(id('unv', 0x1a11));
  final continuity = ContinuityId.parse(id('cont', 1));
  final principal = PrincipalId.parse(id('prn', 1));
  Map<String, Object> rr(int n) => {
    'universe': universe.value,
    'record': id('rec', n),
  };
  StoredVersion record(int n, int v, Map<String, Object?> payload) =>
      StoredVersion.build(
        RecordVersionId.parse(id('ver', v)),
        RecordIdentity(
          universeId: universe,
          recordId: RecordId.parse(id('rec', n)),
          recordKind: RecordKind.parse(payload['record_kind']! as String),
        ),
        CanonicalValue.parseJson(jsonEncode(payload)),
      );
  Map<String, Object?> payload(StoredVersion r) =>
      jsonDecode(r.payload.toText()) as Map<String, Object?>;
  StoredVersion changed(StoredVersion r, int v, Map<String, Object?> changes) =>
      record(int.parse(r.identity.recordId.value.substring(4), radix: 16), v, {
        ...payload(r),
        ...changes,
      });
  StoredVersion proposition(int n, int v, int subject, String digits) =>
      record(n, v, {
        'record_kind': 'proposition',
        'subject': rr(subject),
        'predicate': rr(2),
        'value': {'kind': 'integer', 'digits': digits},
        'quantification': 'particular',
        'context': rr(3),
      });
  StoredVersion assertion(
    int n,
    int v,
    int proposition,
    String mode,
    Map<String, Object?> basis,
  ) => record(n, v, {
    'record_kind': 'assertion',
    'attributeMode': mode,
    'proposition': rr(proposition),
    'polarity': 'support',
    'scope': {
      'context': rr(3),
      'applicability': {'kind': 'universe_wide'},
    },
    'validity': {
      'kind': 'calendar_interval',
      'calendar': id('cal', 4),
      'start': {'kind': 'exact', 'value': '10'},
      'end': {'kind': 'exact', 'value': '11'},
    },
    'persistence': 'explicit_interval',
    'precision': 'exact',
    'basis': basis,
  });

  final schema = postgresUniverseSchema(universe);
  late Connection connection;
  late RevisionId latestRevision;
  late RevisionId baseRevision;
  late List<StoredVersion> baseRows;
  Future<Connection> connect() => Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: port!,
      database: 'ub_disposable',
      username: 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  Future<CommitInput> request(String key, List<StoredVersion> records) =>
      connection.runTx((tx) async {
        final journal = PostgresJournal(tx, universe);
        final head = await journal.head(continuity);
        final membership = await journal.snapshot(continuity, head);
        return CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: head,
          principal: principal,
          decision: 'Reviewed disposable fixture',
          reason: key,
          idempotencyKey: key,
          changes: [
            for (final r in records)
              Assignment(
                recordId: r.identity.recordId,
                expected: membership[r.identity.recordId],
                next: r,
              ),
          ],
        );
      });

  // Internal storage pipeline with already-admitted fixture inputs. This is not
  // the service's authenticated, exactly-approved publication entry point.
  Future<RevisionId> publish(CommitInput input, {String? failAfter}) async {
    void checkpoint(String stage) {
      if (stage == failAfter) throw StateError('Interrupted $stage');
    }

    final revision = await connection.runTx(
      (tx) => PostgresKernel(
        tx,
        universe,
      ).commit(input, hook: (point) => checkpoint(point.name)),
    );
    latestRevision = revision;
    return revision;
  }

  Future<List<InitializationReceipt>> read() => connection.runTx(
    (tx) => PostgresInitializationEvidence(tx, universe).read(),
  );
  Future<List<InitializationReceipt>> readAt(ContinuityId c, RevisionId r) =>
      connection.runTx(
        (tx) => PostgresInitializationEvidence(tx, universe).readAt(c, r),
      );
  Future<void> verify() => connection.runTx(
    (tx) => PostgresInitializationEvidence(tx, universe).verify(),
  );
  Future<int> count(String table) async =>
      (await connection.execute('SELECT count(*) FROM $schema.$table'))
              .single
              .single
          as int;
  List<StoredVersion> initial(int instance, int offset) => [
    record(offset, offset, {
      'record_kind': 'event',
      'occurrence': 'occurred',
      'time': {'kind': 'exact', 'calendar': id('cal', 4), 'value': '10'},
      'participants': [
        {'record': rr(instance), 'role': 'starting_instance'},
      ],
      'labels': <String, Object>{},
    }),
    proposition(offset + 1, offset + 1, instance, '12'),
    assertion(offset + 2, offset + 2, offset + 1, 'instance', {
      'kind': 'instance_initialization',
      'start': {...rr(offset), 'version': id('ver', offset)},
      'definition': {...rr(6), 'version': id('ver', 6)},
      'source_revision': latestRevision.value,
    }),
  ];

  group(
    'PostgreSQL initialization admission',
    () {
      setUp(() async {
        connection = await connect();
        latestRevision = await connection.runTx((tx) async {
          await tx.execute('CREATE SCHEMA $schema');
          for (final sql in [
            ...postgresBodySchema(universe),
            ...postgresKernelSchema(universe),
            ...postgresSemanticSchema(universe),
            ...postgresWorkflowSchema(universe),
            ...postgresProjectionSchema(universe),
          ]) {
            await tx.execute(sql);
          }
          return PostgresJournal(
            tx,
            universe,
          ).initialize('Disposable initialization', continuity, principal);
        });
        baseRows = [
          record(1, 1, {
            'record_kind': 'entity_type',
            'namespace': 'pistol',
            'key': 'gun',
            'name': 'Gun',
            'labels': <String, Object>{},
            'parent': null,
            'parentResolution': 'root',
            'applicability': {'kind': 'universe_wide'},
            'classificationExecutable': true,
          }),
          record(2, 2, {
            'record_kind': 'property',
            'namespace': 'pistol',
            'key': 'rounds',
            'labels': <String, Object>{},
            'subjectTypes': [id('rec', 1)],
            'value': {'kind': 'integer'},
            'multiplicity': 'single',
            'persistence': 'explicit_interval',
            'exclusive': false,
            'symmetric': false,
            'transitive': false,
          }),
          record(3, 3, {
            'record_kind': 'represented_context',
            'universe': universe.value,
            'kind': {'kind': 'objective'},
            'labels': <String, Object>{},
          }),
          record(4, 4, {
            'record_kind': 'calendar',
            'namespace': 'pistol',
            'key': 'clock',
            'labels': <String, Object>{},
            'unitStructure': <String, Object>{},
          }),
          proposition(5, 5, 1, '12'),
          assertion(6, 6, 5, 'initial_value', {
            'kind': 'author_decision',
            'note': 'Starts with twelve',
          }),
          for (final n in [7, 8])
            record(n, n, {
              'record_kind': 'entity',
              'names': <Object>[],
              'classification': id('rec', 1),
              'classificationResolution': 'resolved',
              'worldAssociations': <Object>[],
              'labels': <String, Object>{},
              'metadata': <String, Object>{},
            }),
        ];
        baseRevision = await publish(await request('base', baseRows));
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });
      test(
        'exact receipts survive corrections, reconnect and durable retry',
        () async {
          final first = await request('first', initial(7, 10));
          final revision = await publish(first);
          final original = (await read()).single;
          expect(original.instance, RecordId.parse(id('rec', 7)));
          expect(original.assertion, RecordVersionId.parse(id('ver', 12)));
          expect(original.sourceRevision, baseRevision);
          expect(original.revision, revision);
          await publish(await request('second', initial(8, 20)));
          expect(await publish(first), revision);
          await publish(
            await request('correct-value', [proposition(11, 31, 7, '7')]),
          );
          final assertionVersion = await connection.runTx(
            (tx) => PostgresJournal(
              tx,
              universe,
            ).load(RecordVersionId.parse(id('ver', 12))),
          );
          await publish(
            await request('correct-assertion', [
              changed(assertionVersion, 32, {'precision': 'approximate'}),
            ]),
          );
          expect((await read()).first, original);
          await verify();
          await connection.close();
          connection = await connect();
          expect((await read()).first, original);
          final old = await connection.runTx(
            (tx) => PostgresJournal(
              tx,
              universe,
            ).load(RecordVersionId.parse(id('ver', 11))),
          );
          expect(old.digest, proposition(11, 11, 7, '12').digest);
          await expectLater(
            publish(await request('refill', initial(7, 40))),
            throwsFormatException,
          );
          expect(await read(), hasLength(2));
        },
      );

      test('recovery checks initialization after multiple batches of ordinary assertions', () async {
        await publish(
          await request('mixed-assertions', [
            proposition(100, 100, 7, '12'),
            for (var n = 101; n < 156; n++)
              assertion(n, n, 100, 'instance', {
                'kind': 'author_decision',
                'note': 'Ordinary authored assertion',
              }),
            ...initial(8, 200),
          ]),
        );
        final receipts = await read();
        expect(receipts, hasLength(1));
        expect(receipts.single.instance, RecordId.parse(id('rec', 8)));
        await verify();
        await connection.close();
        connection = await connect();
        await verify();
        expect(await read(), receipts);
        await expectLater(
          connection.runTx((tx) async {
            await tx.execute('DELETE FROM $schema.initialization_receipt');
            await PostgresInitializationEvidence(tx, universe).verify();
          }),
          throwsFormatException,
        );
        expect(await read(), receipts);
      });

      test('duplicate initialization and forged value roll back records and receipts', () async {
        await expectLater(
          publish(
            await request('duplicate', [...initial(7, 10), ...initial(7, 20)]),
          ),
          throwsFormatException,
        );
        final wrong = initial(7, 30);
        wrong[1] = proposition(31, 31, 7, '13');
        await expectLater(
          publish(await request('forged', wrong)),
          throwsFormatException,
        );
        expect(await count('record_versions'), 8);
        expect(await read(), isEmpty);
        expect(
          await connection.runTx(
            (tx) => PostgresJournal(tx, universe).head(continuity),
          ),
          baseRevision,
        );
      });

      test(
        'interruption rolls back definitions, receipts, heads and retries',
        () async {
          final input = await request('interrupt', [
            ...initial(7, 10),
            changed(baseRows.first, 50, {'name': 'Renamed gun type'}),
            changed(baseRows[6], 51, {
              'labels': {'en': 'Renamed instance'},
            }),
          ]);
          for (final stage in [
            'versions',
            'changes',
            'head',
            'receipt',
            'beforeCommit',
          ]) {
            await expectLater(
              publish(input, failAfter: stage),
              throwsStateError,
            );
            expect(await read(), isEmpty);
            expect(await count('record_versions'), 8);
            expect(await count('type_definition'), 1);
            expect(await count('definition_attribute'), 1);
            expect(await count('instance_classification'), 2);
            await connection.runTx((tx) async {
              final journal = PostgresJournal(tx, universe);
              expect(await journal.head(continuity), baseRevision);
              expect(await journal.receipt(input), isNull);
            });
          }
          final revision = await publish(input);
          expect(await publish(input), revision);
          expect(await read(), hasLength(1));
          await verify();
        },
      );

      test('uncertain occurrence, time, source and ancestry cannot establish a start', () async {
        final rows = initial(7, 10);
        for (final occurrence in <Object>[
          'planned',
          'hypothetical',
          {
            'descriptive': {'label': 'authored mode'},
          },
        ]) {
          final modified = [...rows];
          modified[0] = changed(rows[0], 10, {'occurrence': occurrence});
          await expectLater(
            publish(await request('occurrence-$occurrence', modified)),
            throwsFormatException,
          );
        }
        final noTime = [...rows];
        noTime[0] = changed(rows[0], 10, {
          'time': {'kind': 'unspecified'},
        });
        await expectLater(
          publish(await request('no-time', noTime)),
          throwsFormatException,
        );
        for (final change in [
          changed(baseRows[5], 30, {'precision': 'approximate'}),
          proposition(5, 31, 1, '13'),
          changed(baseRows[0], 32, {'classificationExecutable': false}),
        ]) {
          await expectLater(
            publish(await request('changed-source', [...rows, change])),
            throwsFormatException,
          );
        }
        final foreign = [...rows];
        final basis = {...payload(rows[2])['basis']! as Map<String, Object?>};
        basis['definition'] = {
          ...rr(6),
          'version': id('ver', 6),
          'universe': id('unv', 2),
        };
        foreign[2] = changed(rows[2], 12, {'basis': basis});
        await expectLater(
          publish(await request('foreign-source', foreign)),
          throwsFormatException,
        );
        expect(await read(), isEmpty);
        expect(await count('record_versions'), 8);
      });

      test('pinned fork ancestry excludes later receipts; restoration preserves original', () async {
        final rows = initial(7, 10);
        final first = await publish(await request('first', rows));
        final original = await read();
        expect(await readAt(continuity, baseRevision), isEmpty);
        expect(await readAt(continuity, first), original);
        final branch = ContinuityId.parse(id('cont', 2));
        final branchRevision = await connection.runTx((tx) async {
          final journal = PostgresJournal(tx, universe);
          await journal.lockUniverse();
          return journal.branch(branch, continuity, first, principal);
        });
        await publish(await request('second-instance', initial(8, 20)));
        expect(await readAt(branch, branchRevision), original);
        await expectLater(
          readAt(branch, latestRevision),
          throwsFormatException,
        );
        final remove = CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: latestRevision,
          principal: principal,
          decision: 'Reviewed retraction',
          reason: 'retract',
          idempotencyKey: 'retract',
          changes: [
            Assignment(
              recordId: rows[2].identity.recordId,
              expected: rows[2].versionId,
            ),
          ],
        );
        await publish(remove);
        await expectLater(
          publish(await request('new-start-after-retraction', initial(7, 100))),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'receipt forbids reset',
              'Instance property has already been initialized',
            ),
          ),
        );
        final forgedBasis = {
          ...payload(rows[2])['basis']! as Map<String, Object?>,
          'source_revision': latestRevision.value,
        };
        await expectLater(
          publish(
            await request('forged-restoration', [
              changed(rows[2], 98, {'basis': forgedBasis}),
            ]),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'original provenance',
              'Initialization provenance cannot change on historical restoration',
            ),
          ),
        );
        await publish(await request('restore', [changed(rows[2], 99, {})]));
        expect((await read()).first, original.single);
        await verify();
        await expectLater(
          connection.runTx((tx) async {
            await tx.execute('DELETE FROM $schema.initialization_receipt');
            await PostgresInitializationEvidence(tx, universe).verify();
          }),
          throwsFormatException,
        );
        expect((await read()).first, original.single);
        await verify();
      });

      test(
        'pending admission holds the universe lock until outer completion',
        () async {
          final input = await request('locked-start', initial(7, 10));
          final other = await connect();
          final entered = Completer<void>();
          final release = Completer<void>();
          final first = connection.runTx((tx) async {
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            final base = await journal.snapshot(continuity, baseRevision);
            final candidate = await journal.stageVersions(input);
            final pending = await PostgresInitializationEvidence(
              tx,
              universe,
            ).pending(input, base, candidate);
            expect(pending, hasLength(1));
            entered.complete();
            await release.future;
            throw StateError('Discard locked fixture');
          });
          final checked = expectLater(first, throwsStateError);
          try {
            await entered.future;
            await expectLater(
              other.runTx((tx) async {
                await tx.execute("SET LOCAL lock_timeout='100ms'");
                await PostgresInitializationEvidence(
                  tx,
                  universe,
                ).pending(input, {}, {});
              }),
              throwsA(
                isA<ServerException>().having(
                  (e) => e.code,
                  'lock timeout',
                  '55P03',
                ),
              ),
            );
          } finally {
            release.complete();
            await checked;
            await other.close();
          }
          expect(await count('record_versions'), 8);
          expect(await read(), isEmpty);
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
