@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_client/archive_transfer.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/loopback_engine.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_service/sqlite_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL durable source move quiescence',
    () {
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late ProfileId authorId, writerId;
      final universes = <UniverseId>[];
      const secret = 'disposable-move-profile';
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
        credential: const Credential(secret),
        clientName: 'Disposable source move',
      );
      String text(CanonicalValue v, String key) =>
          wireString(Map.fromEntries((v as CanonicalObject).fields)[key]!);
      Future<CanonicalValue> create(
        NativePostgresConnection author,
        String name,
      ) async {
        final result = await author.execute(
          CreateUniverseEngineRequest(
            name: name,
            start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        );
        universes.add(UniverseId.parse(text(result, 'universe_id')));
        return result;
      }

      Future<void> quiesce(
        ProfileId actor,
        UniverseId universe,
        OperationId operation,
        OperationId target,
      ) => store.transaction((s) async {
        final authority = PostgresServiceAuthority(s.authority);
        final principal = await authority.authenticate(
          profile: actor,
          credential: const Credential(secret),
        );
        await authority.quiesceUniverseForMove(
          principal,
          universe: universe,
          operation: operation,
          targetInstance: target,
        );
      });
      setUp(() async {
        universes.clear();
        observer = await Connection.open(endpoint(), settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: settings,
        );
        authorId = ProfileId.generate();
        writerId = ProfileId.generate();
        await store.transaction((s) async {
          final hash = sha256.convert(utf8.encode(secret)).toString();
          await s.authority.enroll(id: authorId, credentialHash: hash);
          await s.authority.enroll(
            id: writerId,
            credentialHash: hash,
            actor: authorId,
          );
        });
        runtime = NativePostgresRuntime(store: store);
      });
      tearDown(() async {
        await runtime.close();
        await store.close();
        try {
          for (final universe in universes) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
            );
          }
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
        }
      });
      test('committed source guard blocks connected author and peer while retaining original grants aliases and data through restart', () async {
        var author = await runtime.connect(hello(authorId));
        final source = await create(author, 'Move source');
        final other = await create(author, 'Other universe');
        final universe = UniverseId.parse(text(source, 'universe_id'));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Renamed source',
          ),
        );
        final peerStore = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        final peerRuntime = NativePostgresRuntime(store: peerStore);
        try {
          final peer = await peerRuntime.connect(hello(authorId));
          final writer = await peerRuntime.connect(hello(writerId));
          expect(
            textArray(
              await writer.execute(const StatusEngineRequest()),
              'universes',
            ),
            hasLength(1),
          );
          SaveDraftEngineRequest save(CanonicalValue row, String name) =>
              SaveDraftEngineRequest(
                universe: Selector(name),
                continuityId: ContinuityId.parse(text(row, 'continuity_id')),
                expectedVersion: BigInt.zero,
                content: DraftContent(
                  baseRevision: RevisionId.parse(text(row, 'revision')),
                  representedContext: RecordId.parse(text(row, 'context_id')),
                  operations: const [],
                  rationale: 'Exact retained draft é😀',
                  proposal: null,
                ),
              );
          final request = save(source, 'Move source');
          final draft = await peer.execute(request);
          final operation = OperationId.generate(),
              target = OperationId.generate();
          await quiesce(authorId, universe, operation, target);
          await quiesce(authorId, universe, operation, target);
          for (final connection in [author, peer]) {
            await expectLater(
              connection.execute(request),
              throwsA(isA<NotFoundOrNotAccessibleError>()),
            );
          }
          final hidden = textArray(
            await writer.execute(const StatusEngineRequest()),
            'universes',
          );
          expect(hidden, isEmpty);
          await expectLater(
            quiesce(
              authorId,
              UniverseId.parse(text(other, 'universe_id')),
              operation,
              target,
            ),
            throwsFormatException,
          );
          await author.execute(save(other, 'Other universe'));
          final control = postgresAuthorityNamespace(store.instanceId);
          expect(
            (await observer.execute(
              'SELECT count(*) FROM $control.catalog WHERE id=\$1',
              parameters: [universe.value],
            )).single.single,
            1,
          );
          expect(
            (await observer.execute(
              'SELECT count(*) FROM $control.aliases WHERE universe=\$1',
              parameters: [universe.value],
            )).single.single,
            2,
          );
          expect(
            (await observer.execute(
              'SELECT count(*) FROM $control.grants WHERE universe=\$1',
              parameters: [universe.value],
            )).single.single,
            1,
          );
          expect(
            (await observer.execute(
              "SELECT count(*) FROM $control.audit WHERE action='quiesce_move'",
            )).single.single,
            1,
          );
          await store.transaction((s) async {
            expect(
              await s
                  .kernel(universe)
                  .journal
                  .head(ContinuityId.parse(text(source, 'continuity_id'))),
              RevisionId.parse(text(source, 'revision')),
            );
            final keys = await s
                .workflows(universe)
                .keys('draft:${authorId.value}:');
            expect(keys, hasLength(1));
            expect(
              (await s.workflows(universe).get(keys.single))!.toText(),
              draft.toText(),
            );
            await s.verifyUniverse(universe, complete: true);
          });
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          author = await runtime.connect(hello(authorId));
          await expectLater(
            author.execute(request),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          await expectLater(
            quiesce(authorId, universe, OperationId.generate(), target),
            throwsFormatException,
          );
          await expectLater(
            quiesce(authorId, universe, operation, OperationId.generate()),
            throwsFormatException,
          );
        } finally {
          await peerRuntime.close();
          await peerStore.close();
        }
      });
      test('retained SQLite move stage admits PostgreSQL after restart and recovers lost target response', () async {
        final root = Directory.systemTemp.createTempSync(
          'universe-builder-source-move-',
        );
        var sourceStore = SqliteInstallationStore.create(root.path);
        var sourceAuthority = InstallationAuthority(sourceStore);
        final sourceAuthor = sourceAuthority.initializeAuthor();
        EngineHello sourceHello() => EngineHello(
          protocolVersion: protocolVersion,
          profileId: sourceAuthor,
          credential: Credential(
            ProfileCredentialStore.read(root: root.path, profile: sourceAuthor),
          ),
          clientName: 'Disposable source move',
        );
        var sourceRuntime = NativeSqliteRuntime(authority: sourceAuthority);
        try {
          final client = sourceRuntime.connect(sourceHello());
          final created = await client.execute(
            CreateUniverseEngineRequest(
              name: 'SQLite original',
              start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          );
          final universe = UniverseId.parse(text(created, 'universe_id'));
          universes.add(universe);
          final operation = OperationId.generate();
          final draft = await client.execute(
            SaveDraftEngineRequest(
              universe: const Selector('SQLite original'),
              continuityId: ContinuityId.parse(text(created, 'continuity_id')),
              expectedVersion: BigInt.zero,
              content: DraftContent(
                baseRevision: RevisionId.parse(text(created, 'revision')),
                representedContext: RecordId.parse(text(created, 'context_id')),
                operations: const [],
                rationale: 'Retained move draft é😀',
                proposal: null,
              ),
            ),
          );
          final stage = await sourceRuntime.stageSourceMove(
            sourceAuthority.authenticateHello(sourceHello()),
            universe: universe,
            operation: operation,
            targetInstance: store.instanceId,
          );
          final originalBytes = File(stage.path).readAsBytesSync();
          final target = await runtime.connect(hello(authorId));
          final preview = await target.execute(
            PreviewImportEngineRequest(
              source: stage.path,
              name: 'Moved to PostgreSQL',
              mode: ImportMode.restore,
            ),
          );
          final targetReview = InstallationImportPreview.fromCanonical(
            await target.execute(
              GetImportEngineRequest(
                previewId: OperationId.parse(text(preview, 'preview_id')),
                digest: text(preview, 'digest'),
              ),
            ),
          );
          final sourcePrincipal = sourceAuthority.authenticateHello(
            sourceHello(),
          );
          await sourceAuthority.reviewMoveTarget(
            sourcePrincipal,
            universe: universe,
            operation: operation,
            targetInstance: store.instanceId,
            preview: targetReview,
          );
          await sourceAuthority.beginMoveAdmission(
            sourcePrincipal,
            universe: universe,
            operation: operation,
            targetInstance: store.instanceId,
          );
          await sourceRuntime.close();
          sourceStore.close();
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          sourceStore = SqliteInstallationStore.openExisting(root.path);
          sourceAuthority = InstallationAuthority(sourceStore);
          sourceRuntime = NativeSqliteRuntime(authority: sourceAuthority);
          final recovered = await sourceRuntime.stageSourceMove(
            sourceAuthority.authenticateHello(sourceHello()),
            universe: universe,
            operation: operation,
            targetInstance: store.instanceId,
          );
          expect(recovered.digest, stage.digest);
          expect(File(recovered.path).readAsBytesSync(), originalBytes);
          final reconnected = await runtime.connect(hello(authorId));
          final accept = AcceptImportEngineRequest(
            previewId: OperationId.parse(text(preview, 'preview_id')),
            digest: text(preview, 'digest'),
          );
          final pending = await sourceAuthority.loadMoveReview(
            sourceAuthority.authenticateHello(sourceHello()),
            universe: universe,
            operation: operation,
            targetInstance: store.instanceId,
          );
          expect(pending.state, MoveAdmissionState.admitting);
          expect(pending.acceptRequest.previewId, accept.previewId);
          expect(pending.acceptRequest.digest, accept.digest);
          final receipt = await reconnected.execute(accept);
          expect(text(receipt, 'universe_id'), universe.value);
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          expect(
            (await (await runtime.connect(hello(authorId))).execute(accept))
                .toText(),
            receipt.toText(),
          );
          final admitted = await sourceAuthority.recordMoveAdmission(
            sourceAuthority.authenticateHello(sourceHello()),
            universe: universe,
            operation: operation,
            targetInstance: store.instanceId,
            receipt: receipt as CanonicalObject,
          );
          expect(admitted.state, MoveAdmissionState.admitted);
          await store.transaction((s) async {
            expect(
              await s
                  .kernel(universe)
                  .journal
                  .head(ContinuityId.parse(text(created, 'continuity_id'))),
              RevisionId.parse(text(created, 'revision')),
            );
            final keys = await s
                .workflows(universe)
                .keys('draft:${sourceAuthor.value}:');
            expect(keys, hasLength(1));
            expect(
              (await s.workflows(universe).evidence(keys.single))!.toText(),
              draft.toText(),
            );
            await s.verifyUniverse(universe, complete: true);
          });
          expect(
            textArray(
              await sourceRuntime
                  .connect(sourceHello())
                  .execute(const StatusEngineRequest()),
              'universes',
            ),
            isEmpty,
          );
          expect(
            sourceStore
                .audit(sourceAuthor)
                .where((e) => e.action == 'quiesce_move'),
            hasLength(1),
          );
          expect(File(stage.path).readAsBytesSync(), originalBytes);
        } finally {
          await sourceRuntime.close();
          sourceStore.close();
          root.deleteSync(recursive: true);
        }
      });

      test('loopback HTTP dispatches authenticated PostgreSQL calls', () async {
        final server = await LoopbackEngineServer.postgres(runtime);
        final http = HttpClient();
        try {
          final request = await http.postUrl(
            server.endpoint.resolve('/engine/call'),
          );
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'UB ${base64Encode(hello(authorId).toWire().toBytes())}',
          );
          request.add(
            EngineCall(
              id: BigInt.from(17),
              request: const StatusEngineRequest(),
            ).toWire().toBytes(),
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          final reply = EngineReply.fromWire(
            CanonicalValue.parseWireJson(
              await utf8.decoder.bind(response).join(),
            ),
          );
          expect(reply.id, BigInt.from(17));
          final body = (reply.result as EngineSuccess).value;
          expect(text(body, 'instance_id'), store.instanceId.value);
          expect(text(body, 'service_instance'), runtime.instance.value);
        } finally {
          http.close(force: true);
          await server.close();
        }
      });

      test('client moves PostgreSQL source to SQLite through private service requests', () async {
        final root = Directory.systemTemp.createTempSync('ub-client-pg-move-');
        final targetStore = SqliteInstallationStore.create(root.path);
        final authority = InstallationAuthority(targetStore);
        final owner = authority.initializeAuthor();
        final targetRuntime = NativeSqliteRuntime(authority: authority);
        try {
          final source = await runtime.connect(hello(authorId));
          final target = targetRuntime.connect(
            EngineHello(
              protocolVersion: protocolVersion,
              profileId: owner,
              credential: Credential(
                ProfileCredentialStore.read(root: root.path, profile: owner),
              ),
              clientName: 'Disposable transfer target',
            ),
          );
          final created = await create(source, 'Client move source');
          final move = StageMoveEngineRequest(
            universeId: UniverseId.parse(text(created, 'universe_id')),
            operationId: OperationId.generate(),
            targetInstance: targetStore.instanceId,
          );
          final preview = await prepareMoveTransfer(
            source: source.execute,
            target: target.execute,
            move: move,
            uploadId: OperationId.generate(),
            name: 'Client move target',
          );
          final receipt = await admitMoveTransfer(
            source: source.execute,
            target: target.execute,
            move: move,
            approval: AcceptImportEngineRequest(
              previewId: OperationId.parse(text(preview, 'preview_id')),
              digest: text(preview, 'digest'),
            ),
          );
          expect(text(receipt, 'universe_id'), move.universeId.value);
          expect(
            text(
              await source.execute(
                GetMoveEngineRequest(operationId: move.operationId),
              ),
              'state',
            ),
            'admitted',
          );
        } finally {
          await targetRuntime.close();
          targetStore.close();
          root.deleteSync(recursive: true);
        }
      });

      test('PostgreSQL source stage survives failed file publication and restart before SQLite admission', () async {
        final root = Directory.systemTemp.createTempSync(
          'universe-builder-pg-move-',
        );
        var targetStore = SqliteInstallationStore.create('${root.path}/target');
        var targetAuthority = InstallationAuthority(targetStore);
        final targetAuthor = targetAuthority.initializeAuthor();
        EngineHello targetHello() => EngineHello(
          protocolVersion: protocolVersion,
          profileId: targetAuthor,
          credential: Credential(
            ProfileCredentialStore.read(
              root: targetStore.root,
              profile: targetAuthor,
            ),
          ),
          clientName: 'Disposable local target',
        );
        var targetRuntime = NativeSqliteRuntime(authority: targetAuthority);
        try {
          final source = await runtime.connect(hello(authorId));
          final created = await create(source, 'PostgreSQL original');
          final universe = UniverseId.parse(text(created, 'universe_id'));
          final request = SaveDraftEngineRequest(
            universe: const Selector('PostgreSQL original'),
            continuityId: ContinuityId.parse(text(created, 'continuity_id')),
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: RevisionId.parse(text(created, 'revision')),
              representedContext: RecordId.parse(text(created, 'context_id')),
              operations: const [],
              rationale: 'Retained PostgreSQL draft é😀',
              proposal: null,
            ),
          );
          final draft = await source.execute(request);
          var principal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority).authenticate(
              profile: authorId,
              credential: const Credential(secret),
            ),
          );
          final operation = OperationId.generate(),
              targetInstance = targetStore.instanceId;
          final blocked = Directory('${root.path}/blocked')..createSync();
          await expectLater(
            runtime.stageSourceMove(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              destination: blocked.path,
            ),
            throwsA(isA<FileSystemException>()),
          );
          final control = postgresAuthorityNamespace(store.instanceId);
          expect(
            (await observer.execute('SELECT count(*) FROM $control.move_stage'))
                .single
                .single,
            1,
          );
          final chunks = await observer.execute(
            'SELECT count(*),max(octet_length(content)) FROM $control.move_archive',
          );
          expect(chunks.single[0] as int, greaterThan(1));
          expect(chunks.single[1] as int, lessThanOrEqualTo(262144));
          await expectLater(
            source.execute(request),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          final copy = '${root.path}/transport.sqlite';
          final stage = await runtime.stageSourceMove(
            principal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
            destination: copy,
          );
          final bytes = File(copy).readAsBytesSync();
          expect(File(copy).statSync().mode & 0x1ff, 0x180);
          final preview = await targetRuntime
              .connect(targetHello())
              .execute(
                PreviewImportEngineRequest(
                  source: copy,
                  name: 'Moved to SQLite',
                  mode: ImportMode.restore,
                ),
              );
          final targetReview = targetAuthority.loadImport(
            targetAuthority.authenticateHello(targetHello()),
            AcceptImportEngineRequest(
              previewId: OperationId.parse(text(preview, 'preview_id')),
              digest: text(preview, 'digest'),
            ),
          );
          for (var i = 0; i < 2; i++) {
            await runtime.reviewMoveTarget(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              preview: targetReview,
            );
          }
          final changedPreview = await targetRuntime
              .connect(targetHello())
              .execute(
                PreviewImportEngineRequest(
                  source: copy,
                  name: 'Another move review',
                  mode: ImportMode.restore,
                ),
              );
          final changedReview = targetAuthority.loadImport(
            targetAuthority.authenticateHello(targetHello()),
            AcceptImportEngineRequest(
              previewId: OperationId.parse(text(changedPreview, 'preview_id')),
              digest: text(changedPreview, 'digest'),
            ),
          );
          await expectLater(
            runtime.reviewMoveTarget(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              preview: changedReview,
            ),
            throwsFormatException,
          );
          await expectLater(
            runtime.recordMoveAdmission(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              receipt: targetReview.receipt,
            ),
            throwsStateError,
          );
          await observer.execute(
            'CREATE FUNCTION $control.reject_move() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'Disposable move audit failure\'; RETURN NEW; END \$\$',
          );
          await observer.execute(
            "CREATE TRIGGER reject_move BEFORE INSERT ON $control.audit FOR EACH ROW WHEN (NEW.action='begin_move_admission') EXECUTE FUNCTION $control.reject_move()",
          );
          await expectLater(
            runtime.beginMoveAdmission(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
            ),
            throwsA(isA<ServerException>()),
          );
          expect(
            (await runtime.loadMoveReview(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
            )).state,
            MoveAdmissionState.reviewed,
          );
          await observer.execute('DROP TRIGGER reject_move ON $control.audit');
          for (var i = 0; i < 2; i++) {
            await runtime.beginMoveAdmission(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
            );
          }
          await targetRuntime.close();
          targetStore.close();
          File(copy).deleteSync();
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          principal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority).authenticate(
              profile: authorId,
              credential: const Credential(secret),
            ),
          );
          final recovered = await runtime.stageSourceMove(
            principal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
            destination: copy,
          );
          expect(recovered.digest, stage.digest);
          expect(File(copy).readAsBytesSync(), bytes);
          expect(
            (await runtime.stageSourceMove(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              destination: copy,
            )).digest,
            stage.digest,
          );
          expect(File(copy).readAsBytesSync(), bytes);
          targetStore = SqliteInstallationStore.openExisting(
            '${root.path}/target',
          );
          targetAuthority = InstallationAuthority(targetStore);
          targetRuntime = NativeSqliteRuntime(authority: targetAuthority);
          final client = targetRuntime.connect(targetHello());
          final accept = AcceptImportEngineRequest(
            previewId: OperationId.parse(text(preview, 'preview_id')),
            digest: text(preview, 'digest'),
          );
          final pending = await runtime.loadMoveReview(
            principal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
          );
          expect(pending.state, MoveAdmissionState.admitting);
          expect(pending.acceptRequest.previewId, accept.previewId);
          expect(pending.acceptRequest.digest, accept.digest);
          final receipt = await client.execute(accept);
          expect(text(receipt, 'universe_id'), universe.value);
          expect((await client.execute(accept)).toText(), receipt.toText());
          await expectLater(
            runtime.recordMoveAdmission(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              receipt: CanonicalObject([]),
            ),
            throwsFormatException,
          );
          final writerPrincipal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority).authenticate(
              profile: writerId,
              credential: const Credential(secret),
            ),
          );
          await expectLater(
            runtime.beginMoveAdmission(
              writerPrincipal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
            ),
            throwsA(isA<InstallationException>()),
          );
          await observer.execute(
            "CREATE TRIGGER reject_move BEFORE INSERT ON $control.audit FOR EACH ROW WHEN (NEW.action='complete_move_admission') EXECUTE FUNCTION $control.reject_move()",
          );
          await expectLater(
            runtime.recordMoveAdmission(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              receipt: receipt as CanonicalObject,
            ),
            throwsA(isA<ServerException>()),
          );
          expect(
            (await runtime.loadMoveReview(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
            )).state,
            MoveAdmissionState.admitting,
          );
          await observer.execute('DROP TRIGGER reject_move ON $control.audit');
          for (var i = 0; i < 2; i++) {
            expect(
              (await runtime.recordMoveAdmission(
                principal,
                universe: universe,
                operation: operation,
                targetInstance: targetInstance,
                receipt: receipt,
              )).state,
              MoveAdmissionState.admitted,
            );
          }
          for (final action in [
            'review_move',
            'begin_move_admission',
            'complete_move_admission',
          ]) {
            expect(
              (await observer.execute(
                'SELECT count(*) FROM $control.audit WHERE action=\$1',
                parameters: [action],
              )).single.single,
              1,
            );
          }
          await runtime.close();
          await store.close();
          store = await PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          );
          runtime = NativePostgresRuntime(store: store);
          principal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority).authenticate(
              profile: authorId,
              credential: const Credential(secret),
            ),
          );
          expect(
            (await runtime.loadMoveReview(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
            )).state,
            MoveAdmissionState.admitted,
          );
          final path = targetAuthority
              .resolveUniverseAlias(
                targetAuthority.authenticateHello(targetHello()),
                'Moved to SQLite',
              )
              .path;
          await targetRuntime.close();
          final package = OwnedSqliteDatabase.openExisting(path);
          try {
            expect(
              SqliteJournal(
                package.database,
                universe,
              ).head(ContinuityId.parse(text(created, 'continuity_id'))),
              RevisionId.parse(text(created, 'revision')),
            );
            final workflow = WorkflowStorage(package.database);
            final keys = workflow.keys('draft:${authorId.value}:');
            expect(keys, hasLength(1));
            expect(workflow.evidence(keys.single)!.toText(), draft.toText());
            expect(
              package.database.select(
                'SELECT key FROM historical_workflow WHERE key=?',
                [keys.single],
              ),
              hasLength(1),
            );
          } finally {
            package.close();
          }
          expect(
            (await observer.execute(
              "SELECT count(*) FROM $control.audit WHERE action='quiesce_move'",
            )).single.single,
            1,
          );
          // Missing retained chunks must refuse recovery, never regenerate a
          // different archive from the still-retained original universe.
          await observer.execute(
            'DELETE FROM $control.move_archive WHERE ordinal=0',
          );
          final absent = '${root.path}/refused.sqlite';
          await expectLater(
            runtime.stageSourceMove(
              principal,
              universe: universe,
              operation: operation,
              targetInstance: targetInstance,
              destination: absent,
            ),
            throwsFormatException,
          );
          expect(File(absent).existsSync(), isFalse);
          expect(File(copy).readAsBytesSync(), bytes);
          await expectLater(
            (await runtime.connect(hello(authorId))).execute(request),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          await store.transaction(
            (s) => s.verifyUniverse(universe, complete: true),
          );
          final detail = await (await runtime.connect(hello(authorId)))
              .execute(GetMoveEngineRequest(operationId: operation));
          final fields = Map.fromEntries((detail as CanonicalObject).fields);
          expect(text(detail, 'state'), 'admitted');
          expect(
            fields['target_review']!.toText(),
            targetReview.toCanonical().toText(),
          );
          expect(fields['accept_request']!.toText(), accept.toWire().toText());
          expect(fields['receipt']!.toText(), receipt.toText());
          expect(detail.toText(), isNot(contains(secret)));
        } finally {
          await targetRuntime.close();
          targetStore.close();
          root.deleteSync(recursive: true);
        }
      });

      test('aborted PostgreSQL stage transaction retains guard without partial archive and retries cleanly', () async {
        final author = await runtime.connect(hello(authorId));
        final created = await create(author, 'Move source');
        final universe = UniverseId.parse(text(created, 'universe_id'));
        final operation = OperationId.generate(),
            target = OperationId.generate();
        await quiesce(authorId, universe, operation, target);
        await expectLater(
          store.transaction((s) async {
            await s.prepareMoveArchive(
              actor: authorId,
              universe: universe,
              operation: operation,
              targetInstance: target,
            );
            throw StateError('Disposable interruption before archive commit');
          }),
          throwsStateError,
        );
        final control = postgresAuthorityNamespace(store.instanceId);
        for (final table in ['move_stage', 'move_archive']) {
          expect(
            (await observer.execute('SELECT count(*) FROM $control.$table'))
                .single
                .single,
            0,
          );
        }
        expect(
          (await observer.execute(
            'SELECT count(*) FROM $control.move_quiescence',
          )).single.single,
          1,
        );
        await expectLater(
          author.execute(
            const LibraryEngineRequest(universe: Selector('Move source')),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          store.transaction(
            (s) => s.prepareMoveArchive(
              actor: writerId,
              universe: universe,
              operation: operation,
              targetInstance: target,
            ),
          ),
          throwsA(isA<InstallationException>()),
        );
        final root = Directory.systemTemp.createTempSync(
          'universe-builder-stage-retry-',
        );
        try {
          final principal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority).authenticate(
              profile: authorId,
              credential: const Credential(secret),
            ),
          );
          final stage = await runtime.stageSourceMove(
            principal,
            universe: universe,
            operation: operation,
            targetInstance: target,
            destination: '${root.path}/archive.sqlite',
          );
          expect(stage.digest, matches(RegExp(r'^[0-9a-f]{64}$')));
          expect(
            (await observer.execute('SELECT count(*) FROM $control.move_stage'))
                .single
                .single,
            1,
          );
          expect(
            (await observer.execute(
              "SELECT count(*) FROM $control.audit WHERE action='quiesce_move'",
            )).single.single,
            1,
          );
        } finally {
          root.deleteSync(recursive: true);
        }
      });

      test('private staging retains the exact archive after restart and refuses writers and self-targets', () async {
        var author = await runtime.connect(hello(authorId));
        final source = await create(author, 'Staged service move');
        await author.execute(
          StageSourceEngineRequest(
            universe: const Selector('Staged service move'),
            label: 'Exact multiline source',
            text: List.filled(50000, 'é😀\r\n').join(),
          ),
        );
        final other = await create(author, 'Available service universe');
        final universe = UniverseId.parse(text(source, 'universe_id'));
        final otherUniverse = UniverseId.parse(text(other, 'universe_id'));
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            StageMoveEngineRequest(
              universeId: universe,
              operationId: OperationId.generate(),
              targetInstance: OperationId.generate(),
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          author.execute(
            StageMoveEngineRequest(
              universeId: otherUniverse,
              operationId: OperationId.generate(),
              targetInstance: store.instanceId,
            ),
          ),
          throwsFormatException,
        );
        final operation = OperationId.generate();
        final request = StageMoveEngineRequest(
          universeId: universe,
          operationId: operation,
          targetInstance: OperationId.generate(),
        );
        final staged = await author.execute(
          EngineRequest.decode(request.toWire().toBytes()),
        );
        expect(text(staged, 'source_instance'), store.instanceId.value);
        expect(text(staged, 'digest'), hasLength(64));
        final fields = Map.fromEntries((staged as CanonicalObject).fields);
        expect(
          BigInt.parse((fields['bytes'] as CanonicalNumber).digits),
          greaterThan(BigInt.zero),
        );
        final manifest = Map.fromEntries(
          (fields['manifest'] as CanonicalObject).fields,
        );
        expect((manifest['includes_history'] as CanonicalBool).value, isTrue);
        expect((manifest['includes_workflow'] as CanonicalBool).value, isTrue);
        expect(staged.toText(), isNot(contains(Directory.systemTemp.path)));
        expect(staged.toText(), isNot(contains(secret)));
        expect((await author.execute(request)).toText(), staged.toText());
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect((await author.execute(request)).toText(), staged.toText());
        expect(
          text(
            await author.execute(GetMoveEngineRequest(operationId: operation)),
            'state',
          ),
          'suspended',
        );
        ReadMoveChunkEngineRequest chunkRequest(
          int ordinal, {
          OperationId? target,
        }) => ReadMoveChunkEngineRequest(
          universeId: universe,
          operationId: operation,
          targetInstance: target ?? request.targetInstance,
          ordinal: ordinal,
        );
        final scratch = Directory.systemTemp.createTempSync(
          'universe-builder-move-download-',
        );
        try {
          final downloaded = '${scratch.path}/archive.sqlite';
          protectedFile(downloaded, createNew: true);
          final output = File(downloaded).openSync(mode: FileMode.writeOnly);
          var received = 0, ordinal = 0;
          final bytes = int.parse((fields['bytes'] as CanonicalNumber).digits);
          try {
            while (received < bytes) {
              final reply = await author.execute(
                EngineRequest.decode(chunkRequest(ordinal).toWire().toBytes()),
              );
              final chunk = MoveArchiveChunk.fromWire(reply);
              expect(chunk.ordinal, ordinal++);
              output.writeFromSync(chunk.content);
              received += chunk.content.length;
              expect(
                (await author.execute(chunkRequest(chunk.ordinal))).toText(),
                reply.toText(),
              );
            }
            output.flushSync();
          } finally {
            output.closeSync();
          }
          expect(received, bytes);
          expect(ordinal, greaterThan(1));
          final archive = OwnedSqliteDatabase.stageLogicalArchive(
            downloaded,
            scratch.path,
          );
          try {
            expect(archive.digest, text(staged, 'digest'));
          } finally {
            archive.close();
          }
          await expectLater(
            author.execute(chunkRequest(ordinal)),
            throwsFormatException,
          );
          await expectLater(
            author.execute(chunkRequest(0, target: OperationId.generate())),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          final contributor = await runtime.connect(hello(writerId));
          await expectLater(
            contributor.execute(chunkRequest(0)),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
        } finally {
          scratch.deleteSync(recursive: true);
        }
        final control = postgresAuthorityNamespace(store.instanceId);
        expect(
          (await observer.execute(
            "SELECT count(*) FROM $control.audit WHERE action='quiesce_move'",
          )).single.single,
          1,
        );
        expect(
          (await observer.execute(
            'SELECT count(*) FROM $control.move_quiescence',
          )).single.single,
          1,
        );
        expect(
          (await observer.execute('SELECT count(*) FROM $control.move_stage'))
              .single
              .single,
          1,
        );
      });

      test('private PostgreSQL discovery pages moves after restart and denies writers', () async {
        var author = await runtime.connect(hello(authorId));
        final operations = <OperationId>[];
        for (var i = 0; i < 3; i++) {
          final source = await create(author, 'Move $i');
          final operation = OperationId.generate();
          operations.add(operation);
          await quiesce(
            authorId,
            UniverseId.parse(text(source, 'universe_id')),
            operation,
            OperationId.generate(),
          );
        }
        operations.sort((a, b) => a.value.compareTo(b.value));
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        OperationId? after;
        for (var i = 0; i < operations.length; i++) {
          final page = await author.execute(
            EngineRequest.decode(
              ListMovesEngineRequest(after: after, limit: 1).toWire().toBytes(),
            ),
          );
          final fields = Map.fromEntries((page as CanonicalObject).fields);
          final rows = (fields['moves'] as CanonicalArray).items;
          expect(rows, hasLength(1));
          expect(text(rows.single, 'operation_id'), operations[i].value);
          expect(text(rows.single, 'state'), 'suspended');
          expect(text(page, 'source_instance'), store.instanceId.value);
          if (i == operations.length - 1) {
            expect(fields['next_after'], isA<CanonicalNull>());
          } else {
            after = OperationId.parse(wireString(fields['next_after']!));
            expect(after, operations[i]);
          }
          final report = await author.execute(
            GetMoveEngineRequest(operationId: operations[i]),
          );
          expect(text(report, 'state'), 'suspended');
          final data = Map.fromEntries((report as CanonicalObject).fields);
          expect(data['target_review'], isA<CanonicalNull>());
          expect(data['accept_request'], isA<CanonicalNull>());
          expect(report.toText(), isNot(contains('ub_unv_')));
        }
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(const ListMovesEngineRequest()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(GetMoveEngineRequest(operationId: operations.first)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          author.execute(const ListMovesEngineRequest(limit: 101)),
          throwsFormatException,
        );
        await expectLater(
          author.execute(
            GetMoveEngineRequest(operationId: OperationId.generate()),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });

      test('writer self-target and rollback cannot suspend a source', () async {
        final author = await runtime.connect(hello(authorId));
        final source = await create(author, 'Move source');
        final universe = UniverseId.parse(text(source, 'universe_id'));
        final operation = OperationId.generate(),
            target = OperationId.generate();
        await expectLater(
          quiesce(writerId, universe, operation, target),
          throwsA(isA<InstallationException>()),
        );
        await expectLater(
          quiesce(authorId, universe, operation, store.instanceId),
          throwsFormatException,
        );
        await expectLater(
          store.transaction((s) async {
            await s.authority.quiesceUniverseForMove(
              actor: authorId,
              universe: universe,
              operation: operation,
              targetInstance: target,
            );
            throw StateError('Disposable move rollback');
          }),
          throwsStateError,
        );
        await author.execute(
          const LibraryEngineRequest(universe: Selector('Move source')),
        );
        expect(
          (await observer.execute(
            'SELECT count(*) FROM ${postgresAuthorityNamespace(store.instanceId)}.move_quiescence',
          )).single.single,
          0,
        );
      });
      test('prior PostgreSQL control version refuses opening without rewriting its layout', () async {
        await runtime.close();
        await store.close();
        final control = postgresAuthorityNamespace(store.instanceId);
        await observer.execute('DROP TABLE $control.move_review');
        await observer.execute(
          'ALTER TABLE $control.move_stage DROP COLUMN records',
        );
        await observer.execute(
          'ALTER TABLE $control.authority DROP CONSTRAINT authority_schema_version_check',
        );
        await observer.execute(
          'UPDATE $control.authority SET schema_version=4',
        );
        await observer.execute(
          'ALTER TABLE $control.authority ADD CHECK(schema_version=4)',
        );
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
        expect(
          (await observer.execute(
            'SELECT schema_version FROM $control.authority',
          )).single.single,
          4,
        );
        final name = 'ub_install_${store.instanceId.value}';
        expect(
          (await observer.execute(
            "SELECT count(*) FROM information_schema.tables WHERE table_schema=\$1 AND table_name='move_review'",
            parameters: [name],
          )).single.single,
          0,
        );
        expect(
          (await observer.execute(
            "SELECT count(*) FROM information_schema.columns WHERE table_schema=\$1 AND table_name='move_stage' AND column_name='records'",
            parameters: [name],
          )).single.single,
          0,
        );
      });

      test('missing move layout refuses existing installation without recreating it', () async {
        await runtime.close();
        await store.close();
        await observer.execute(
          'DROP TABLE ${postgresAuthorityNamespace(store.instanceId)}.move_quiescence CASCADE',
        );
        await expectLater(
          PostgresInstallationStore.openExisting(
            endpoint(),
            settings: settings,
          ),
          throwsA(isA<InstallationException>()),
        );
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}

List<CanonicalValue> textArray(CanonicalValue value, String key) =>
    (Map.fromEntries((value as CanonicalObject).fields)[key] as CanonicalArray)
        .items;
