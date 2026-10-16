@TestOn('vm')
library;

import 'helpers/universe_creation.dart' as creation;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/sqlite.dart' as local;
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  test(
    'reviewed SQLite PostgreSQL SQLite transfer above 512 MiB retains sources history and historical evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'universe-builder-large-transfer-',
      );
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
      local.OwnedSqliteDatabase? source;
      final universe = UniverseId.generate();
      final continuity = ContinuityId.generate(),
          branch = ContinuityId.generate();
      final principal = PrincipalId.generate(), profile = ProfileId.generate();
      const secret = 'disposable-large-transfer-profile';
      const count = 172;
      final body = 'A' * (3 * 1048576);
      final digests = <String>[];
      final cursor = CanonicalValue.parseJson(
        '{"binding":"large source review é😀","offset":0}',
      );
      Map<String, CanonicalValue> fields(CanonicalValue value) =>
          Map.fromEntries((value as CanonicalObject).fields);
      String text(CanonicalValue value, String name) =>
          wireString(fields(value)[name]!);
      EngineHello hello() => EngineHello(
        protocolVersion: protocolVersion,
        profileId: profile,
        credential: const Credential(secret),
        clientName: 'Disposable large transfer',
      );
      try {
        source = local.OwnedSqliteDatabase.create('${root.path}/source.sqlite');
        final kernel = local.SqliteKernel(source.database, universe);
        source.database.execute('BEGIN IMMEDIATE');
        kernel.journal.initialize(
          'Large source universe',
          continuity,
          principal,
        );
        final workflow = local.WorkflowStorage(source.database);
        workflow.put('cursor:retained', cursor);
        for (var i = 0; i < count; i++) {
          final content = '$i é😀\r\n$body';
          final digest = sha256.convert(utf8.encode(content)).toString();
          digests.add(digest);
          workflow.put('source:$digest', CanonicalString(content));
        }
        source.database.execute('COMMIT');
        creation.addFixtureRoot(source);
        final genesis = kernel.journal.head(continuity);
        final record = RecordId.generate();
        StoredVersion version(String label) => StoredVersion.build(
          RecordVersionId.generate(),
          RecordIdentity(
            universeId: universe,
            recordId: record,
            recordKind: RecordKind.entity,
          ),
          EntityRecord(
            names: const [],
            classificationResolution: ClassificationResolution.unclassified,
            worldAssociations: const [],
            labels: {'en': label},
            metadata: const {},
          ).toWire(),
        );
        final earlier = version('Earlier é😀'), later = version('Later');
        RevisionId commit(RevisionId head, String key, Assignment change) =>
            kernel.commit(
              CommitInput(
                universe: universe,
                continuity: continuity,
                expectedHead: head,
                principal: principal,
                decision: 'Disposable large transfer setup',
                reason: key,
                idempotencyKey: key,
                changes: [change],
              ),
            );
        final first = commit(
          genesis,
          'create',
          Assignment(recordId: record, next: earlier),
        );
        source.database.execute('BEGIN IMMEDIATE');
        final branchHead = kernel.journal.branch(
          branch,
          continuity,
          first,
          principal,
        );
        source.database.execute('COMMIT');
        final second = commit(
          first,
          'replace',
          Assignment(
            recordId: record,
            expected: earlier.versionId,
            next: later,
          ),
        );
        final head = commit(
          second,
          'tombstone',
          Assignment(recordId: record, expected: later.versionId, next: null),
        );
        final originalHeads = kernel.journal.heads();
        final archivePath = '${root.path}/archive.sqlite';
        source.exportCompleteHistory(archivePath);
        expect(File(archivePath).lengthSync(), greaterThan(512 * 1048576));
        print('Large retained source archive exported');
        store = await PostgresInstallationStore.create(
          endpoint,
          settings: settings,
        );
        await store.transaction(
          (s) => s.authority.enroll(
            id: profile,
            credentialHash: sha256.convert(utf8.encode(secret)).toString(),
          ),
        );
        runtime = NativePostgresRuntime(store: store);
        var author = await runtime.connect(hello());
        final preview = await author.execute(
          PreviewImportEngineRequest(
            source: archivePath,
            name: 'Large imported universe',
            mode: ImportMode.restore,
          ),
        );
        final accept = AcceptImportEngineRequest(
          previewId: OperationId.parse(text(preview, 'preview_id')),
          digest: text(preview, 'digest'),
        );
        final control = postgresAuthorityNamespace(store.instanceId);
        final retainedBytes = (await observer.execute(
          'SELECT sum(octet_length(content)),max(octet_length(content)),count(*) FROM $control.import_archive WHERE preview_id=\$1',
          parameters: [accept.previewId.value],
        )).single;
        expect(
          BigInt.parse(retainedBytes[0].toString()),
          BigInt.from(File(archivePath).lengthSync()),
        );
        expect(retainedBytes[1], lessThanOrEqualTo(262144));
        expect(retainedBytes[2] as int, greaterThan(2048));
        File(archivePath).deleteSync();
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint,
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello());
        print(
          'Large reviewed preview retained across restart and deleted input',
        );
        final receipt = await author.execute(accept);
        expect((await author.execute(accept)).toText(), receipt.toText());
        await store.transaction((s) async {
          final journal = s.kernel(universe).journal;
          expect(await journal.heads(), originalHeads);
          expect(await journal.head(continuity), head);
          expect(await journal.head(branch), branchHead);
          for (final row in [earlier, later]) {
            expect(
              (await journal.load(row.versionId)).toCanonical().toText(),
              row.toCanonical().toText(),
            );
          }
          expect(
            (await journal.snapshot(continuity, head)).containsKey(record),
            isFalse,
          );
          expect(
            (await journal.snapshot(branch, branchHead))[record],
            earlier.versionId,
          );
          expect(await s.workflows(universe).get('cursor:retained'), isNull);
          expect(
            (await s.workflows(universe).evidence('cursor:retained'))!.toText(),
            cursor.toText(),
          );
          for (var i = 0; i < count; i++) {
            final content =
                (await s.workflows(universe).evidence('source:${digests[i]}')
                        as CanonicalString)
                    .value;
            expect(content, '$i é😀\r\n$body');
            expect(sha256.convert(utf8.encode(content)).toString(), digests[i]);
          }
          await s.verifyUniverse(universe, complete: true);
        });
        print(
          'Large PostgreSQL admission and exact source/history checks passed',
        );
        final returnedPath = '${root.path}/returned.sqlite';
        await author.execute(
          ExportLogicalEngineRequest(
            universe: const Selector('Large imported universe'),
            destination: returnedPath,
            recordIds: const [],
            completeHistory: true,
          ),
        );
        expect(File(returnedPath).lengthSync(), greaterThan(512 * 1048576));
        final returned = local.OwnedSqliteDatabase.stageLogicalArchive(
          returnedPath,
          root.path,
        );
        try {
          final restored = returned.stageRestore(
            root.path,
            name: 'Large returned universe',
          );
          try {
            final journal = local.SqliteJournal(
              restored.package.database,
              universe,
            );
            expect(journal.heads(), originalHeads);
            for (final row in [earlier, later]) {
              expect(
                journal.load(row.versionId).toCanonical().toText(),
                row.toCanonical().toText(),
              );
            }
            final copied = local.WorkflowStorage(restored.package.database);
            expect(copied.get('cursor:retained'), isNull);
            expect(
              copied.evidence('cursor:retained')!.toText(),
              cursor.toText(),
            );
            for (var i = 0; i < count; i++) {
              final content = (copied.evidence(
                'source:${digests[i]}',
              ) as CanonicalString).value;
              expect(content, '$i é😀\r\n$body');
              expect(
                sha256.convert(utf8.encode(content)).toString(),
                digests[i],
              );
            }
          } finally {
            restored.close();
          }
        } finally {
          returned.close();
        }
        expect(kernel.journal.heads(), originalHeads);
        for (var i = 0; i < count; i++) {
          expect(
            (workflow.evidence(
              'source:${digests[i]}',
            ) as CanonicalString).value,
            '$i é😀\r\n$body',
          );
        }
      } finally {
        await runtime?.close();
        await store?.close();
        source?.close();
        try {
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
          );
          if (store != null) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
            );
          }
        } finally {
          await observer.close();
          root.deleteSync(recursive: true);
        }
      }
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
