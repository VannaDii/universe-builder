@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/postgres_workflow_schema.dart';
import 'package:ub_store/src/postgres_workflow_storage.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL retained workflows',
    () {
      late Connection connection;
      late UniverseId universe;
      late ContinuityId continuity;
      late PrincipalId principal;
      late RevisionId genesis;
      late String schema;
      CanonicalValue value(Object? v) =>
          CanonicalValue.parseJson(jsonEncode(v));
      final approval = value({
        'author': 'author-one',
        'proposal': {
          'proposal_id': 'prp_000000000000000000000001',
          'version': 1,
          'digest': 'a' * 64,
        },
        'validation_digest': 'b' * 64,
        'evaluator': 'rules-one',
      });
      final cursor = CanonicalValue.parseJson(
        '{"binding":"\\ufeffexact\\u0000😀","offset":18446744073709551615}',
      );
      Future<Connection> open() => Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: port!,
          database: 'ub_disposable',
          username: 'postgres',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      setUp(() async {
        universe = UniverseId.generate();
        continuity = ContinuityId.generate();
        principal = PrincipalId.generate();
        schema = postgresUniverseSchema(universe);
        connection = await open();
        genesis = await connection.runTx((tx) async {
          await tx.execute('CREATE SCHEMA $schema');
          for (final statement in [
            ...postgresBodySchema(universe),
            ...postgresKernelSchema(universe),
            ...postgresWorkflowSchema(universe),
          ]) {
            await tx.execute(statement);
          }
          return PostgresJournal(
            tx,
            universe,
          ).initialize('Disposable workflow', continuity, principal);
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });
      Future<void> append(
        Map<String, String?> expected,
        Iterable<MapEntry<String, CanonicalValue>> entries,
      ) => connection.runTx(
        (tx) => PostgresWorkflowStorage(
          tx,
          universe,
        ).compareAppend(expected, entries),
      );

      test('typed envelopes, exact counters and retry digests survive reconnect', () async {
        final entries = {
          'cancel:one\u0000': value({'cancelled': false}),
          'reserved-record:one': value({
            'proposal_id': 'prp_000000000000000000000001',
          }),
          'cursor:one': cursor,
          'approval:one': approval,
          'draft:one': CanonicalValue.parseJson(
            '{"version":18446744073709551615,"content":{"base_revision":"${genesis.value}","represented_context":"rec_000000000000000000000001","operations":[],"rationale":"\\ufeffmemoir\\u0000😀"}}',
          ),
          'assessment-selection:one': value({
            'proposal': {
              'proposal_id': 'prp_000000000000000000000001',
              'version': 1,
              'digest': 'a' * 64,
            },
            'generation': 1,
            'selected': null,
          }),
          'logical-import-origin:one': value({
            'digest': 'c' * 64,
            'source_universe': universe.value,
            'target_universe': universe.value,
            'complete': true,
            'omitted_records': 0,
          }),
          'logical-import-admission:one': value({
            'preview_id': 'op_000000000000000000000001',
            'digest': 'd' * 64,
            'universe_id': universe.value,
            'name': '\uFEFFImported\u0000',
            'complete': true,
            'omitted_records': 0,
            'imported': true,
          }),
        };
        await append({}, entries.entries);
        await append({}, entries.entries);
        expect(
          (await connection.execute(
            'SELECT count(*) FROM $schema.workflow_entries',
          )).single.single,
          entries.length,
        );
        await expectLater(
          connection.execute(
            'INSERT INTO $schema.workflow_entries(key,family,digest,digest_recipe,"Cursor","Cancellation") '
            'SELECT \$1,\'Cursor\',a.digest,a.digest_recipe,a."Cursor",b."Cancellation" '
            'FROM $schema.workflow_entries a,$schema.workflow_entries b WHERE a.key=\$2 AND b.key=\$3',
            parameters: [
              postgresAuthoredText('cursor:invalid-family'),
              postgresAuthoredText('cursor:one'),
              postgresAuthoredText('cancel:one\u0000'),
            ],
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
        await connection.close();
        connection = await open();
        await connection.runTx((tx) async {
          final workflow = PostgresWorkflowStorage(tx, universe);
          for (final entry in entries.entries) {
            expect(
              (await workflow.evidence(entry.key))!.toText(),
              entry.value.toText(),
            );
          }
          expect(await workflow.keys('cancel:'), ['cancel:one\u0000']);
        });
        await expectLater(
          append({}, [
            MapEntry('cancel:one\u0000', value({'cancelled': true})),
          ]),
          throwsFormatException,
        );
        await expectLater(
          append({}, [MapEntry('unknown:one', value({}))]),
          throwsFormatException,
        );
        await expectLater(
          append({}, [
            MapEntry(
              'cancel:invalid',
              value({'cancelled': true, 'invented': 'field'}),
            ),
          ]),
          throwsFormatException,
        );
        await connection.runTx((tx) async {
          expect(
            await PostgresWorkflowStorage(tx, universe).get('cancel:invalid'),
            isNull,
          );
        });
        await expectLater(
          connection.execute(
            "UPDATE $schema.workflow_entries SET digest='corrupt'",
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '55000'),
          ),
        );
      });

      test('historical approval and cursor evidence cannot regain active authority', () async {
        await append({}, [
          MapEntry('approval:one', approval),
          MapEntry('cursor:one', cursor),
        ]);
        for (final key in ['approval:one', 'cursor:one']) {
          await connection.execute(
            'INSERT INTO $schema.historical_workflow VALUES(\$1)',
            parameters: [postgresAuthoredText(key)],
          );
        }
        await connection.runTx((tx) async {
          final workflow = PostgresWorkflowStorage(tx, universe);
          expect(await workflow.get('approval:one'), isNull);
          expect(await workflow.get('cursor:one'), isNull);
          expect(await workflow.keys('approval:'), isEmpty);
          expect(await workflow.latestKey('cursor:'), isNull);
          expect(
            (await workflow.evidence('approval:one'))!.toText(),
            approval.toText(),
          );
        });
        await expectLater(
          append({}, [MapEntry('approval:one', approval)]),
          throwsFormatException,
        );
        await append({}, [MapEntry('approval:fresh', approval)]);
        await connection.runTx((tx) async {
          expect(
            (await PostgresWorkflowStorage(tx, universe).get('approval:fresh'))!
                .toText(),
            approval.toText(),
          );
        });
      });

      test(
        'selection comparison and append roll back the entire retained batch',
        () async {
          await append({'cursor:': null}, [MapEntry('cursor:0001', cursor)]);
          await expectLater(
            append({'cursor:': null}, [MapEntry('cursor:0002', cursor)]),
            throwsFormatException,
          );
          await expectLater(
            append(
              {'cursor:': 'cursor:0001'},
              [
                MapEntry('cursor:0002', cursor),
                MapEntry('cancel:invalid', value({'invented': true})),
              ],
            ),
            throwsFormatException,
          );
          await connection.runTx((tx) async {
            final workflow = PostgresWorkflowStorage(tx, universe);
            expect(await workflow.get('cursor:0002'), isNull);
            final journal = PostgresJournal(tx, universe);
            await journal.lockUniverse();
            await journal.compareWorkflow({'cursor:': 'cursor:0001'});
            await expectLater(
              journal.compareWorkflow({'cursor:': 'stale'}),
              throwsFormatException,
            );
          });
          await append(
            {'cursor:': 'cursor:0001'},
            [
              MapEntry('cursor:0002', cursor),
              MapEntry('cancel:one', value({'cancelled': false})),
            ],
          );
          await expectLater(
            append({}, [
              MapEntry('cancel:new', value({'cancelled': true})),
              MapEntry('cancel:one', value({'cancelled': true})),
            ]),
            throwsFormatException,
          );
          await connection.runTx((tx) async {
            final workflow = PostgresWorkflowStorage(tx, universe);
            expect(await workflow.keys('cursor:'), [
              'cursor:0001',
              'cursor:0002',
            ]);
            expect(await workflow.latestKey('cursor:'), 'cursor:0002');
            expect(await workflow.get('cancel:new'), isNull);
          });
        },
      );

      test(
        'awaited verification retains the universe lock and failure rolls back',
        () async {
          final entered = Completer<void>(), resume = Completer<void>();
          final original = StateError('Interrupted verification');
          final pending = connection.runTx(
            (tx) => PostgresWorkflowStorage(tx, universe)
                .compareAppendWithVerification(
                  verify: () async {
                    entered.complete();
                    await resume.future;
                    throw original;
                  },
                  entries: [
                    MapEntry('cancel:pending', value({'cancelled': true})),
                  ],
                ),
          );
          final failed = expectLater(pending, throwsA(same(original)));
          await entered.future;
          final contender = await open();
          try {
            await expectLater(
              contender.runTx((tx) async {
                await tx.execute("SET LOCAL lock_timeout='100ms'");
                await PostgresWorkflowStorage(
                  tx,
                  universe,
                ).put('cancel:other', value({'cancelled': true}));
              }),
              throwsA(
                isA<ServerException>().having((e) => e.code, 'code', '55P03'),
              ),
            );
          } finally {
            await contender.close();
            resume.complete();
          }
          await failed;
          await connection.runTx((tx) async {
            expect(
              await PostgresWorkflowStorage(tx, universe).get('cancel:pending'),
              isNull,
            );
          });
          await append({}, [
            MapEntry('cancel:released', value({'cancelled': true})),
          ]);
        },
      );

      test('source, media, names and staging preserve exact bytes and digest bindings', () async {
        const text = '\uFEFF\uFEFFCafé\u0000😀\r\n';
        final digest = sha256.convert(utf8.encode(text)).toString();
        final source = value({
          'record_kind': 'source_version',
          'source': {
            'universe': universe.value,
            'record': 'rec_000000000000000000000001',
          },
          'digest': digest,
          'mediaType': 'text/plain',
          'byteSize': utf8.encode(text).length,
          'importActor': principal.value,
          'importTime': '2026-10-11T12:00:00Z',
          'decoding': {
            'encoding': 'utf-8',
            'representation': 'unicode',
            'byteLength': utf8.encode(text).length,
          },
          'origin': <String, Object?>{},
        });
        final image = value({
          'record_kind': 'image_asset',
          'digest': 'b' * 64,
          'media_type': 'image/png',
          'byte_size': 68,
          'width': 1,
          'height': 1,
          'original_name': '\uFEFFmap\u0000.png',
        });
        final entries = {
          'source:$digest': CanonicalString(text),
          'image-bytes:\uFEFFasset\u0000:0': CanonicalString(
            base64.encode([0, 255, 10]),
          ),
          'continuity-name:${continuity.value}': CanonicalString(
            '\uFEFFCampaign\u0000😀',
          ),
          'source-version:one': source,
          'image-asset:one': image,
        };
        await append({}, entries.entries);
        await connection.runTx((tx) async {
          final workflow = PostgresWorkflowStorage(tx, universe);
          for (final entry in entries.entries) {
            expect(
              (await workflow.evidence(entry.key))!.toText(),
              entry.value.toText(),
            );
          }
          expect(await workflow.keys('image-bytes:'), [
            'image-bytes:\uFEFFasset\u0000:0',
          ]);
        });
        await expectLater(
          append({}, [MapEntry('image-asset:wrong', source)]),
          throwsFormatException,
        );
        await expectLater(
          append({}, [MapEntry('source:${'0' * 64}', CanonicalString(text))]),
          throwsFormatException,
        );
        for (final ordinal in ['01', '+1', '-1', '9223372036854775808']) {
          await expectLater(
            append({}, [
              MapEntry('image-bytes:asset:$ordinal', CanonicalString('AA==')),
            ]),
            throwsFormatException,
          );
        }
        await expectLater(
          append({}, [MapEntry('image-bytes:asset:1', CanonicalString('AA'))]),
          throwsFormatException,
        );
        await expectLater(
          connection.execute('DELETE FROM $schema.source_content'),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '55000'),
          ),
        );
      });

      test('identical retries reconstruct retained evidence and detect corruption', () async {
        await append({}, [MapEntry('cursor:one', cursor)]);
        await expectLater(
          connection.runTx((tx) async {
            await tx.execute(
              'ALTER TABLE $schema.workflow_entries DISABLE TRIGGER immutable_workflow',
            );
            await tx.execute(
              "UPDATE $schema.workflow_entries SET digest='${'0' * 64}'",
            );
            await expectLater(
              PostgresWorkflowStorage(tx, universe).put('cursor:one', cursor),
              throwsFormatException,
            );
            throw StateError('Discard corrupt fixture');
          }),
          throwsStateError,
        );
        await append({}, [MapEntry('cursor:one', cursor)]);
        const text = '\uFEFFSource';
        final digest = sha256.convert(utf8.encode(text)).toString();
        await append({}, [MapEntry('source:$digest', CanonicalString(text))]);
        await expectLater(
          connection.runTx((tx) async {
            await tx.execute(
              'ALTER TABLE $schema.source_content DISABLE TRIGGER immutable_workflow',
            );
            await tx.execute(
              'UPDATE $schema.source_content SET utf8_content=\$1',
              parameters: [postgresAuthoredText('corrupt')],
            );
            await expectLater(
              PostgresWorkflowStorage(tx, universe).evidence('source:$digest'),
              throwsFormatException,
            );
            throw StateError('Discard corrupt content fixture');
          }),
          throwsStateError,
        );
      });

      test(
        'matching workflow keys remain independent across universe namespaces',
        () async {
          final other = UniverseId.generate();
          final otherSchema = postgresUniverseSchema(other);
          final contender = await open();
          try {
            await contender.runTx((tx) async {
              await tx.execute('CREATE SCHEMA $otherSchema');
              for (final statement in [
                ...postgresBodySchema(other),
                ...postgresKernelSchema(other),
                ...postgresWorkflowSchema(other),
              ]) {
                await tx.execute(statement);
              }
              await PostgresJournal(tx, other).initialize(
                'Other workflow',
                ContinuityId.generate(),
                principal,
              );
            });
            await append(
              {'cancel:': null},
              [
                MapEntry('cancel:same', value({'cancelled': false})),
              ],
            );
            await connection.runTx((tx) async {
              final main = PostgresWorkflowStorage(tx, universe);
              await main.compare({'cancel:': 'cancel:same'});
              await contender.runTx((otherTx) async {
                await otherTx.execute("SET LOCAL lock_timeout='100ms'");
                final workflow = PostgresWorkflowStorage(otherTx, other);
                await workflow.compareAppend(
                  {'cancel:': null},
                  [
                    MapEntry('cancel:same', value({'cancelled': true})),
                  ],
                );
                expect(
                  (await workflow.evidence('cancel:same'))!.toText(),
                  value({'cancelled': true}).toText(),
                );
              });
              expect(
                (await main.evidence('cancel:same'))!.toText(),
                value({'cancelled': false}).toText(),
              );
            });
          } finally {
            await contender.execute(
              'DROP SCHEMA IF EXISTS $otherSchema CASCADE',
            );
            await contender.close();
          }
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
