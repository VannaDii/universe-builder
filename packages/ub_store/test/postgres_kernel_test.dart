@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/src/kernel.dart' show CommitFaultPoint;
import 'package:ub_store/src/media_decode.dart';
import 'package:ub_store/src/postgres_authority.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_kernel.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_projection_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_semantic_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/postgres_workflow_schema.dart';
import 'package:ub_store/src/postgres_workflow_storage.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  final universe = UniverseId.generate(),
      continuity = ContinuityId.generate(),
      principal = PrincipalId.generate();
  final record = RecordId.generate();
  final schema = postgresUniverseSchema(universe);
  late Connection connection;
  late RevisionId genesis;
  late OperationId instance;
  late ProfileId author, writer;
  late String control;
  Future<Connection> connect() => Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: port!,
      database: 'ub_disposable',
      username: 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  StoredVersion entity({RecordId? classification}) => StoredVersion.build(
    RecordVersionId.generate(),
    RecordIdentity(
      universeId: universe,
      recordId: record,
      recordKind: RecordKind.entity,
    ),
    EntityRecord(
      names: [],
      classification: classification,
      classificationResolution: classification == null
          ? ClassificationResolution.unclassified
          : ClassificationResolution.resolved,
      worldAssociations: [],
      labels: {'en': 'Disposable cedar'},
      metadata: {},
    ).toWire(),
  );
  CommitInput input(
    String key,
    StoredVersion next, {
    RevisionId? head,
    RecordVersionId? expected,
  }) => CommitInput(
    universe: universe,
    continuity: continuity,
    expectedHead: head ?? genesis,
    principal: principal,
    decision: 'Already admitted disposable input',
    reason: 'Kernel checks',
    idempotencyKey: key,
    changes: [Assignment(recordId: record, expected: expected, next: next)],
  );
  Future<RevisionId> publish(
    CommitInput input, {
    Map<String, String?> expectedWorkflow = const {},
    FutureOr<void> Function(CommitFaultPoint)? hook,
  }) => connection.runTx((tx) async {
    await PostgresInstallationAuthority(tx, instance).requireAuthor(author);
    return PostgresKernel(
      tx,
      universe,
    ).commit(input, expectedWorkflow: expectedWorkflow, hook: hook);
  });
  Future<List<StoredVersion>> preview(CommitInput input) =>
      connection.runTx((tx) async {
        await PostgresInstallationAuthority(tx, instance).requireAuthor(author);
        return PostgresKernel(tx, universe).preview(input);
      });
  Future<Map<String, int>> sizes() async => {
    for (final table in [
      'record_identities',
      'record_versions',
      'commits',
      'commit_changes',
      'operation_receipts',
      'type_definition',
      'instance_classification',
      'initialization_receipt',
      'reference_index',
      'typed_projection',
      'search_index',
    ])
      table:
          (await connection.execute('SELECT count(*) FROM $schema.$table'))
                  .single
                  .single
              as int,
  };
  group(
    'PostgreSQL transaction coordinator',
    () {
      setUp(() async {
        connection = await connect();
        instance = OperationId.generate();
        author = ProfileId.generate();
        writer = ProfileId.generate();
        control = postgresAuthorityNamespace(instance);
        genesis = await connection.runTx((tx) async {
          for (final sql in postgresAuthoritySchema(instance)) {
            await tx.execute(sql);
          }
          final authority = PostgresInstallationAuthority(tx, instance);
          await authority.enroll(id: author, credentialHash: '0' * 64);
          await authority.enroll(
            id: writer,
            credentialHash: '1' * 64,
            actor: author,
          );
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
          final base = await PostgresKernel(
            tx,
            universe,
          ).journal.initialize('Disposable kernel', continuity, principal);
          await authority.registerUniverse(
            actor: author,
            universe: universe,
            name: 'Disposable kernel',
          );
          await authority.putGrant(
            actor: author,
            grant: GrantSpec(
              profileId: writer,
              universeId: universe,
              propose: true,
              edit: true,
              protected: false,
            ),
            epochSeconds: BigInt.one,
          );
          return base;
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $control CASCADE');
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });

      test('all commit checkpoints roll back history, definitions, projections and receipt', () async {
        final before = await sizes();
        for (final fault in CommitFaultPoint.values) {
          final seen = <CommitFaultPoint>[];
          await expectLater(
            publish(
              input('fault-${fault.name}', entity()),
              hook: (point) {
                seen.add(point);
                if (point == fault) {
                  throw StateError('Interrupted ${point.name}');
                }
              },
            ),
            throwsStateError,
          );
          expect(seen.last, fault);
          expect(await sizes(), before);
          await connection.runTx((tx) async {
            expect(
              await PostgresKernel(tx, universe).journal.head(continuity),
              genesis,
            );
          });
        }
      });

      test('exact retry precedes stale workflow and head; changed content conflicts after reconnect', () async {
        final request = input('durable', entity());
        final revision = await publish(request);
        final next = entity();
        await publish(
          input(
            'advance',
            next,
            head: revision,
            expected: request.changes.single.next!.versionId,
          ),
        );
        final before = await sizes();
        await connection.close();
        connection = await connect();
        expect(
          await publish(
            request,
            expectedWorkflow: {'reserved-record:${record.value}': 'missing'},
          ),
          revision,
        );
        expect(await sizes(), before);
        await expectLater(
          publish(input('durable', entity())),
          throwsFormatException,
        );
        expect(await sizes(), before);
      });

      test(
        'workflow comparison rejects stale capture before staging',
        () async {
          final key = 'reserved-record:${record.value}';
          final value = CanonicalObject([
            MapEntry(
              'proposal_id',
              CanonicalString(ProposalId.generate().value),
            ),
          ]);
          await connection.runTx(
            (tx) => PostgresWorkflowStorage(
              tx,
              universe,
            ).compareAppend({}, [MapEntry(key, value)]),
          );
          final before = await sizes();
          final request = input('stale', entity());
          await expectLater(
            publish(request, expectedWorkflow: {key: null}),
            throwsFormatException,
          );
          expect(await sizes(), before);
          expect(
            await publish(request, expectedWorkflow: {key: key}),
            isA<RevisionId>(),
          );
        },
      );

      test('preview runs all gates but leaves no history, identity or receipt', () async {
        final before = await sizes();
        final valid = input('preview', entity());
        expect(
          (await preview(valid)).single.digest,
          valid.changes.single.next!.digest,
        );
        expect(await sizes(), before);
        await expectLater(
          preview(
            input('missing-type', entity(classification: RecordId.generate())),
          ),
          throwsFormatException,
        );
        expect(await sizes(), before);
        // Savepoint recovery leaves the outer transaction usable after rejected
        // preview, while the real commit remains under the same authority lock.
        final revision = await connection.runTx((tx) async {
          await PostgresInstallationAuthority(
            tx,
            instance,
          ).requireAuthor(author);
          final kernel = PostgresKernel(tx, universe);
          await expectLater(
            kernel.preview(
              input('bad', entity(classification: RecordId.generate())),
            ),
            throwsFormatException,
          );
          return kernel.commit(valid);
        });
        expect(await publish(valid), revision);
        final original = valid.changes.single.next!;
        final replacement = entity();
        final reusedVersion = StoredVersion.build(
          original.versionId,
          replacement.identity,
          replacement.payload,
        );
        final retained = await sizes();
        await connection.runTx((tx) async {
          await PostgresInstallationAuthority(
            tx,
            instance,
          ).requireAuthor(author);
          final kernel = PostgresKernel(tx, universe);
          await expectLater(
            kernel.preview(
              input(
                'sql-error',
                reusedVersion,
                head: revision,
                expected: original.versionId,
              ),
            ),
            throwsA(
              isA<ServerException>().having(
                (e) => e.code,
                'duplicate stored version',
                '23505',
              ),
            ),
          );
          expect(await kernel.commit(valid), revision);
        });
        expect(await sizes(), retained);
      });

      test(
        'commit and preview validate retained decoded image bytes',
        () async {
          final missing = ImageAssetRecord(
            contentDigest: '0' * 64,
            mediaType: 'image/png',
            byteSize: BigInt.one,
            width: 1,
            height: 1,
            originalName: 'disposable.png',
          );
          StoredVersion stored(ImageAssetRecord asset) => StoredVersion.build(
            RecordVersionId.generate(),
            RecordIdentity(
              universeId: universe,
              recordId: record,
              recordKind: RecordKind.imageAsset,
            ),
            asset.toWire(),
          );
          final absent = input('absent-image', stored(missing));
          final before = await sizes();
          await expectLater(preview(absent), throwsFormatException);
          await expectLater(publish(absent), throwsFormatException);
          expect(await sizes(), before);
          final bytes = img.encodePng(img.Image(width: 3, height: 2));
          final asset = inspectImageBytes(bytes, 'disposable.png');
          await connection.runTx(
            (tx) => PostgresWorkflowStorage(tx, universe).compareAppend({}, [
              MapEntry('image-asset:${record.value}', asset.toWire()),
              MapEntry(
                'image-bytes:${asset.contentDigest}:0',
                CanonicalString(base64.encode(bytes)),
              ),
            ]),
          );
          final valid = input('decoded-image', stored(asset));
          expect(
            (await preview(valid)).single.versionId,
            valid.changes.single.next!.versionId,
          );
          expect(await sizes(), before);
          final revision = await publish(valid);
          final wrong = ImageAssetRecord(
            contentDigest: asset.contentDigest,
            mediaType: asset.mediaType,
            byteSize: asset.byteSize,
            width: 4,
            height: 2,
            originalName: asset.originalName,
          );
          final correction = input(
            'wrong-metadata',
            stored(wrong),
            head: revision,
            expected: valid.changes.single.next!.versionId,
          );
          final admitted = await sizes();
          await expectLater(preview(correction), throwsFormatException);
          await expectLater(publish(correction), throwsFormatException);
          expect(await sizes(), admitted);
        },
      );

      test('authority remains locked through awaited publication; revoked retries are denied', () async {
        final other = await connect();
        final entered = Completer<void>(), release = Completer<void>();
        final request = input('guarded', entity());
        Future<void> authorize(PostgresInstallationAuthority authority) =>
            authority.authorizeWrite(
              profile: writer,
              universe: universe,
              worlds: {},
              shared: true,
              protected: false,
              commit: true,
              epochSeconds: BigInt.one,
            );
        final running = connection.runTx((tx) async {
          await authorize(PostgresInstallationAuthority(tx, instance));
          return PostgresKernel(tx, universe).commit(
            request,
            hook: (point) async {
              if (point == CommitFaultPoint.beforeCommit) {
                entered.complete();
                await release.future;
              }
            },
          );
        });
        try {
          await entered.future;
          await expectLater(
            other.runTx((tx) async {
              await tx.execute("SET LOCAL lock_timeout='100ms'");
              await PostgresInstallationAuthority(
                tx,
                instance,
              ).revoke(actor: author, target: writer);
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
        }
        final revision = await running;
        try {
          await other.runTx(
            (tx) => PostgresInstallationAuthority(
              tx,
              instance,
            ).revoke(actor: author, target: writer),
          );
          await expectLater(
            connection.runTx((tx) async {
              await authorize(PostgresInstallationAuthority(tx, instance));
              return PostgresKernel(tx, universe).commit(request);
            }),
            throwsA(
              isA<InstallationException>().having(
                (e) => e.failure,
                'current revocation',
                InstallationFailure.denied,
              ),
            ),
          );
          expect(
            await connection.runTx(
              (tx) => PostgresKernel(tx, universe).journal.receipt(request),
            ),
            revision,
          );
        } finally {
          await other.close();
        }
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
