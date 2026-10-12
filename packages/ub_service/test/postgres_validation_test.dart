@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/postgres_validation.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

import 'operation_compilation_test.dart' as f;
import 'structural_checks_test.dart' as structure;
import 'rule_checks_test.dart' as frames;
import 'source_verification_test.dart' as sources;
import 'assessment_validation_test.dart' as assessments;
import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  late PostgresInstallationStore store;
  late Connection observer;
  late ProfileId owner, writer;
  late ContinuityId continuity;
  late Frame frame;
  late ContextId writerContext;
  var now = BigInt.from(100);
  const secret = 'disposable-proposal-profile';
  final hash = sha256.convert(utf8.encode(secret)).toString();
  Future<PostgresInstallationStore> open({bool create = false}) {
    final endpoint = Endpoint(
      host: '127.0.0.1',
      port: port!,
      database: 'ub_disposable',
      username: 'postgres',
    );
    const settings = ConnectionSettings(sslMode: SslMode.disable);
    return create
        ? PostgresInstallationStore.create(endpoint, settings: settings)
        : PostgresInstallationStore.openExisting(endpoint, settings: settings);
  }

  Future<T> run<T>(
    ProfileId actor,
    Future<T> Function(PostgresValidationWorkflow) action,
  ) => store.transaction((s) async {
    final authority = PostgresServiceAuthority(
      s.authority,
      epochSeconds: () => now,
    );
    final principal = await authority.authenticate(
      profile: actor,
      credential: Credential(secret),
    );
    return action(
      PostgresValidationWorkflow(
        session: s,
        universe: f.u,
        authority: authority,
        principal: principal,
        epochSeconds: () => now,
      ),
    );
  });
  CreateProposalRequest create({
    String key = 'create',
    Submission submission = Submission.submitted,
    int record = 10,
  }) => CreateProposalRequest(
    universe: const Selector('Disposable universe'),
    universeId: f.u,
    contextId: writerContext,
    operations: [
      CreateEntityOperation(clientRef: f.id(record).value, record: f.entity()),
    ],
    submission: submission,
    rationale: 'Disposable authoring',
    idempotencyKey: key,
  );
  ProposalRef reference(Proposal p) => ProposalRef(
    proposalId: p.proposalId,
    version: p.version,
    digest: p.digest,
  );
  Future<Proposal> propose(WorkflowRequest request) => run(
    writer,
    (w) => w.proposeRequest(request, isValidationActive: (_) => false),
  );
  Future<ValidationV3> validate(Proposal p) => run(
    writer,
    (w) => w.validateProposalRequest(
      ProposalValidationRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        checkScope: CheckScope.candidate,
      ),
    ),
  );
  Future<OpenedContext> openContext(
    ProfileId actor, {
    RevisionSelector revision = const HeadRevisionSelector(),
    UniverseId? guard,
    RecordId? represented,
  }) => run(
    actor,
    (w) => w.openContext(
      OpenContextRequest(
        universe: const Selector('Disposable universe'),
        universeId: guard ?? f.u,
        continuityId: continuity,
        revision: revision,
        representedContext: ContextIdSelector(represented ?? f.id(99)),
        temporalQuery: const TimelessFrameTime(),
        temporalSystems: [],
        perspective: const AuthorPerspective(),
      ),
    ),
  );
  Future<void> refreshContext() async {
    final opened = await openContext(writer);
    writerContext = opened.contextId;
    frame = opened.frame;
  }

  Future<({Proposal proposal, SourceAssessmentV1 body})>
  researchedProposal() async {
    await store.transaction((s) async {
      await s
          .workflows(f.u)
          .compareAppend(
            {},
            sources.staging(sources.source()).entries.toList(),
          );
      final rows = [
        f.row(
          1,
          SourceRecord(
            label: 'External source',
            origin: const OriginMetadata(),
            versions: [f.id(2)],
          ),
        ),
        f.row(2, sources.source()),
      ];
      await s
          .kernel(f.u)
          .commit(
            CommitInput(
              universe: f.u,
              continuity: continuity,
              expectedHead: frame.revision,
              principal: PrincipalId.generate(),
              decision: 'Source fixture',
              reason: 'Retained external research',
              idempotencyKey: 'sources',
              changes: [
                for (final version in rows)
                  Assignment(
                    recordId: version.identity.recordId,
                    expected: null,
                    next: StoredVersion.build(
                      version.recordVersionId,
                      version.identity,
                      version.payload.toWire(),
                    ),
                  ),
              ],
            ),
          );
    });
    await refreshContext();
    final proposal = await propose(create());
    var wire = accounting.replace(assessments.body().toWire(), [
      'proposal',
    ], reference(proposal).toWire());
    wire = accounting.replace(wire, ['base_frame'], frame.toWire());
    wire = accounting.replace(wire, [
      'assessor',
      'principal',
    ], CanonicalString(writer.value.replaceFirst('prf_', 'prn_')));
    return (proposal: proposal, body: SourceAssessmentV1.fromWire(wire));
  }

  Future<AssessmentSelection> attach(
    Proposal p,
    SourceAssessmentV1 body, {
    String key = 'attach',
    BigInt? generation,
  }) => run(
    writer,
    (w) => w.assessmentRequest(
      AttachAssessmentRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        expectedSelectionGeneration: generation ?? BigInt.zero,
        body: body,
        idempotencyKey: key,
      ),
    ),
  );
  Future<AssessmentSelection> select(
    Proposal p,
    AssessmentRef? selected,
    BigInt generation,
    String key,
  ) => run(
    writer,
    (w) => w.assessmentRequest(
      SelectAssessmentRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        expectedSelectionGeneration: generation,
        assessmentReference: selected,
        idempotencyKey: key,
      ),
    ),
  );
  CommitRequest request(
    Proposal p,
    ValidationRunId validation, {
    String key = 'commit',
    RevisionId? base,
  }) => CommitRequest(
    universe: const Selector('Disposable universe'),
    universeId: f.u,
    proposalReference: reference(p),
    expectedBaseRevision: base ?? frame.revision,
    validationRun: validation,
    idempotencyKey: key,
  );
  Future<CommitReceipt> commit(CommitRequest request) =>
      run(writer, (w) => w.commit(request, isValidationActive: (_) => false));
  final stale = throwsA(isA<ApprovalStaleError>());
  group(
    'PostgreSQL exact proposal publication',
    () {
      setUp(() async {
        now = BigInt.from(100);
        owner = ProfileId.generate();
        writer = ProfileId.generate();
        continuity = ContinuityId.generate();
        observer = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        store = await open(create: true);
        final base = await store.transaction((s) async {
          await s.authority.enroll(id: owner, credentialHash: hash);
          await s.authority.enroll(
            id: writer,
            credentialHash: hash,
            actor: owner,
          );
          final genesis = await s.createUniverse(
            actor: owner,
            universe: f.u,
            name: 'Disposable universe',
            continuity: continuity,
            principal: PrincipalId.generate(),
          );
          // Seed only the pre-existing represented context; authoring below uses
          // real proposal creation, factual evaluation and private author approval.
          final context = structure.context(99);
          final revision = await s
              .kernel(f.u)
              .commit(
                CommitInput(
                  universe: f.u,
                  continuity: continuity,
                  expectedHead: genesis,
                  principal: PrincipalId.generate(),
                  decision: 'Fixture context',
                  reason: 'Disposable setup',
                  idempotencyKey: 'context',
                  changes: [
                    Assignment(
                      recordId: context.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        context.recordVersionId,
                        context.identity,
                        context.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              );
          await s.authority.putGrant(
            actor: owner,
            grant: GrantSpec(
              profileId: writer,
              universeId: f.u,
              worlds: null,
              propose: true,
              edit: true,
              protected: false,
            ),
            epochSeconds: now,
          );
          return revision;
        });
        frame = Frame(
          universe: f.u,
          continuity: continuity,
          revision: base,
          context: f.ref(99),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        );
        await refreshContext();
      });
      tearDown(() async {
        await store.close();
        try {
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(f.u)} CASCADE',
          );
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
        }
      });
      test('assessment attachment binds source bytes through exact approval, publication and reconnect retry', () async {
        final researched = await researchedProposal();
        final p = researched.proposal;
        final selection = await attach(p, researched.body);
        expect(selection.generation, BigInt.one);
        final key = 'assessment:${selection.selected!.assessmentId.value}';
        final original = await store.transaction(
          (s) => s.workflows(f.u).get(key),
        );
        final checked = await validate(p);
        expect(
          (checked as EvaluatedValidation).assessment,
          isA<BoundAssessment>(),
        );
        expect(checked.submittedInput, isA<SourceAssessedCandidateInput>());
        expect(checked.finalBindingDigest, isNotNull);
        await run(
          owner,
          (w) => w.approve(reference(p), checked.execution.runId),
        );
        final receipt = await commit(request(p, checked.execution.runId));
        await store.close();
        store = await open();
        expect(
          (await attach(p, researched.body)).toWire().toText(),
          selection.toWire().toText(),
        );
        expect(
          (await commit(request(p, checked.execution.runId))).toWire().toText(),
          receipt.toWire().toText(),
        );
        expect(
          (await store.transaction((s) => s.workflows(f.u).get(key)))!.toText(),
          original!.toText(),
        );
      });
      test('assessment clearing and reselection preserve evidence and invalidate prior approval', () async {
        final researched = await researchedProposal();
        final p = researched.proposal;
        final first = await attach(p, researched.body);
        final checked = await validate(p);
        await run(
          owner,
          (w) => w.approve(reference(p), checked.execution!.runId),
        );
        final cleared = await select(p, null, BigInt.one, 'clear');
        expect(cleared.generation, BigInt.two);
        expect(cleared.selected, isNull);
        await expectLater(commit(request(p, checked.execution!.runId)), stale);
        expect(
          (await attach(p, researched.body)).toWire().toText(),
          first.toWire().toText(),
        );
        final restored = await select(
          p,
          first.selected,
          BigInt.two,
          'reselect',
        );
        expect(restored.generation, BigInt.from(3));
        expect(
          restored.selected!.toWire().toText(),
          first.selected!.toWire().toText(),
        );
        await expectLater(
          attach(p, researched.body, generation: BigInt.one),
          throwsA(isA<IdempotencyKeyReusedError>()),
        );
        await expectLater(select(p, null, BigInt.one, 'stale-clear'), stale);
        final again = await validate(p);
        await run(
          owner,
          (w) => w.approve(reference(p), again.execution!.runId),
        );
        await commit(
          request(p, again.execution!.runId, key: 'reselected-commit'),
        );
      });
      test('assessment attribution and unverifiable sources fail without retained selection or receipt', () async {
        final researched = await researchedProposal();
        final wrong = SourceAssessmentV1.fromWire(
          accounting.replace(researched.body.toWire(), [
            'assessor',
            'principal',
          ], CanonicalString(owner.value.replaceFirst('prf_', 'prn_'))),
        );
        await expectLater(
          attach(researched.proposal, wrong),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final wrongBytes = SourceAssessmentV1.fromWire(
          accounting.replace(researched.body.toWire(), [
            'sources',
            0,
            'blob_digest',
          ], CanonicalString('a' * 64)),
        );
        await expectLater(
          attach(researched.proposal, wrongBytes, key: 'unverified-source'),
          throwsA(isA<InvalidArgumentError>()),
        );
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('assessment-selection:'),
          ),
          isNull,
        );
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('assessment-receipt:'),
          ),
          isNull,
        );
        final first = await attach(researched.proposal, researched.body);
        expect(first.generation, BigInt.one);
      });
      test('creates, validates, requires exact author approval, publishes and retries after reconnect', () async {
        final proposal = await propose(create());
        expect(
          (await propose(create())).toWire().toText(),
          proposal.toWire().toText(),
        );
        final checked = await validate(proposal);
        final validation = checked.execution!;
        expect(validation.coverage, Coverage.complete);
        final publish = request(proposal, validation.runId);
        await expectLater(
          commit(publish),
          throwsA(isA<ApprovalRequiredError>()),
        );
        await expectLater(
          run(writer, (w) => w.approve(reference(proposal), validation.runId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await run(
          owner,
          (w) => w.approve(reference(proposal), validation.runId),
        );
        final receipt = await commit(publish);
        expect(receipt.revision, isNot(frame.revision));
        final saved = await store.transaction(
          (s) async => StoredProposal.fromWire(
            (await s.workflows(f.u).get(proposalKey(reference(proposal))))!,
          ),
        );
        await store.close();
        store = await open();
        expect(
          (await commit(publish)).toWire().toText(),
          receipt.toWire().toText(),
        );
        await expectLater(
          commit(request(proposal, validation.runId, base: receipt.revision)),
          throwsA(isA<IdempotencyKeyReusedError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(f.u).journal.head(continuity),
            receipt.revision,
          );
          final next = saved.changes.single.next!;
          expect(
            (await s.kernel(f.u).journal.load(next.versionId)).digest,
            next.digest,
          );
          expect(
            await s.kernel(f.u).journal.identityExists(next.identity.recordId),
            isTrue,
          );
        });
      });
      test(
        'new proposal version and withdrawal invalidate exact approval',
        () async {
          final original = await propose(create());
          final checked = await validate(original);
          await run(
            owner,
            (w) => w.approve(reference(original), checked.execution!.runId),
          );
          final revised = await propose(
            ReviseProposalRequest(
              universe: const Selector('Disposable universe'),
              contextId: writerContext,
              proposalReference: reference(original),
              operations: create().operations,
              submission: Submission.submitted,
              rationale: 'Revised exact input',
              idempotencyKey: 'revise',
            ),
          );
          await expectLater(
            commit(request(original, checked.execution!.runId)),
            stale,
          );
          await expectLater(
            run(
              owner,
              (w) => w.approve(reference(original), checked.execution!.runId),
            ),
            stale,
          );
          final checkedAgain = await validate(revised);
          await run(
            owner,
            (w) => w.approve(reference(revised), checkedAgain.execution!.runId),
          );
          await propose(
            WithdrawProposalRequest(
              universe: const Selector('Disposable universe'),
              contextId: writerContext,
              proposalReference: reference(revised),
              idempotencyKey: 'withdraw',
            ),
          );
          await expectLater(
            commit(
              request(
                revised,
                checkedAgain.execution!.runId,
                key: 'after-withdraw',
              ),
            ),
            stale,
          );
          expect(
            await store.transaction(
              (s) => s.kernel(f.u).journal.head(continuity),
            ),
            frame.revision,
          );
        },
      );
      test(
        'validation is immutable and approval does not cover another run',
        () async {
          final proposal = await propose(create());
          final checked = await validate(proposal);
          final runId = checked.execution!.runId;
          await run(owner, (w) => w.approve(reference(proposal), runId));
          final key = 'validation:${runId.value}';
          final before = await store.transaction(
            (s) => s.workflows(f.u).get(key),
          );
          await expectLater(
            store.transaction(
              (s) => s.workflows(f.u).put(key, const CanonicalNull()),
            ),
            throwsFormatException,
          );
          expect(
            (await store.transaction((s) => s.workflows(f.u).get(key)))!
                .toText(),
            before!.toText(),
          );
          final another = await validate(proposal);
          expect(another.execution!.runId, isNot(runId));
          await expectLater(
            commit(request(proposal, another.execution!.runId)),
            throwsA(isA<ApprovalRequiredError>()),
          );
          expect(
            await store.transaction(
              (s) => s.kernel(f.u).journal.head(continuity),
            ),
            frame.revision,
          );
        },
      );
      test(
        'current grant edit denial and revocation precede receipt retry',
        () async {
          final proposal = await propose(create());
          final checked = await validate(proposal);
          await run(
            owner,
            (w) => w.approve(reference(proposal), checked.execution!.runId),
          );
          final publish = request(proposal, checked.execution!.runId);
          await commit(publish);
          await store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: false,
                protected: false,
              ),
              epochSeconds: now,
            ),
          );
          await expectLater(
            commit(publish),
            throwsA(isA<InstallationException>()),
          );
          await store.transaction(
            (s) => s.authority.revoke(actor: owner, target: writer),
          );
          await expectLater(
            commit(publish),
            throwsA(isA<InstallationException>()),
          );
        },
      );
      test(
        'bounded delegated commit requires complete validation and live expiry',
        () async {
          final base = await store.transaction(
            (s) => s
                .kernel(f.u)
                .commit(
                  CommitInput(
                    universe: f.u,
                    continuity: continuity,
                    expectedHead: frame.revision,
                    principal: PrincipalId.generate(),
                    decision: 'Delegation fixture base',
                    reason: 'Existing predicate and entity',
                    idempotencyKey: 'delegation-base',
                    changes: [
                      for (final version in [
                        frames.fixture().first,
                        f.row(2, f.entity()),
                      ])
                        Assignment(
                          recordId: version.identity.recordId,
                          expected: null,
                          next: StoredVersion.build(
                            version.recordVersionId,
                            version.identity,
                            version.payload.toWire(),
                          ),
                        ),
                    ],
                  ),
                ),
          );
          frame = Frame(
            universe: f.u,
            continuity: continuity,
            revision: base,
            context: f.ref(99),
            time: const TimelessFrameTime(),
            perspective: const AuthorPerspective(),
          );
          Future<void> delegation(bool shared) => store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: true,
                protected: true,
                limits: GrantLimits(
                  entities: [f.id(2)],
                  predicates: [f.id(1)],
                  continuities: [continuity],
                  expiresAt: BigInt.from(200),
                  delegatedCommit: true,
                  allowShared: shared,
                ),
              ),
              epochSeconds: now,
            ),
          );
          await delegation(false);
          await refreshContext();
          final proposal = await propose(
            CreateProposalRequest(
              universe: const Selector('Disposable universe'),
              universeId: f.u,
              contextId: writerContext,
              operations: [
                DefinePropositionOperation(
                  clientRef: f.id(10).value,
                  record: PropositionRecord(
                    subject: f.ref(2),
                    predicate: f.ref(1),
                    context: f.ref(99),
                    value: const BooleanValue(true),
                    quantification: Quantification.particular,
                  ),
                ),
              ],
              submission: Submission.submitted,
              rationale: 'Delegated factual edit',
              idempotencyKey: 'delegated-proposal',
            ),
          );
          final checked = await validate(proposal);
          expect(checked.execution!.coverage, Coverage.complete);
          final publish = request(proposal, checked.execution!.runId);
          await expectLater(
            commit(publish),
            throwsA(isA<ApprovalRequiredError>()),
          );
          await delegation(true);
          final receipt = await commit(publish);
          expect(receipt.revision, isNot(frame.revision));
          expect(
            await store.transaction(
              (s) => s.workflows(f.u).latestKey('approval:'),
            ),
            isNull,
          );
          now = BigInt.from(200);
          await expectLater(
            commit(publish),
            throwsA(isA<InstallationException>()),
          );
        },
      );
      test('moved head blocks approval and publication without partial operation retention', () async {
        final proposal = await propose(create());
        final checked = await validate(proposal);
        await run(
          owner,
          (w) => w.approve(reference(proposal), checked.execution!.runId),
        );
        final version = f.row(400, f.entity());
        final moved = await store.transaction(
          (s) => s
              .kernel(f.u)
              .commit(
                CommitInput(
                  universe: f.u,
                  continuity: continuity,
                  expectedHead: frame.revision,
                  principal: PrincipalId.generate(),
                  decision: 'Independent fixture change',
                  reason: 'Stale base check',
                  idempotencyKey: 'move-head',
                  changes: [
                    Assignment(
                      recordId: version.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        version.recordVersionId,
                        version.identity,
                        version.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              ),
        );
        await expectLater(
          run(
            owner,
            (w) => w.approve(reference(proposal), checked.execution!.runId),
          ),
          stale,
        );
        await expectLater(
          commit(request(proposal, checked.execution!.runId)),
          throwsA(isA<BaseRevisionConflictError>()),
        );
        expect(
          await store.transaction(
            (s) => s.kernel(f.u).journal.head(continuity),
          ),
          moved,
        );
        expect(
          await store.transaction(
            (s) =>
                s.workflows(f.u).latestKey('request:${writer.value}:commit:'),
          ),
          isNull,
        );
      });
      test('contexts are principal-bound, expire and reject changed scope before retention', () async {
        final foreign = await openContext(owner);
        final original = writerContext;
        writerContext = foreign.contextId;
        await expectLater(
          propose(create()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        writerContext = original;
        now += BigInt.from(3601);
        await expectLater(
          propose(create()),
          throwsA(isA<ContextExpiredError>()),
        );
        now = BigInt.from(100);
        await store.transaction(
          (s) => s.authority.putGrant(
            actor: owner,
            grant: GrantSpec(
              profileId: writer,
              universeId: f.u,
              worlds: null,
              propose: true,
              edit: false,
              protected: false,
            ),
            epochSeconds: now,
          ),
        );
        await expectLater(
          propose(create()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('proposal:'),
          ),
          isNull,
        );
      });
      test('opening preserves exact revisions and validation rejects a different pinned context', () async {
        final proposal = await propose(create());
        final original = frame;
        final version = f.row(400, f.entity());
        final moved = await store.transaction(
          (s) => s
              .kernel(f.u)
              .commit(
                CommitInput(
                  universe: f.u,
                  continuity: continuity,
                  expectedHead: frame.revision,
                  principal: PrincipalId.generate(),
                  decision: 'Context fixture movement',
                  reason: 'Pinned context check',
                  idempotencyKey: 'context-move',
                  changes: [
                    Assignment(
                      recordId: version.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        version.recordVersionId,
                        version.identity,
                        version.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              ),
        );
        final historical = await openContext(
          writer,
          revision: ExactRevisionSelector(revisionId: original.revision),
        );
        expect(historical.frame.revision, original.revision);
        final latest = await openContext(writer);
        expect(latest.frame.revision, moved);
        writerContext = latest.contextId;
        await expectLater(validate(proposal), stale);
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('validation:'),
          ),
          isNull,
        );
      });
      test('unknown represented context and mismatched universe guard fail opening', () async {
        await expectLater(
          openContext(writer, represented: f.id(777)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          openContext(writer, guard: UniverseId.generate()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });
      test(
        'continuity and entity boundaries deny proposal retention atomically',
        () async {
          await store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: true,
                protected: false,
                limits: GrantLimits(continuities: [ContinuityId.generate()]),
              ),
              epochSeconds: now,
            ),
          );
          await refreshContext();
          await expectLater(
            propose(create()),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          expect(
            await store.transaction(
              (s) => s.workflows(f.u).latestKey('proposal:'),
            ),
            isNull,
          );
          await store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: true,
                protected: false,
                limits: GrantLimits(entities: [f.id(500)]),
              ),
              epochSeconds: now,
            ),
          );
          await refreshContext();
          await expectLater(
            propose(create()),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          expect(
            await store.transaction(
              (s) => s.workflows(f.u).latestKey('proposal:'),
            ),
            isNull,
          );
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for the owned disposable PostgreSQL fixture.'
        : false,
  );
}
