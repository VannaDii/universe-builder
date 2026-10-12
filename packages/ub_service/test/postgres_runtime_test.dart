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

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as objects;
import 'writing_units_test.dart' as units;

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
      test('private image routes preserve originals and preview only admitted pinned assets after reviewed publication', () async {
        final directory = Directory.systemTemp.createTempSync(
          'ub-postgres-images-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final bytes = base64.decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
        );
        final source = File('${directory.path}/Portrait é.png')
          ..writeAsBytesSync(bytes);
        var author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
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
        final revision = RevisionId.parse(created.string('revision'));
        Future<OpenedContext> open() => tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        StageImageEngineRequest stage(String path) =>
            StageImageEngineRequest(universe: selector, source: path);
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
        await expectLater(
          writer.execute(stage('/unreadable/never-opened')),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final invalid = File('${directory.path}/invalid.png')
          ..writeAsStringSync('not an image');
        final link = Link('${directory.path}/linked.png')
          ..createSync(source.path);
        await expectLater(
          author.execute(stage(invalid.path)),
          throwsA(isA<FormatException>()),
        );
        await expectLater(
          author.execute(stage(link.path)),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          author.execute(stage(directory.path)),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          store.transaction((s) async {
            await s
                .kernel(universe)
                .stageImageBytes(bytes, 'Interrupted import.png');
            throw StateError('Disposable interrupted staging');
          }),
          throwsA(isA<StateError>()),
        );
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('image-asset:'), isEmpty);
          expect(await s.workflows(universe).keys('image-bytes:'), isEmpty);
        });
        final old = await open();
        final imported = WireFields(await author.execute(stage(source.path)), {
          'canonical',
          'asset_id',
          'preview',
          'metadata',
          'operations',
        });
        expect(imported.boolean('canonical'), isFalse);
        expect(
          imported.string('preview'),
          startsWith('data:image/jpeg;base64,'),
        );
        final operation = DomainOperation.fromWire(
          imported.array('operations').single,
        ) as AddImageAssetOperation;
        final asset = operation.record;
        final id = RecordId.parse(imported.string('asset_id'));
        expect(operation.clientRef, id.value);
        expect(asset.originalName, 'Portrait é.png');
        expect(asset.mediaType, 'image/png');
        expect(asset.byteSize, BigInt.from(bytes.length));
        expect(
          imported.require('metadata').toText(),
          CanonicalObject(
            asset.toWire().fields.where((f) => f.key != 'record_kind'),
          ).toText(),
        );
        ImagePreviewEngineRequest preview(
          ContextId context, {
          RecordId? record,
        }) => ImagePreviewEngineRequest(
          universe: selector,
          contextId: context,
          asset: record ?? id,
        );
        await expectLater(
          author.execute(preview(old.contextId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).imageBytes(asset),
            orderedEquals(bytes),
          );
          expect(await s.kernel(universe).journal.head(continuity), revision);
          expect(await s.kernel(universe).journal.identityExists(id), isFalse);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
        final candidate = await tool(
          author,
          CreateProposalRequest(
            universe: selector,
            contextId: old.contextId,
            operations: [operation],
            submission: Submission.submitted,
            rationale: 'Reviewed portrait asset',
            idempotencyKey: 'image-candidate',
          ),
          Proposal.fromWire,
        );
        final reference = ProposalRef(
          proposalId: candidate.proposalId,
          version: candidate.version,
          digest: candidate.digest,
        );
        final checked = await tool(
          author,
          ProposalValidationRequest(
            universe: selector,
            contextId: old.contextId,
            proposalReference: reference,
            checkScope: CheckScope.candidate,
          ),
          ValidationV3.fromWire,
        ) as EvaluatedValidation;
        await author.execute(
          ApproveEngineRequest(
            universe: selector,
            proposalReference: reference,
            validationRun: checked.execution.runId,
          ),
        );
        final published = await tool(
          author,
          CommitRequest(
            universe: selector,
            proposalReference: reference,
            expectedBaseRevision: revision,
            validationRun: checked.execution.runId,
            idempotencyKey: 'publish-image',
          ),
          CommitReceipt.fromWire,
        );
        expect(published.revision, isNot(revision));
        await expectLater(
          author.execute(preview(old.contextId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final current = await open();
        await expectLater(
          author.execute(preview(current.contextId, record: represented)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(preview(current.contextId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final result = await author.execute(preview(current.contextId));
        expect(
          WireFields(result, {
            'asset_id',
            'metadata',
            'preview',
          }).string('preview'),
          imported.string('preview'),
        );
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(
          (await author.execute(preview(current.contextId))).toText(),
          result.toText(),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).imageBytes(asset),
            orderedEquals(bytes),
          );
        });
      });

      test('private library shows current heads and latest named writing while retaining immutable revisions', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
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
        final context = RecordId.parse(created.string('context_id'));
        final revision = RevisionId.parse(created.string('revision'));
        const request = LibraryEngineRequest(universe: selector);
        Future<WireFields> library() async => WireFields(
          await author.execute(request),
          {'storage', 'worlds', 'contexts', 'continuities', 'writing'},
        );
        List<WireFields> pending(WireFields value) =>
            WireFields(value.require('writing'), {'proposals', 'approved'})
                .array('proposals')
                .map(
                  (v) => WireFields(v, {
                    'candidate',
                    'label',
                    'submission',
                    'base_revision',
                    'continuity',
                  }),
                )
                .toList();
        final initial = await library();
        final storage = WireFields(initial.require('storage'), {
          'universe',
          'backend',
          'postgres_version',
          'synchronous_commit',
          'heads',
        });
        expect(storage.string('universe'), universe.value);
        expect(storage.string('backend'), 'postgres');
        expect(storage.string('postgres_version'), isNotEmpty);
        expect(storage.string('synchronous_commit'), 'on');
        expect(
          storage.array('heads').single.toText(),
          CanonicalArray([
            CanonicalString(continuity.value),
            CanonicalString(revision.value),
          ]).toText(),
        );
        expect(initial.array('contexts').map(wireString), [context.value]);
        expect(initial.array('worlds'), isEmpty);
        expect(
          WireFields(initial.array('continuities').single, {
            'id',
            'revision',
            'name',
          }).string('name'),
          'Original continuity',
        );
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
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final opened = await tool(
          author,
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
        EntityRecord person(String name) => EntityRecord(
          names: [
            ContextualName(text: name, validity: const UnspecifiedValidity()),
          ],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [],
          labels: {'en': 'Display label'},
          metadata: {},
        );
        ProposalRef reference(Proposal p) => ProposalRef(
          proposalId: p.proposalId,
          version: p.version,
          digest: p.digest,
        );
        final proposal = await tool(
          author,
          CreateProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            operations: [
              CreateEntityOperation(
                clientRef: f.id(20).value,
                record: person('Mara'),
              ),
            ],
            submission: Submission.draft,
            rationale: 'Named authoring',
            idempotencyKey: 'library-create',
          ),
          Proposal.fromWire,
        );
        expect(pending(await library()).single.string('label'), 'Mara');
        final revised = await tool(
          author,
          ReviseProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: reference(proposal),
            operations: [
              CreateEntityOperation(
                clientRef: f.id(20).value,
                record: person('Mara corrected'),
              ),
            ],
            submission: Submission.draft,
            rationale: 'Corrected identity',
            idempotencyKey: 'library-revise',
          ),
          Proposal.fromWire,
        );
        final latest = pending(await library());
        expect(latest, hasLength(1));
        expect(latest.single.string('label'), 'Mara corrected');
        expect(
          ProposalRef.fromWire(latest.single.require('candidate')),
          reference(revised),
        );
        await tool(
          author,
          WithdrawProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: reference(revised),
            idempotencyKey: 'library-withdraw',
          ),
          Proposal.fromWire,
        );
        expect(pending(await library()), isEmpty);
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('proposal:'), hasLength(3));
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
          expect(await s.kernel(universe).journal.head(continuity), revision);
          final world = StoredVersion.build(
            RecordVersionId.generate(),
            RecordIdentity(
              universeId: universe,
              recordId: f.id(50),
              recordKind: RecordKind.world,
            ),
            WorldRecord(selector: 'Campaign').toWire(),
          );
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'Library world',
                  idempotencyKey: 'library-world',
                  changes: [
                    Assignment(
                      recordId: world.identity.recordId,
                      expected: null,
                      next: world,
                    ),
                  ],
                ),
              );
          await s.workflows(universe).compareAppend({}, [
            MapEntry(
              'continuity-name:${continuity.value}',
              CanonicalString('Campaign edition'),
            ),
          ]);
        });
        final current = await library();
        final world = WireFields(current.array('worlds').single, {
          'id',
          'name',
          'continuity_id',
        });
        expect(world.string('id'), recordWorld(f.id(50)).value);
        expect(world.string('name'), 'Campaign');
        expect(world.string('continuity_id'), continuity.value);
        final edition = WireFields(current.array('continuities').single, {
          'id',
          'revision',
          'name',
        });
        expect(edition.string('name'), 'Campaign edition');
        expect(edition.string('revision'), isNot(revision.value));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: [recordWorld(f.id(50))],
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await runtime.close();
        runtime = NativePostgresRuntime(store: store);
        final reopened = await runtime.connect(hello(authorId));
        final recovered = WireFields(await reopened.execute(request), {
          'storage',
          'worlds',
          'contexts',
          'continuities',
          'writing',
        });
        expect(
          recovered.require('writing').toText(),
          current.require('writing').toText(),
        );
        expect(
          recovered.require('continuities').toText(),
          current.require('continuities').toText(),
        );
        expect(
          recovered.require('worlds').toText(),
          current.require('worlds').toText(),
        );
      });

      test('private drafts recover exact saves across reconnect and keep old bases without publication', () async {
        var author = await runtime.connect(hello(authorId));
        final other = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
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
        final context = RecordId.parse(created.string('context_id'));
        final revision = RevisionId.parse(created.string('revision'));
        DraftContent content(
          String text, {
          RecordId? represented,
          List<DomainOperation> operations = const [],
        }) => DraftContent(
          baseRevision: revision,
          representedContext: represented ?? context,
          operations: operations,
          rationale: text,
          proposal: null,
        );
        SaveDraftEngineRequest save(DraftContent draft, BigInt version) =>
            SaveDraftEngineRequest(
              universe: selector,
              continuityId: continuity,
              expectedVersion: version,
              content: draft,
            );
        final load = LoadDraftEngineRequest(
          universe: selector,
          continuityId: continuity,
        );
        expect(await author.execute(load), isA<CanonicalNull>());
        await expectLater(
          author.execute(save(content('😀' * 4001), BigInt.zero)),
          throwsA(isA<InvalidArgumentError>()),
        );
        final oversized = content(
          'Too many operations',
          operations: List.generate(
            2000,
            (_) => DefineUnitOperation(
              clientRef: 'unfinished-unit',
              record: units.unit(),
            ),
          ),
        );
        expect(
          CanonicalArray(oversized.operations.map((op) => op.toWire()))
              .toBytes()
              .length,
          greaterThan(128000),
        );
        await expectLater(
          author.execute(save(oversized, BigInt.zero)),
          throwsA(isA<InvalidArgumentError>()),
        );
        await expectLater(
          author.execute(
            save(
              content('Unknown context', represented: f.id(999)),
              BigInt.zero,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(await author.execute(load), isA<CanonicalNull>());
        final request = save(
          content(
            'Unfinished text é😀',
            operations: [
              DefineUnitOperation(
                clientRef: 'unfinished-unit',
                record: units.unit(),
              ),
            ],
          ),
          BigInt.zero,
        );
        final saved = await author.execute(request);
        expect(SavedDraft.fromWire(saved).version, BigInt.one);
        expect(
          SavedDraft.fromWire(saved).content.toWire().toText(),
          request.content.toWire().toText(),
        );
        expect((await other.execute(request)).toText(), saved.toText());
        await expectLater(
          other.execute(save(content('Competing text'), BigInt.zero)),
          throwsA(
            isA<BaseRevisionConflictError>().having(
              (e) => e.actual,
              'actual',
              'draft:1',
            ),
          ),
        );
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
        await expectLater(
          writer.execute(load),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          final journal = s.kernel(universe).journal;
          expect(await journal.head(continuity), revision);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
          final row = f.row(20, f.entity());
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'Advance after draft',
                  idempotencyKey: 'draft-fixture',
                  changes: [
                    Assignment(
                      recordId: row.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        row.recordVersionId,
                        RecordIdentity(
                          universeId: universe,
                          recordId: row.identity.recordId,
                          recordKind: row.identity.recordKind,
                        ),
                        row.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              );
        });
        await runtime.close();
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect((await author.execute(request)).toText(), saved.toText());
        expect((await author.execute(load)).toText(), saved.toText());
        final revised = await author.execute(
          save(content('😀' * 4000), BigInt.one),
        );
        expect(SavedDraft.fromWire(revised).version, BigInt.two);
        expect(SavedDraft.fromWire(revised).content.baseRevision, revision);
        await store.transaction((s) async {
          final workflow = s.workflows(universe);
          final keys = await workflow.keys(
            'draft:${authorId.value}:${continuity.value}:',
          );
          expect(keys, hasLength(2));
          expect((await workflow.get(keys.first))!.toText(), saved.toText());
          expect((await workflow.get(keys.last))!.toText(), revised.toText());
          expect(await workflow.keys('approval:'), isEmpty);
          expect(await workflow.keys('proposal:'), isEmpty);
          expect(
            await s.kernel(universe).journal.head(continuity),
            isNot(revision),
          );
        });
      });

      test('inline research dispatch works without writing rights and never retains publication authority', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
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
        final revision = RevisionId.parse(created.string('revision'));
        Future<void> grant(List<WorldId>? worlds) async {
          await author.execute(
            GrantEngineRequest(
              grant: GrantSpec(
                profileId: writerId,
                universeId: universe,
                worlds: worlds,
                propose: false,
                edit: false,
                protected: false,
              ),
            ),
          );
        }

        Future<OpenedContext> open() => tool(
          writer,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        InlineValidationRequest check(
          ContextId context, {
          Selector? world,
          List<DomainOperation>? operations,
        }) => InlineValidationRequest(
          universe: selector,
          contextId: context,
          world: world,
          operations:
              operations ??
              [
                CreateEntityOperation(
                  clientRef: f.id(20).value,
                  record: f.entity(),
                ),
              ],
          checkScope: CheckScope.universe,
        );
        await grant(null);
        final opened = await open();
        final request = check(opened.contextId);
        final report = await tool(
          writer,
          request,
          ValidationV3.fromWire,
        ) as EvaluatedValidation;
        expect((report.submittedInput as QueryInput).frame, opened.frame);
        expect(report.finalBindingDigest, isNull);
        expect(report.assessment, isA<AbsentAssessment>());
        expect(report.execution.operationId, isNull);
        expect(report.execution.inputDigest, canonicalDigest(request.toArgs()));
        await store.transaction((s) async {
          final workflow = s.workflows(universe);
          expect(await workflow.keys('validation:'), hasLength(1));
          final retained = WireFields(
            (await workflow.get('validation:${report.execution.runId.value}'))!,
            {
              'proposal_digest',
              'validation',
              'admissible',
              'report',
              'capture',
            },
          );
          expect(retained.boolean('admissible'), isTrue);
          expect(retained.optional('capture', (value) => value), isNull);
          expect(retained.require('report').toText(), report.toWire().toText());
          for (final prefix in [
            'proposal:',
            'operation:',
            'reserved-record:',
            'approval:',
          ]) {
            expect(await workflow.keys(prefix), isEmpty);
          }
          expect(await s.kernel(universe).journal.head(continuity), revision);
          expect(
            await s.kernel(universe).journal.identityExists(f.id(20)),
            isFalse,
          );
        });
        await expectLater(
          tool(
            writer,
            check(
              opened.contextId,
              operations: [
                CreateEntityOperation(
                  clientRef: f.id(21).value,
                  record: f.entity(classification: f.id(999)),
                ),
              ],
            ),
            ValidationV3.fromWire,
          ),
          throwsA(isA<FormatException>()),
        );
        await store.transaction((s) async {
          final row = f.row(50, WorldRecord(selector: 'Campaign'));
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable world',
                  reason: 'Scoped research',
                  idempotencyKey: 'inline-world',
                  changes: [
                    Assignment(
                      recordId: row.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        row.recordVersionId,
                        RecordIdentity(
                          universeId: universe,
                          recordId: row.identity.recordId,
                          recordKind: row.identity.recordKind,
                        ),
                        row.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              );
        });
        final unscoped = await open();
        await expectLater(
          tool(
            writer,
            check(unscoped.contextId, world: const Selector('Campaign')),
            ValidationV3.fromWire,
          ),
          throwsA(isA<WorldScopeConflictError>()),
        );
        await grant([recordWorld(f.id(50))]);
        final scoped = await open();
        final invalid = [
          CreateEntityOperation(clientRef: '', record: f.entity()),
        ];
        expect(
          await tool(
            writer,
            check(
              scoped.contextId,
              world: const Selector('Campaign'),
              operations: invalid,
            ),
            ValidationV3.fromWire,
          ),
          isA<RestrictedValidation>(),
        );
        await expectLater(
          tool(
            writer,
            check(
              scoped.contextId,
              world: const Selector('Hidden'),
              operations: invalid,
            ),
            ValidationV3.fromWire,
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('validation:'), hasLength(1));
          expect(await s.workflows(universe).keys('proposal:'), isEmpty);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
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
        const libraryRequest = LibraryEngineRequest(universe: selector);
        WireFields writing(CanonicalValue value) => WireFields(
          WireFields(value, {
            'storage',
            'worlds',
            'contexts',
            'continuities',
            'writing',
          }).require('writing'),
          {'proposals', 'approved'},
        );
        final beforeApproval = writing(await author.execute(libraryRequest));
        expect(beforeApproval.array('proposals'), hasLength(1));
        expect(beforeApproval.array('approved'), isEmpty);
        await author.execute(approve);
        final approvedWriting = writing(await author.execute(libraryRequest));
        expect(approvedWriting.array('proposals'), hasLength(1));
        expect(approvedWriting.array('approved'), hasLength(1));
        final historical = WireFields(
          approvedWriting.array('approved').single,
          {'candidate', 'validation_run', 'label'},
        );
        expect(
          ProposalRef.fromWire(historical.require('candidate')),
          reference,
        );
        expect(
          historical.string('validation_run'),
          report.execution.runId.value,
        );
        final commit = CommitRequest(
          universe: selector,
          universeId: universe,
          proposalReference: reference,
          expectedBaseRevision: opened.frame.revision,
          validationRun: report.execution.runId,
          idempotencyKey: 'publish',
        );
        final receipt = await tool(writer, commit, CommitReceipt.fromWire);
        final publishedLibrary = writing(await author.execute(libraryRequest));
        expect(publishedLibrary.array('proposals'), isEmpty);
        expect(
          publishedLibrary.require('approved').toText(),
          approvedWriting.require('approved').toText(),
        );
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
        final recoveredLibrary = writing(await author.execute(libraryRequest));
        expect(
          recoveredLibrary.require('proposals').toText(),
          publishedLibrary.require('proposals').toText(),
        );
        expect(
          recoveredLibrary.require('approved').toText(),
          publishedLibrary.require('approved').toText(),
        );
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
      test('state and plain facts preserve initialization evidence after its assertion leaves canon', () async {
        var author = await runtime.connect(hello(authorId));
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
        StoredVersion row(RecordVersion source) => StoredVersion.build(
          source.recordVersionId,
          RecordIdentity(
            universeId: universe,
            recordId: source.identity.recordId,
            recordKind: source.identity.recordKind,
          ),
          CanonicalValue.parseWireJson(
            source.payload.toWire().toText().replaceAll(
              f.u.value,
              universe.value,
            ),
          ),
        );
        var head = RevisionId.parse(created.string('revision'));
        Future<RevisionId> publish(
          String key,
          List<StoredVersion> records, {
          List<RecordId> remove = const [],
        }) async {
          head = await store.transaction((s) async {
            final membership = await s
                .kernel(universe)
                .journal
                .snapshot(continuity, head);
            return s
                .kernel(universe)
                .commit(
                  CommitInput(
                    universe: universe,
                    continuity: continuity,
                    expectedHead: head,
                    principal: PrincipalId.generate(),
                    decision: 'Disposable state setup',
                    reason: key,
                    idempotencyKey: key,
                    changes: [
                      for (final r in records)
                        Assignment(
                          recordId: r.identity.recordId,
                          expected: membership[r.identity.recordId],
                          next: r,
                        ),
                      for (final id in remove)
                        Assignment(
                          recordId: id,
                          expected: membership[id],
                          next: null,
                        ),
                    ],
                  ),
                );
          });
          return head;
        }

        final base = objects.fixture();
        objects.edit(base, 4, {
          'labels': CanonicalObject([MapEntry('en', CanonicalString('Cedar'))]),
          'worldAssociations': CanonicalArray([
            WorldAssociation(
              world: recordWorld(f.id(50)),
              role: 'setting',
              validity: const UnspecifiedValidity(),
              qualifiers: {},
            ).toWire(),
          ]),
        });
        base.addAll([
          f.row(
            10,
            CalendarRecord(
              namespace: 'test',
              key: 'clock',
              labels: {},
              unitStructure: {},
            ),
          ),
          f.row(
            99,
            RepresentedContextRecord(
              universe: f.u,
              kind: const ObjectiveContext(),
              labels: {},
            ),
          ),
          f.row(50, WorldRecord(selector: 'Campaign')),
          f.row(51, WorldRecord(selector: 'Private')),
          f.row(12, objects.assertion(6, mode: AttributeMode.initialValue)),
        ]);
        final templateRevision = await publish(
          'template',
          base.map(row).toList(),
        );
        final instance = objects.assertion(20);
        final initialized = AssertionRecord.fromWire(
          CanonicalObject([
            ...instance.toWire().fields.where((e) => e.key != 'basis'),
            MapEntry(
              'basis',
              InstanceInitializationBasis(
                VersionRef(universe: f.u, record: f.id(21), version: f.ver(21)),
                VersionRef(universe: f.u, record: f.id(12), version: f.ver(12)),
                templateRevision,
              ).toWire(),
            ),
          ]),
        );
        await publish('initialize', [
          row(f.row(20, objects.proposition(4))),
          row(
            f.row(
              21,
              EventRecord(
                occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
                time: ExactTime(objects.cal, '10'),
                participants: [EventParticipant(f.ref(4), 'starting_instance')],
                labels: {},
              ),
            ),
          ),
          row(f.row(22, initialized)),
        ]);
        Future<OpenedContext> open(NativePostgresConnection connection) => tool(
          connection,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(f.id(99)),
            temporalQuery: AtFrameTime(ExactTime(objects.cal, '15')),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        GetStateRequest stateRequest(
          ContextId context, {
          RecordId? event,
          EventTimeSide? side,
        }) => GetStateRequest(
          universe: selector,
          contextId: context,
          entityIds: [f.id(4)],
          predicateFilters: [f.id(5)],
          event: event,
          eventSide: side,
        );
        ReadFactsRequest factsRequest(ContextId context) => ReadFactsRequest(
          universe: selector,
          contextId: context,
          objectNames: ['Cedar'],
        );
        CanonicalValue field(CanonicalValue value, String key) =>
            (value as CanonicalObject).fields
                .singleWhere((e) => e.key == key)
                .value;
        List<CanonicalValue> list(CanonicalValue value, String key) =>
            (field(value, key) as CanonicalArray).items;
        final opened = await open(author);
        final state = await tool(
          author,
          stateRequest(opened.contextId),
          State.fromWire,
        );
        expect(state.assertions.single.identity.recordId, f.id(22));
        expect(state.objects.single.initializationReceipts, hasLength(1));
        final facts = await tool(
          author,
          factsRequest(opened.contextId),
          (v) => v,
        );
        final object = list(facts, 'objects').single;
        expect(wireString(field(object, 'identity')), 'resolved');
        expect(field(list(object, 'facts').single, 'value').toText(), 'true');
        expect(list(object, 'initial_value_candidates'), hasLength(1));
        expect(list(object, 'inherited_attributes'), hasLength(1));
        final before = await tool(
          author,
          stateRequest(
            opened.contextId,
            event: f.id(21),
            side: EventTimeSide.before,
          ),
          State.fromWire,
        );
        final after = await tool(
          author,
          stateRequest(
            opened.contextId,
            event: f.id(21),
            side: EventTimeSide.after,
          ),
          State.fromWire,
        );
        expect(before.assertions, isEmpty);
        expect(after.assertions, hasLength(1));
        await publish(
          'remove assertion and add private namesake',
          [
            row(
              f.row(
                24,
                EntityRecord(
                  names: [],
                  classificationResolution:
                      ClassificationResolution.unclassified,
                  labels: {'en': 'Cedar'},
                  metadata: {},
                  worldAssociations: [
                    WorldAssociation(
                      world: recordWorld(f.id(51)),
                      role: 'setting',
                      validity: const UnspecifiedValidity(),
                      qualifiers: {},
                    ),
                  ],
                ),
              ),
            ),
          ],
          remove: [f.id(22)],
        );
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(
          (await tool(
            author,
            factsRequest(opened.contextId),
            (v) => v,
          )).toText(),
          facts.toText(),
        );
        final fresh = await open(author);
        final ambiguous = await tool(
          author,
          factsRequest(fresh.contextId),
          (v) => v,
        );
        expect(
          wireString(field(list(ambiguous, 'objects').single, 'identity')),
          'ambiguous',
        );
        expect(
          field(list(ambiguous, 'objects').single, 'matches').toText(),
          '2',
        );
        final retained = await tool(
          author,
          stateRequest(fresh.contextId),
          State.fromWire,
        );
        expect(retained.assertions, isEmpty);
        expect(
          retained.objects.single.initializationReceipts,
          state.objects.single.initializationReceipts,
        );
        expect(
          retained.objects.single.initializationHistoryCoverage,
          Coverage.complete,
        );
        final contracts = await tool(
          author,
          ReadContractsRequest(universe: selector, contextId: fresh.contextId),
          (v) => v,
        );
        expect(wireString(field(contracts, 'coverage')), 'bounded');
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: [recordWorld(f.id(50))],
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        final writer = await runtime.connect(hello(writerId));
        final scoped = await open(writer);
        final restricted = await tool(
          writer,
          stateRequest(scoped.contextId),
          State.fromWire,
        );
        expect(restricted.objects.single.initializationReceipts, isEmpty);
        expect(
          restricted.objects.single.initializationHistoryCoverage,
          Coverage.restricted,
        );
        final scopedFacts = await tool(
          writer,
          factsRequest(scoped.contextId),
          (v) => v,
        );
        expect(
          wireString(field(list(scopedFacts, 'objects').single, 'identity')),
          'resolved',
        );
        expect(wireString(field(scopedFacts, 'coverage')), 'restricted');
        final scopedContracts = await tool(
          writer,
          ReadContractsRequest(universe: selector, contextId: scoped.contextId),
          (v) => v,
        );
        expect(wireString(field(scopedContracts, 'coverage')), 'restricted');
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        await expectLater(
          tool(writer, stateRequest(scoped.contextId), State.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(writer, factsRequest(scoped.contextId), (v) => v),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(
            writer,
            ReadContractsRequest(
              universe: selector,
              contextId: scoped.contextId,
            ),
            (v) => v,
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });
      test('ordinary writing checks retain a provisional exact candidate and recover it without approving or publishing', () async {
        var author = await runtime.connect(hello(authorId));
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
        final opened = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        final request = CheckChangesRequest(
          universe: selector,
          contextId: opened.contextId,
          units: [
            units.declaration(name: 'league', symbol: 'lg', introduce: true),
          ],
        );
        final check = await tool(author, request, WritingCheck.fromWire);
        expect(check.candidateHandle, isNotNull);
        expect(check.clarifications, isEmpty);
        final validation =
            ValidationV3.fromWire(check.validation!) as EvaluatedValidation;
        final candidate = ProposalId.parse(check.candidateHandle!);
        final get = GetProposalRequest(
          universe: selector,
          proposalId: candidate,
          version: BigInt.one,
        );
        final view = await tool(
          author,
          get,
          ProposalViewResult.fromWire,
        ) as FrozenProposalView;
        final proposal = view.proposal;
        expect(proposal.submission, Submission.draft);
        expect(proposal.operations.single, isA<DefineUnitOperation>());
        final ref = ProposalRef(
          proposalId: candidate,
          version: proposal.version,
          digest: proposal.digest,
        );
        await expectLater(
          author.execute(
            ApproveEngineRequest(
              universe: selector,
              proposalReference: ref,
              validationRun: validation.execution.runId,
            ),
          ),
          throwsA(isA<ApprovalStaleError>()),
        );
        final impact = await tool(
          author,
          ProposalImpactRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: ref,
            scope: CheckScope.universe,
            byteBudget: 65536,
          ),
          Impact.fromWire,
        );
        expect(impact.toWire().toText(), check.impact!.toText());
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        final retry = await tool(author, request, WritingCheck.fromWire);
        expect(retry.candidateHandle, check.candidateHandle);
        final repeated =
            ValidationV3.fromWire(retry.validation!) as EvaluatedValidation;
        expect(
          repeated.execution.inputDigest,
          validation.execution.inputDigest,
        );
        expect(repeated.execution.runId, isNot(validation.execution.runId));
        expect(
          (await tool(
            author,
            get,
            ProposalViewResult.fromWire,
          ) as FrozenProposalView).proposal.digest,
          proposal.digest,
        );
        final clarified = await tool(
          author,
          CheckChangesRequest(
            universe: selector,
            contextId: opened.contextId,
            questions: ['Which unit applies?'],
          ),
          WritingCheck.fromWire,
        );
        expect(clarified.candidateHandle, isNull);
        expect(clarified.clarifications, ['Which unit applies?']);
        final withdrawn = await tool(
          author,
          WithdrawProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: ref,
            idempotencyKey: 'withdraw-writing',
          ),
          Proposal.fromWire,
        );
        expect(withdrawn.withdrawn, isTrue);
        expect(
          (await tool(
            author,
            DescribeSummaryRequest(universe: selector),
            Description.fromWire,
          )).continuities.single.revisionId,
          opened.frame.revision,
        );
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          tool(writer, get, ProposalViewResult.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(writer, request, WritingCheck.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final writerContext = await tool(
          writer,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        await expectLater(
          tool(
            writer,
            CheckChangesRequest(
              universe: selector,
              contextId: writerContext.contextId,
              units: request.units,
            ),
            WritingCheck.fromWire,
          ),
          throwsA(isA<PolicyDeniedError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).journal.head(continuity),
            opened.frame.revision,
          );
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
      });
      test('private source preparation, inspection, publication and rejection retain exact author decisions through reopen', () async {
        var author = await runtime.connect(hello(authorId));
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
        final opened = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        Future<WritingCheck> draft(String name) => tool(
          author,
          CheckChangesRequest(
            universe: selector,
            contextId: opened.contextId,
            units: [
              units.declaration(name: name, symbol: name, introduce: true),
            ],
          ),
          WritingCheck.fromWire,
        );
        final candidate = ProposalId.parse(
          (await draft('league')).candidateHandle!,
        );
        const source = '\uFEFFAuthor: é😀\r\nA league is an authored unit.';
        Future<CanonicalValue> act(AuthorWritingAction action) =>
            author.execute(
              AuthorWritingEngineRequest(universe: selector, action: action),
            );
        WireFields review(CanonicalValue value) => WireFields(value, {
          'acceptance_options',
          'summary',
          'candidate',
          'validation',
          'impact',
          'publishable',
          'review',
        });
        final plainPrepare = PrepareWritingAction(
          candidate: candidate,
          label: 'Author passage',
          text: source,
        );
        await expectLater(act(plainPrepare), throwsA(isA<PolicyDeniedError>()));
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('source-version:'), isEmpty);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
        final prepare = PrepareContractsWritingAction(
          candidate: candidate,
          label: 'Author passage',
          text: source,
        );
        final prepared = review(await act(prepare));
        final ref = ProposalRef.fromWire(prepared.require('candidate'));
        expect(ref.version, BigInt.two);
        expect(prepared.boolean('publishable'), isTrue);
        final frozen = await tool(
          author,
          GetProposalRequest(
            universe: selector,
            proposalId: ref.proposalId,
            version: ref.version,
          ),
          ProposalViewResult.fromWire,
        ) as FrozenProposalView;
        final anchor = frozen.proposal.operations
            .whereType<AddSourceAnchorOperation>()
            .single
            .record;
        expect(anchor.excerpt, source);
        expect(
          anchor.excerptDigest,
          sha256.convert(utf8.encode(source)).toString(),
        );
        final sourceVersion = frozen.proposal.operations
            .whereType<RecordNarrativeReferenceOperation>()
            .map((op) => op.payload)
            .whereType<SourceVersionRecord>()
            .single;
        expect(sourceVersion.byteSize, BigInt.from(utf8.encode(source).length));
        expect(
          sourceVersion.importActor.value,
          authorId.value.replaceFirst('prf_', 'prn_'),
        );
        final retry = review(await act(prepare));
        expect(
          ProposalRef.fromWire(retry.require('candidate')).toWire().toText(),
          ref.toWire().toText(),
        );
        final rejectedCandidate = ProposalId.parse(
          (await draft('furlong')).candidateHandle!,
        );
        final reject = RejectWritingAction(candidate: rejectedCandidate);
        final rejected = Proposal.fromWire(await act(reject));
        expect(rejected.withdrawn, isTrue);
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).journal.head(continuity),
            opened.frame.revision,
          );
          expect(
            await s.workflows(universe).keys('source-version:'),
            hasLength(1),
          );
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
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
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            AuthorWritingEngineRequest(universe: selector, action: prepare),
          ),
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
        final inspected = review(
          await act(InspectWritingAction(candidate: ref)),
        );
        expect(
          ProposalRef.fromWire(inspected.require('candidate'))
              .toWire()
              .toText(),
          ref.toWire().toText(),
        );
        expect(inspected.boolean('publishable'), isTrue);
        final report = ValidationV3.fromWire(inspected.require('validation'));
        final publish = PublishWritingAction(
          candidate: ref,
          validationRun: report.execution!.runId,
          idempotencyKey: 'source-publish',
        );
        final published = Envelope.fromWire(
          await act(publish),
          CommitReceipt.fromWire,
        );
        expect(published.frame!.revision, opened.frame.revision);
        await store.transaction((s) async {
          final version = StoredVersion.build(
            RecordVersionId.generate(),
            RecordIdentity(
              universeId: universe,
              recordId: RecordId.generate(),
              recordKind: RecordKind.entity,
            ),
            EntityRecord(
              names: [],
              classificationResolution: ClassificationResolution.unclassified,
              worldAssociations: [],
              labels: {},
              metadata: {},
            ).toWire(),
          );
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: published.result.revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable advance',
                  reason: 'Disposable advance',
                  idempotencyKey: 'after-source-publish',
                  changes: [
                    Assignment(
                      recordId: version.identity.recordId,
                      next: version,
                    ),
                  ],
                ),
              );
        });
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        final recovered = Envelope.fromWire(
          await act(publish),
          CommitReceipt.fromWire,
        );
        expect(
          recovered.result.toWire().toText(),
          published.result.toWire().toText(),
        );
        expect(
          Proposal.fromWire(await act(reject)).toWire().toText(),
          rejected.toWire().toText(),
        );
        await expectLater(act(prepare), throwsA(isA<ApprovalStaleError>()));
        await expectLater(
          act(
            PublishWritingAction(
              candidate: ref,
              validationRun: ValidationRunId.generate(),
              idempotencyKey: publish.idempotencyKey,
            ),
          ),
          throwsA(isA<IdempotencyKeyReusedError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.workflows(universe).keys('source-version:'),
            hasLength(1),
          );
          expect(await s.workflows(universe).keys('approval:'), hasLength(1));
        });
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
