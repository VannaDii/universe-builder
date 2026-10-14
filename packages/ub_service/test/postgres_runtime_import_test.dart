@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/sqlite.dart' as local;
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL reviewed import dispatch',
    () {
      late Directory directory;
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late ProfileId authorId, writerId;
      final targets = <UniverseId>[];
      var opened = false, started = false;
      const secret = 'disposable-import-profile';
      const sourceText = '\uFEFFResearch é😀\u0000 exact bytes';
      final sourceDigest = sha256.convert(utf8.encode(sourceText)).toString();
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
        clientName: 'Disposable import client',
      );
      String getControl() => postgresAuthorityNamespace(store.instanceId);
      Future<bool> exists(UniverseId id) async =>
          (await observer.execute(
                'SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname=\$1)',
                parameters: ['ub_${id.value}'],
              )).single.single
              as bool;
      Map<String, CanonicalValue> fields(CanonicalValue value) =>
          Map.fromEntries((value as CanonicalObject).fields);
      String text(CanonicalValue value, String key) =>
          wireString(fields(value)[key]!);
      AcceptImportEngineRequest accept(CanonicalValue report) =>
          AcceptImportEngineRequest(
            previewId: OperationId.parse(text(report, 'preview_id')),
            digest: text(report, 'digest'),
          );
      String source({bool canonOnly = false, bool large = false}) {
        final path = '${directory.path}/${OperationId.generate().value}.sqlite';
        final package = local.OwnedSqliteDatabase.create(
          '${directory.path}/${OperationId.generate().value}.sqlite',
        );
        try {
          package.database.execute('BEGIN IMMEDIATE');
          local.SqliteJournal(
            package.database,
            UniverseId.generate(),
          ).initialize(
            'Original',
            ContinuityId.generate(),
            PrincipalId.generate(),
          );
          local.WorkflowStorage(package.database).put(
            'cursor:old',
            CanonicalValue.parseJson(
              '{"binding":"original binding","offset":0}',
            ),
          );
          local.WorkflowStorage(package.database)
              .put('source:$sourceDigest', CanonicalString(sourceText));
          if (large) {
            final body = List.filled(50000, 'é😀\r\n').join();
            local.WorkflowStorage(package.database).put(
              'source:${sha256.convert(utf8.encode(body))}',
              CanonicalString(body),
            );
          }
          package.database.execute('COMMIT');
          if (canonOnly) {
            package.exportLogical(path);
          } else {
            package.exportCompleteHistory(path);
          }
          return path;
        } finally {
          package.close();
        }
      }

      Future<CanonicalValue> preview(
        NativePostgresConnection connection,
        String path,
        String name,
      ) async {
        final report = await connection.execute(
          PreviewImportEngineRequest(
            source: path,
            name: name,
            mode: ImportMode.clone,
          ),
        );
        targets.add(UniverseId.parse(text(report, 'target_universe')));
        return report;
      }

      setUp(() async {
        targets.clear();
        opened = false;
        started = false;
        directory = Directory.systemTemp.createTempSync(
          'universe-builder-import-dispatch-',
        );
        observer = await Connection.open(endpoint(), settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: settings,
        );
        opened = true;
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
        started = true;
      });
      tearDown(() async {
        if (started) await runtime.close();
        if (opened) await store.close();
        try {
          for (final target in targets) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(target)} CASCADE',
            );
          }
          if (opened) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${getControl()} CASCADE',
            );
          }
        } finally {
          await observer.close();
          directory.deleteSync(recursive: true);
        }
      });

      test('caller-selected file review identity retries the same binding without admission', () async {
        final author = await runtime.connect(hello(authorId));
        final path = source();
        final id = OperationId.generate();
        final request = PreviewImportEngineRequest(
          source: path,
          name: 'Selected file 記憶',
          mode: ImportMode.clone,
          previewId: id,
        );
        final report = await author.execute(request);
        targets.add(UniverseId.parse(text(report, 'target_universe')));
        expect(text(report, 'preview_id'), id.value);
        expect((await author.execute(request)).toText(), report.toText());
        await expectLater(
          author.execute(
            PreviewImportEngineRequest(
              source: path,
              name: 'Changed name',
              mode: ImportMode.clone,
              previewId: id,
            ),
          ),
          throwsA(isA<ApprovalStaleError>()),
        );
        final status = fields(await author.execute(StatusEngineRequest()));
        expect((status['universes']! as CanonicalArray).items, isEmpty);
      });

      test('bounded uploaded archive survives restart and exact review and admission retries', () async {
        var author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final path = source(large: true);
        final archive = local.OwnedSqliteDatabase.stageLogicalArchive(
          path,
          directory.path,
        );
        late String digest;
        try {
          digest = archive.digest;
        } finally {
          archive.close();
        }
        final begin = BeginArchiveUploadEngineRequest(
          uploadId: OperationId.generate(),
          digest: digest,
          bytes: File(path).lengthSync(),
        );
        final review = ReviewArchiveUploadEngineRequest(
          uploadId: begin.uploadId,
          name: 'Uploaded target é😀',
          mode: ImportMode.restore,
        );
        await expectLater(
          writer.execute(begin),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await author.execute(EngineRequest.decode(begin.toWire().toBytes()));
        await expectLater(author.execute(review), throwsFormatException);
        await expectLater(
          author.execute(
            BeginArchiveUploadEngineRequest(
              uploadId: begin.uploadId,
              digest: '0' * 64,
              bytes: begin.bytes,
            ),
          ),
          throwsFormatException,
        );
        final input = File(path).openSync();
        var ordinal = 0, received = 0;
        try {
          while (received < begin.bytes) {
            final chunk = MoveArchiveChunk(
              ordinal: ordinal,
              content: input.readSync(ReadMoveChunkEngineRequest.chunkBytes),
            );
            final request = WriteArchiveChunkEngineRequest(
              uploadId: begin.uploadId,
              chunk: chunk,
            );
            if (ordinal == 0) {
              await expectLater(
                writer.execute(request),
                throwsA(isA<NotFoundOrNotAccessibleError>()),
              );
              await expectLater(
                author.execute(
                  WriteArchiveChunkEngineRequest(
                    uploadId: begin.uploadId,
                    chunk: MoveArchiveChunk(ordinal: 1, content: chunk.content),
                  ),
                ),
                throwsFormatException,
              );
            }
            final progress = await author.execute(
              EngineRequest.decode(request.toWire().toBytes()),
            );
            expect((await author.execute(request)).toText(), progress.toText());
            received += chunk.content.length;
            ordinal++;
            if (ordinal == 1) {
              final changed = Uint8List.fromList(chunk.content)..[0] ^= 1;
              await expectLater(
                author.execute(
                  WriteArchiveChunkEngineRequest(
                    uploadId: begin.uploadId,
                    chunk: MoveArchiveChunk(ordinal: 0, content: changed),
                  ),
                ),
                throwsFormatException,
              );
              await runtime.close();
              await store.close();
              store = await PostgresInstallationStore.openExisting(
                endpoint(),
                settings: settings,
              );
              runtime = NativePostgresRuntime(store: store);
              author = await runtime.connect(hello(authorId));
              expect((await author.execute(begin)).toText(), progress.toText());
            }
          }
        } finally {
          input.closeSync();
        }
        expect(ordinal, greaterThan(1));
        File(path).deleteSync();
        await observer.execute(
          'UPDATE ${getControl()}.archive_upload SET source_digest=\$1 WHERE id=\$2',
          parameters: ['0' * 64, begin.uploadId.value],
        );
        await expectLater(
          author.execute(review),
          throwsA(isA<ApprovalStaleError>()),
        );
        expect(
          (await observer.execute(
            'SELECT count(*) FROM ${getControl()}.import_preview',
          )).single.single,
          0,
        );
        await observer.execute(
          'UPDATE ${getControl()}.archive_upload SET source_digest=\$1 WHERE id=\$2',
          parameters: [digest, begin.uploadId.value],
        );
        final report = await author.execute(review);
        final target = UniverseId.parse(text(report, 'target_universe'));
        targets.add(target);
        expect(text(report, 'preview_id'), begin.uploadId.value);
        expect((await author.execute(review)).toText(), report.toText());
        await expectLater(
          author.execute(
            ReviewArchiveUploadEngineRequest(
              uploadId: begin.uploadId,
              name: 'Changed',
              mode: ImportMode.restore,
            ),
          ),
          throwsFormatException,
        );
        final contributor = await runtime.connect(hello(writerId));
        await expectLater(
          contributor.execute(review),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect((await author.execute(review)).toText(), report.toText());
        final receipt = await author.execute(accept(report));
        expect(
          (await author.execute(accept(report))).toText(),
          receipt.toText(),
        );
        expect(
          (await store.transaction(
            (s) => s.workflows(target).get('source:$sourceDigest'),
          ))?.toText(),
          CanonicalString(sourceText).toText(),
        );
      });

      test('complete and canon-only exact previews survive deleted input and service restart with durable admission retries', () async {
        for (final canonOnly in [false, true]) {
          final path = source(canonOnly: canonOnly);
          var author = await runtime.connect(hello(authorId));
          final report = await preview(author, path, 'Imported $canonOnly');
          expect((fields(report)['canonical'] as CanonicalBool).value, isFalse);
          expect(
            (fields(report)['includes_workflow'] as CanonicalBool).value,
            !canonOnly,
          );
          expect(
            (fields(report)['conflicts'] as CanonicalArray).items,
            isEmpty,
          );
          final request = accept(report);
          final target = UniverseId.parse(text(report, 'target_universe'));
          expect(await exists(target), isFalse);
          final chunks = await observer.execute(
            'SELECT content FROM ${getControl()}.import_archive WHERE preview_id=\$1 ORDER BY ordinal',
            parameters: [request.previewId.value],
          );
          expect(chunks.length, greaterThan(1));
          expect(
            chunks.expand((row) => row.single as List<int>).toList(),
            orderedEquals(File(path).readAsBytesSync()),
          );
          File(path).deleteSync();
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          author = await runtime.connect(hello(authorId));
          final receipt = await author.execute(request);
          expect((await author.execute(request)).toText(), receipt.toText());
          await store.transaction((session) async {
            await session.verifyUniverse(target, complete: true);
            expect(await session.workflows(target).get('cursor:old'), isNull);
            expect(
              await session.workflows(target).evidence('cursor:old'),
              canonOnly ? isNull : isNotNull,
            );
            expect(
              await session.workflows(target).evidence('source:$sourceDigest'),
              canonOnly
                  ? isNull
                  : isA<CanonicalString>().having(
                      (value) => value.value,
                      'exact bytes',
                      sourceText,
                    ),
            );
          });
          await author.execute(
            LibraryEngineRequest(universe: Selector('Imported $canonOnly')),
          );
          // A lost receipt can be retried after the universe is subsequently renamed.
          await author.execute(
            RenameUniverseEngineRequest(
              universeId: target,
              name: 'Renamed $canonOnly',
            ),
          );
          expect((await author.execute(request)).toText(), receipt.toText());
        }
      });

      test('current author permissions stale digests and historical aliases govern admission', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            const PreviewImportEngineRequest(
              source: '/absent/disposable.sqlite',
              name: 'Denied',
              mode: ImportMode.clone,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(
          (await observer.execute(
            'SELECT count(*) FROM ${getControl()}.import_preview',
          )).single.single,
          0,
        );
        final path = source();
        final report = await preview(author, path, 'Reserved name');
        final request = accept(report);
        await expectLater(
          author.execute(
            AcceptImportEngineRequest(
              previewId: request.previewId,
              digest: '0' * 64,
            ),
          ),
          throwsA(isA<ApprovalStaleError>()),
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await author.execute(request);
        final second = await preview(author, path, 'Reserved name');
        expect(
          (fields(second)['conflicts'] as CanonicalArray).items,
          hasLength(1),
        );
        final target = UniverseId.parse(text(report, 'target_universe'));
        await author.execute(
          RenameUniverseEngineRequest(universeId: target, name: 'Moved name'),
        );
        await expectLater(
          author.execute(accept(second)),
          throwsA(isA<NameUnavailableError>()),
        );
        expect(
          await exists(UniverseId.parse(text(second, 'target_universe'))),
          isFalse,
        );
        await expectLater(
          author.execute(
            AcceptImportEngineRequest(
              previewId: OperationId.generate(),
              digest: request.digest,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });

      test('altered reviewed chunks and interrupted acceptance leave no target and permit an exact retry', () async {
        final author = await runtime.connect(hello(authorId));
        final report = await preview(author, source(), 'Recovered import');
        final request = accept(report);
        final target = UniverseId.parse(text(report, 'target_universe'));
        final row = (await observer.execute(
          'SELECT ordinal,content FROM ${getControl()}.import_archive WHERE preview_id=\$1 ORDER BY ordinal LIMIT 1',
          parameters: [request.previewId.value],
        )).single;
        final original = row[1] as List<int>;
        final damaged = Uint8List.fromList(original);
        damaged[0] ^= 1;
        await observer.execute(
          'UPDATE ${getControl()}.import_archive SET content=\$1 WHERE preview_id=\$2 AND ordinal=\$3',
          parameters: [damaged, request.previewId.value, row[0]],
        );
        await expectLater(author.execute(request), throwsA(isA<Exception>()));
        expect(await exists(target), isFalse);
        await observer.execute(
          'UPDATE ${getControl()}.import_archive SET content=\$1 WHERE preview_id=\$2 AND ordinal=\$3',
          parameters: [original, request.previewId.value, row[0]],
        );
        await expectLater(
          store.transaction((session) async {
            await session.acceptImport(
              actor: authorId,
              id: request.previewId,
              digest: request.digest,
            );
            throw StateError('disposable interruption before outer commit');
          }),
          throwsStateError,
        );
        expect(await exists(target), isFalse);
        final receipt = await author.execute(request);
        expect((await author.execute(request)).toText(), receipt.toText());
      });

      test('preview metadata and archive chunk gaps are rejected before registration', () async {
        final author = await runtime.connect(hello(authorId));
        final report = await preview(author, source(), 'Exact review name');
        final request = accept(report);
        final target = UniverseId.parse(text(report, 'target_universe'));
        await observer.execute(
          'UPDATE ${getControl()}.import_preview SET name=\$1 WHERE id=\$2',
          parameters: [
            postgresAuthoredText('Changed name'),
            request.previewId.value,
          ],
        );
        await expectLater(author.execute(request), throwsFormatException);
        expect(await exists(target), isFalse);
        await observer.execute(
          'UPDATE ${getControl()}.import_preview SET name=\$1 WHERE id=\$2',
          parameters: [
            postgresAuthoredText('Exact review name'),
            request.previewId.value,
          ],
        );
        await observer.execute(
          'UPDATE ${getControl()}.import_archive SET ordinal=100000 WHERE preview_id=\$1 AND ordinal=1',
          parameters: [request.previewId.value],
        );
        await expectLater(author.execute(request), throwsFormatException);
        expect(await exists(target), isFalse);
        await observer.execute(
          'UPDATE ${getControl()}.import_archive SET ordinal=1 WHERE preview_id=\$1 AND ordinal=100000',
          parameters: [request.previewId.value],
        );
        await author.execute(request);
      });

      test('opening refuses an incomplete durable import layout', () async {
        await runtime.close();
        await store.close();
        await observer.execute('DROP TABLE ${getControl()}.import_archive');
        await expectLater(
          PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          ),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.incompatibleSchema,
            ),
          ),
        );
      });

      test(
        'another import cannot claim an already registered identity',
        () async {
          final author = await runtime.connect(hello(authorId));
          final report = await preview(author, source(), 'Owned import');
          final request = accept(report);
          final target = UniverseId.parse(text(report, 'target_universe'));
          await author.execute(request);
          final export = '${directory.path}/accepted.sqlite';
          await author.execute(
            ExportLogicalEngineRequest(
              universe: const Selector('Owned import'),
              destination: export,
              recordIds: [],
              completeHistory: true,
            ),
          );
          final restored = await author.execute(
            PreviewImportEngineRequest(
              source: export,
              name: 'Competing identity',
              mode: ImportMode.restore,
            ),
          );
          expect(text(restored, 'target_universe'), target.value);
          await expectLater(
            author.execute(accept(restored)),
            throwsA(isA<PolicyDeniedError>()),
          );
          expect(
            (await author.execute(request)).toText(),
            (await store.transaction(
              (session) => session.loadImport(
                actor: authorId,
                id: request.previewId,
                digest: request.digest,
              ),
            )).receipt.toText(),
          );
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}
