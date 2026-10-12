@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  late PostgresInstallationStore store;
  late NativePostgresRuntime runtime;
  late Connection observer;
  late ProfileId authorId, writerId;
  final universes = <UniverseId>[];
  const secret = 'disposable-engine-profile';
  const selector = Selector('Disposable engine universe');
  Endpoint endpoint() => Endpoint(
    host: '127.0.0.1',
    port: port!,
    database: 'ub_disposable',
    username: 'postgres',
  );
  const settings = ConnectionSettings(sslMode: SslMode.disable);
  EngineHello hello(
    ProfileId id, {
    String version = protocolVersion,
    String credential = secret,
  }) => EngineHello(
    protocolVersion: version,
    profileId: id,
    credential: Credential(credential),
    clientName: 'Disposable PostgreSQL engine client',
  );
  Future<T> tool<T>(
    NativePostgresConnection connection,
    Request request,
    T Function(CanonicalValue) decode,
  ) async => Envelope.fromWire(
    await connection.execute(ToolEngineRequest(request: request)),
    decode,
  ).result;

  group(
    'PostgreSQL engine integration',
    () {
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
      test('creates, validates, reviews, approves and publishes through dispatch with durable retries and current access', () async {
        var author = await runtime.connect(hello(authorId));
        var writer = await runtime.connect(hello(writerId));
        expect(author.welcome.author, isTrue);
        expect(writer.welcome.author, isFalse);
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final represented = RecordId.parse(created.string('context_id'));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: false,
            ),
          ),
        );
        const sourceText = '\uFEFFExact notes: é😀\r\n';
        const sourceRequest = StageSourceEngineRequest(
          universe: selector,
          label: 'Disposable notes',
          text: sourceText,
        );
        await expectLater(
          writer.execute(sourceRequest),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final staged = WireFields(await author.execute(sourceRequest), {
          'canonical',
          'operations',
        });
        expect(staged.boolean('canonical'), isFalse);
        final sourceVersion = (staged.require('operations') as CanonicalArray)
            .items
            .map(DomainOperation.fromWire)
            .cast<RecordNarrativeReferenceOperation>()
            .map((op) => op.payload)
            .whereType<SourceVersionRecord>()
            .single;
        final digest = sha256.convert(utf8.encode(sourceText)).toString();
        expect(sourceVersion.contentDigest, digest);
        expect(
          sourceVersion.byteSize,
          BigInt.from(utf8.encode(sourceText).length),
        );
        await store.transaction((s) async {
          expect(
            wireString((await s.workflows(universe).get('source:$digest'))!),
            sourceText,
          );
          expect(
            await s
                .kernel(universe)
                .journal
                .snapshot(
                  continuity,
                  RevisionId.parse(created.string('revision')),
                ),
            hasLength(2),
          );
        });
        final opened = await tool(
          writer,
          OpenContextRequest(
            universe: selector,
            universeId: universe,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        expect(opened.frame.revision.value, created.string('revision'));
        final proposal = await tool(
          writer,
          CreateProposalRequest(
            universe: selector,
            universeId: universe,
            contextId: opened.contextId,
            operations: [
              CreateEntityOperation(
                clientRef: RecordId.generate().value,
                record: EntityRecord(
                  names: [],
                  classification: null,
                  classificationResolution:
                      ClassificationResolution.unclassified,
                  worldAssociations: [],
                  labels: {},
                  metadata: {},
                ),
              ),
            ],
            submission: Submission.submitted,
            rationale: 'Disposable engine authoring',
            idempotencyKey: 'create',
          ),
          Proposal.fromWire,
        );
        final reference = ProposalRef(
          proposalId: proposal.proposalId,
          version: proposal.version,
          digest: proposal.digest,
        );
        var status = await tool(
          writer,
          QueuedProposalValidationRequest(
            universe: selector,
            universeId: universe,
            contextId: opened.contextId,
            proposalReference: reference,
            checkScope: CheckScope.candidate,
            idempotencyKey: 'queue',
          ),
          OperationStatusV3.fromWire,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!{
              OperationState.succeeded,
              OperationState.failed,
              OperationState.cancelled,
            }.contains(status.state) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          status = await tool(
            writer,
            GetOperationIdRequest(
              universe: selector,
              universeId: universe,
              operationId: status.operationId,
            ),
            OperationStatusV3.fromWire,
          );
        }
        expect(status.state, OperationState.succeeded, reason: status.failure);
        final report = status.validation as EvaluatedValidation;
        final approve = ApproveEngineRequest(
          universe: selector,
          proposalReference: reference,
          validationRun: report.execution.runId,
        );
        await expectLater(
          writer.execute(approve),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(
            ReviewEngineRequest(
              universe: selector,
              proposalReference: reference,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final review = WireFields(
          await author.execute(
            ReviewEngineRequest(
              universe: selector,
              proposalReference: reference,
            ),
          ),
          {
            'proposal',
            'changes',
            'diff',
            'footprint',
            'latest',
            'assessment_review',
          },
        );
        expect(
          Proposal.fromWire(review.require('proposal')).digest,
          proposal.digest,
        );
        expect((review.require('diff') as CanonicalArray).items, hasLength(1));
        await author.execute(approve);
        final commit = CommitRequest(
          universe: selector,
          universeId: universe,
          proposalReference: reference,
          expectedBaseRevision: opened.frame.revision,
          validationRun: report.execution.runId,
          idempotencyKey: 'publish',
        );
        final receipt = await tool(writer, commit, CommitReceipt.fromWire);
        final oldInstance = runtime.instance;
        final installation = store.instanceId;
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        expect(store.instanceId, installation);
        expect(runtime.instance, isNot(oldInstance));
        author = await runtime.connect(hello(authorId));
        writer = await runtime.connect(hello(writerId));
        expect(
          (await tool(
            writer,
            commit,
            CommitReceipt.fromWire,
          )).toWire().toText(),
          receipt.toWire().toText(),
        );
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Renamed engine universe',
          ),
        );
        final retried = Envelope.fromWire(
          await writer.execute(ToolEngineRequest(request: commit)),
          CommitReceipt.fromWire,
        );
        expect(retried.aliasMatched, isTrue);
        expect(retried.universe.value, 'Renamed engine universe');
        expect(retried.result.toWire().toText(), receipt.toWire().toText());
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        await expectLater(
          writer.execute(ToolEngineRequest(request: commit)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final hidden = WireFields(
          await writer.execute(const StatusEngineRequest()),
          {
            'service_instance',
            'universes',
            'canonical_commit',
            'max_requests_per_principal',
            'universe_queue_capacity',
          },
        );
        expect((hidden.require('universes') as CanonicalArray).items, isEmpty);
      });
      test('pinned discovery, record history and paged research survive reopen while current world scope remains closed', () async {
        var author = await runtime.connect(hello(authorId));
        var writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final context = RecordId.parse(created.string('context_id'));
        final publicWorld = RecordId.generate(),
            privateWorld = RecordId.generate();
        final publicWorldId = recordWorld(publicWorld),
            privateWorldId = recordWorld(privateWorld);
        final ids = List.generate(4, (_) => RecordId.generate())
          ..sort((a, b) => a.value.compareTo(b.value));
        final hidden = RecordId.generate();
        EntityRecord entity(String label, WorldId world) => EntityRecord(
          names: [],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [
            WorldAssociation(
              world: world,
              role: 'setting',
              validity: const UnspecifiedValidity(),
              qualifiers: {},
            ),
          ],
          labels: {'en': label},
          metadata: {},
        );
        final payloads = <RecordId, RecordPayload>{
          publicWorld: WorldRecord(selector: 'Campaign', aliases: ['Play']),
          privateWorld: WorldRecord(selector: 'Private'),
          for (var i = 0; i < ids.length; i++)
            ids[i]: entity('Alpha $i é😀', publicWorldId),
          hidden: entity('Alpha hidden', privateWorldId),
        };
        final rows = [
          for (final entry in payloads.entries)
            StoredVersion.build(
              RecordVersionId.generate(),
              RecordIdentity(
                universeId: universe,
                recordId: entry.key,
                recordKind: entry.value.recordKind,
              ),
              entry.value.toWire(),
            ),
        ];
        final revision = await store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: RevisionId.parse(created.string('revision')),
                  principal: PrincipalId.generate(),
                  decision: 'Disposable read setup',
                  reason: 'Disposable read setup',
                  idempotencyKey: 'read-fixture',
                  changes: [
                    for (final row in rows)
                      Assignment(recordId: row.identity.recordId, next: row),
                  ],
                ),
              ),
        );
        Future<OpenedContext> openContext(
          NativePostgresConnection connection,
        ) => tool(
          connection,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(context),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        final opened = await openContext(author);
        final summary = await tool(
          author,
          DescribeSummaryRequest(universe: selector),
          Description.fromWire,
        );
        expect(summary.continuities.single.revisionId, revision);
        expect(
          (await tool(
            author,
            DescribeCapabilitiesRequest(universe: selector),
            Description.fromWire,
          )).capabilities,
          isNotEmpty,
        );
        expect(
          (await tool(
            author,
            DescribeWorldsRequest(
              universe: selector,
              contextId: opened.contextId,
            ),
            Description.fromWire,
          )).worlds,
          hasLength(2),
        );
        await tool(
          author,
          DescribeDefinitionsRequest(
            universe: selector,
            contextId: opened.contextId,
          ),
          Description.fromWire,
        );
        GetRequest get(ContextId retained, RecordId id) => GetRequest(
          universe: selector,
          contextId: retained,
          recordIds: [id],
          fieldGroups: [FieldGroup.payload, FieldGroup.history],
        );
        final oldRecord = await tool(
          author,
          get(opened.contextId, ids.first),
          Records.fromWire,
        );
        expect(
          oldRecord.records.single.payload.toWire().toText(),
          payloads[ids.first]!.toWire().toText(),
        );
        expect(oldRecord.history, hasLength(1));
        final newer = StoredVersion.build(
          RecordVersionId.generate(),
          rows.firstWhere((r) => r.identity.recordId == ids.first).identity,
          entity('Changed', publicWorldId).toWire(),
        );
        await store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable update',
                  reason: 'Disposable update',
                  idempotencyKey: 'read-update',
                  changes: [
                    Assignment(
                      recordId: ids.first,
                      expected: rows
                          .firstWhere((r) => r.identity.recordId == ids.first)
                          .versionId,
                      next: newer,
                    ),
                  ],
                ),
              ),
        );
        SearchRequest search({String? cursor, String query = 'Alpha'}) =>
            SearchRequest(
              universe: selector,
              contextId: opened.contextId,
              query: query,
              typedFilters: Filters(recordKinds: [RecordKind.entity]),
              limit: 1,
              cursor: cursor,
              world: const Selector('Play'),
            );
        Future<Envelope<SearchResults>> searchPage(
          SearchRequest request,
        ) async => Envelope.fromWire(
          await author.execute(ToolEngineRequest(request: request)),
          SearchResults.fromWire,
        );
        final first = await searchPage(search());
        expect(first.result.hits.single.recordId, ids.first);
        expect(first.delivery.complete, isFalse);
        final record = RecordVersion.fromWire(
          rows
              .firstWhere((r) => r.identity.recordId == ids.first)
              .toCanonical(),
        );
        final budget =
            ContextBrief(
              records: [record],
              requiredDependencies: [],
              coverage: Coverage.partial,
            ).toWire().toBytes().length +
            30;
        GetContextRequest brief({
          String? cursor,
          String purpose = 'Research',
        }) => GetContextRequest(
          universe: selector,
          contextId: opened.contextId,
          focusIds: ids,
          purpose: purpose,
          byteBudget: budget,
          cursor: cursor,
        );
        Future<Envelope<ContextBrief>> briefPage(
          GetContextRequest request,
        ) async => Envelope.fromWire(
          await author.execute(ToolEngineRequest(request: request)),
          ContextBrief.fromWire,
        );
        final firstBrief = await briefPage(brief());
        expect(firstBrief.delivery.complete, isFalse);
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        writer = await runtime.connect(hello(writerId));
        await expectLater(
          searchPage(search(cursor: first.delivery.cursor, query: 'Changed')),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          briefPage(
            brief(cursor: firstBrief.delivery.cursor, purpose: 'Changed'),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final collected = [first.result.hits.single.recordId];
        var cursor = first.delivery.cursor;
        while (cursor != null) {
          final page = await searchPage(search(cursor: cursor));
          expect(page.frame!.revision, revision);
          collected.addAll(page.result.hits.map((h) => h.recordId));
          cursor = page.delivery.cursor;
        }
        expect(collected, ids);
        final briefIds = [
          ...firstBrief.result.records.map((r) => r.identity.recordId),
        ];
        final dependencies = [...firstBrief.result.requiredDependencies];
        cursor = firstBrief.delivery.cursor;
        while (cursor != null) {
          final page = await briefPage(brief(cursor: cursor));
          expect(page.frame!.revision, revision);
          briefIds.addAll(page.result.records.map((r) => r.identity.recordId));
          dependencies.addAll(page.result.requiredDependencies);
          cursor = page.delivery.cursor;
        }
        expect(briefIds, [...ids, publicWorld]);
        expect(dependencies, [publicWorld]);
        expect(
          (await tool(
            author,
            get(opened.contextId, ids.first),
            Records.fromWire,
          )).history,
          hasLength(1),
        );
        final fresh = await openContext(author);
        final current = await tool(
          author,
          get(fresh.contextId, ids.first),
          Records.fromWire,
        );
        expect(
          current.records.single.payload.toWire().toText(),
          newer.payload.toText(),
        );
        expect(current.history, hasLength(2));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: [publicWorldId],
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        final scoped = await openContext(writer);
        final scopedSearch = SearchRequest(
          universe: selector,
          contextId: scoped.contextId,
          world: const Selector('Play'),
          query: 'Alpha',
          typedFilters: Filters(recordKinds: [RecordKind.entity]),
          limit: 100,
        );
        final visible = Envelope.fromWire(
          await writer.execute(ToolEngineRequest(request: scopedSearch)),
          SearchResults.fromWire,
        );
        expect(visible.authorizationScope, 'world-scoped grant');
        expect(visible.worldFocus, publicWorldId);
        expect(visible.result.hits.map((h) => h.recordId), ids.skip(1));
        expect(
          (await tool(
            writer,
            DescribeWorldsRequest(
              universe: selector,
              contextId: scoped.contextId,
            ),
            Description.fromWire,
          )).worlds,
          hasLength(1),
        );
        final restricted = await tool(
          writer,
          get(scoped.contextId, ids.first),
          Records.fromWire,
        );
        expect(restricted.historyCoverage, Coverage.restricted);
        expect(restricted.history, isEmpty);
        await expectLater(
          tool(writer, get(scoped.contextId, hidden), Records.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(writer, get(opened.contextId, ids.first), Records.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        await expectLater(
          tool(writer, scopedSearch, SearchResults.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });
      test('denies invalid handshake and private universe creation without side effects', () async {
        await expectLater(
          runtime.connect(hello(writerId, credential: 'invalid')),
          throwsA(isA<InstallationException>()),
        );
        await expectLater(
          runtime.connect(hello(writerId, version: '2')),
          throwsA(isA<FormatException>()),
        );
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            const CreateUniverseEngineRequest(
              name: 'Denied',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final status = WireFields(
          await writer.execute(const StatusEngineRequest()),
          {
            'service_instance',
            'universes',
            'canonical_commit',
            'max_requests_per_principal',
            'universe_queue_capacity',
          },
        );
        expect((status.require('universes') as CanonicalArray).items, isEmpty);
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable PostgreSQL'
        : false,
  );
}
