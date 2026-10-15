@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/operation_state.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/proposal_validation.dart';
import 'package:ub_service/sqlite_validation.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_service/validation_scheduler.dart';
import 'package:ub_service/validation_worker.dart';
import 'package:ub_service/context_binding.dart';
import 'package:ub_service/instance_initialization.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'proposal_authorization_test.dart' as permissions;
import 'rule_checks_test.dart' as frames;
import 'structural_checks_test.dart' as structure;
import 'assessment_validation_test.dart' as assessments;
import 'required_evidence_sources_test.dart' as evidence;
import 'required_evidence_reviews_test.dart' as reviews;
import 'required_event_evidence_test.dart' as event_evidence;
import 'source_verification_test.dart' as sources;
import 'instance_initialization_test.dart' as initialization;
import 'effective_objects_test.dart' as objects;
import 'writing_projection_test.dart' as writing;
import 'action_checks_test.dart' as actions;
import 'resource_checks_test.dart' as resources;
import 'knowledge_checks_test.dart' as knowledge;
import 'writing_binding_test.dart' as named;
import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;

void main() {
  late Directory directory;
  late SqliteInstallationStore installation;
  late InstallationAuthority authority;
  late InstallationPrincipal author, writer;
  late OwnedSqliteDatabase package;
  late SqliteKernel kernel;
  late SqliteValidationWorkflow service;
  late StoredProposal proposal;
  late CheckedValidation checked;
  final continuity = frames.frame().continuity;
  GrantSpec grant() => GrantSpec(
    profileId: writer.id,
    universeId: f.u,
    worlds: null,
    propose: true,
    edit: true,
    protected: true,
  );
  List<RecordVersion> canon(ContinuityId continuity, RevisionId revision) => [
    for (final v in kernel.journal.snapshot(continuity, revision).values)
      RecordVersion.fromWire(kernel.journal.load(v).toCanonical()),
  ];
  CommitInput input(String key, List<RecordVersion> rows) => CommitInput(
    universe: f.u,
    continuity: continuity,
    expectedHead: kernel.journal.head(continuity),
    principal: PrincipalId.parse(author.id.value.replaceFirst('prf_', 'prn_')),
    decision: 'Already admitted disposable fixture',
    reason: 'Functional fixture',
    idempotencyKey: key,
    changes: rows.map(
      (r) => Assignment(
        recordId: r.identity.recordId,
        next: StoredVersion(
          versionId: r.recordVersionId,
          identity: r.identity,
          payload: r.payload.toWire(),
          digest: r.payloadDigest,
        ),
      ),
    ),
  );
  setUp(() async {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-validation-owner-',
    );
    installation = SqliteInstallationStore.create(directory.path);
    authority = InstallationAuthority(installation);
    InstallationPrincipal authenticate(ProfileId id) => authority.authenticate(
      profile: id,
      credential: Credential(
        ProfileCredentialStore.read(root: directory.path, profile: id),
      ),
    );
    author = authenticate(authority.initializeAuthor());
    writer = authenticate(authority.enroll(author));
    final path = '${directory.path}/packages/world.sqlite';
    package = OwnedSqliteDatabase.create(path);
    kernel = SqliteKernel(package.database, f.u);
    package.database.execute('BEGIN IMMEDIATE');
    kernel.journal.initialize(
      'Disposable world',
      continuity,
      PrincipalId.generate(),
    );
    package.database.execute('COMMIT');
    kernel.commit(input('context', [structure.context(99)]));
    package.close();
    authority.registerUniverse(author, name: 'World', path: path);
    authority.grant(author, grant());
    package = OwnedSqliteDatabase.openExisting(path);
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final head = kernel.journal.head(continuity);
    proposal = proposals.prepare(
      principal: writer.id,
      frame: Frame(
        universe: f.u,
        continuity: continuity,
        revision: head,
        context: f.ref(99),
        time: const TimelessFrameTime(),
        perspective: const AuthorPerspective(),
      ),
      base: canon(continuity, head),
    );
    WorkflowStorage(package.database)
        .compareAppend({}, [MapEntry(proposal.key, proposal.toWire())]);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final capture = await service.capture(proposal.reference);
    final result = await checkProposalCandidate(
      stored: proposal,
      universe: f.u,
      principal: writer.id,
      approvalAuthor: author.id,
      scope: null,
      preview: (input) => kernel
          .preview(input)
          .map((r) => RecordVersion.fromWire(r.toCanonical()))
          .toList(),
      readCanon: canon,
      readWorkflow: WorkflowStorage(package.database).get,
      readVersion: (id) =>
          RecordVersion.fromWire(kernel.journal.load(id).toCanonical()),
    );
    checked = CheckedValidation(
      proposalDigest: result.proposalDigest,
      validation: result.validation,
      admissible: result.admissible,
      capture: capture,
      report: capture.report(
        proposal: proposal.reference,
        baseFrame: proposal.proposal.baseFrame,
        execution: result.validation,
        finished: true,
      ),
    );
  });
  tearDown(() {
    package.close();
    installation.close();
    directory.deleteSync(recursive: true);
  });
  String key() => 'validation:${checked.validation.runId.value}';
  final stale = throwsA(isA<ApprovalStaleError>());

  QueuedProposalValidationRequest queued({
    CheckScope scope = CheckScope.candidate,
  }) => QueuedProposalValidationRequest(
    universe: const Selector('World'),
    universeId: f.u,
    contextId: proposals.contextId,
    proposalReference: proposal.reference,
    checkScope: scope,
    idempotencyKey: 'queued-check',
  );

  CreateProposalRequest creation({
    String key = 'native-create',
    int record = 20,
  }) => CreateProposalRequest(
    universe: const Selector('World'),
    universeId: f.u,
    contextId: proposals.contextId,
    operations: [
      CreateEntityOperation(clientRef: f.id(record).value, record: f.entity()),
    ],
    submission: Submission.draft,
    rationale: 'Native authoring',
    idempotencyKey: key,
  );
  ProposalRef reference(Proposal p) => ProposalRef(
    proposalId: p.proposalId,
    version: p.version,
    digest: p.digest,
  );
  Future<Proposal> propose(WorkflowRequest request) => service.propose(
    request,
    resolvedFrame: proposal.proposal.baseFrame,
    worldFocus: null,
    isValidationActive: (_) => false,
  );

  OpenContextRequest contextRequest({
    Perspective perspective = const AuthorPerspective(),
    FrameTime time = const TimelessFrameTime(),
    RepresentedContextSelector? represented,
  }) => OpenContextRequest(
    universe: const Selector('World'),
    universeId: f.u,
    continuityId: continuity,
    revision: const HeadRevisionSelector(),
    representedContext: represented ?? ContextIdSelector(f.id(99)),
    temporalQuery: time,
    temporalSystems: [],
    perspective: perspective,
  );

  test('private author review retains exact frozen history across revision and reopen', () async {
    SqliteValidationWorkflow owner() => SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: author,
    );
    await expectLater(
      service.review(proposal.reference),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final validationCount = WorkflowStorage(package.database)
        .keys('validation:')
        .length;
    await expectLater(
      service.writingAuthorReview(proposal.reference),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(
      WorkflowStorage(package.database).keys('validation:'),
      hasLength(validationCount),
    );
    final first = await owner().review(proposal.reference);
    final fields = WireFields(first, {
      'proposal',
      'changes',
      'diff',
      'footprint',
      'latest',
      'assessment_review',
    });
    expect(
      fields.require('proposal').toText(),
      proposal.proposal.toWire().toText(),
    );
    expect(fields.boolean('latest'), isTrue);
    final changes = fields.array('changes');
    final diff = fields.array('diff');
    expect(diff, hasLength(changes.length));
    for (var i = 0; i < diff.length; i++) {
      final entry = WireFields(diff[i], {'record', 'before', 'after'});
      expect(entry.require('before'), const CanonicalNull());
      expect(
        entry.require('after').toText(),
        proposal.changes[i].next!.toCanonical().toText(),
      );
    }
    expect(
      AssessmentReview.fromWire(fields.require('assessment_review')).envelope,
      isNull,
    );
    final revised = await propose(proposals.revise(proposal));
    final historical = await owner().review(proposal.reference);
    final old = WireFields(historical, {
      'proposal',
      'changes',
      'diff',
      'footprint',
      'latest',
      'assessment_review',
    });
    expect(old.boolean('latest'), isFalse);
    expect(old.require('diff').toText(), fields.require('diff').toText());
    await expectLater(
      owner().writingAuthorReview(proposal.reference),
      throwsA(isA<ApprovalStaleError>()),
    );
    kernel.commit(input('advance-after-review', [f.row(77, f.entity())]));
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final reopened = await owner().review(proposal.reference);
    expect(reopened.toText(), historical.toText());
    final latest = WireFields(await owner().review(reference(revised)), {
      'proposal',
      'changes',
      'diff',
      'footprint',
      'latest',
      'assessment_review',
    });
    expect(latest.boolean('latest'), isTrue);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test('private author review binds edited records to their pinned before versions', () async {
    final original = f.row(77, f.entity());
    kernel.commit(input('review-original', [original]));
    final owner = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: author,
    );
    final opened = await owner.openContext(contextRequest());
    final edit = await owner.proposeRequest(
      CreateProposalRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        operations: [
          AddNameOperation(
            record: f.ref(77),
            expectedVersion: f.ver(77),
            name: const ContextualName(
              text: 'Iris',
              validity: UnspecifiedValidity(),
            ),
          ),
        ],
        submission: Submission.draft,
        rationale: 'An explicit name',
        idempotencyKey: 'review-edit',
      ),
      isValidationActive: (_) => false,
    );
    final reviewed = await owner.review(reference(edit));
    final fields = WireFields(reviewed, {
      'proposal',
      'changes',
      'diff',
      'footprint',
      'latest',
      'assessment_review',
    });
    final diff = WireFields(fields.array('diff').single, {
      'record',
      'before',
      'after',
    });
    expect(diff.require('before').toText(), original.toWire().toText());
    final after = RecordVersion.fromWire(diff.require('after'));
    expect(after.recordVersionId, isNot(original.recordVersionId));
    expect((after.payload as EntityRecord).names.single.text, 'Iris');
    final later = RecordVersion.build(
      recordVersionId: f.ver(78),
      identity: original.identity,
      payload: f.patch<EntityRecord>(original.payload as EntityRecord, {
        'labels': CanonicalObject([
          MapEntry('en', CanonicalString('Later canon')),
        ]),
      }),
    );
    kernel.commit(
      CommitInput(
        universe: f.u,
        continuity: continuity,
        expectedHead: kernel.journal.head(continuity),
        principal: PrincipalId.parse(
          author.id.value.replaceFirst('prf_', 'prn_'),
        ),
        decision: 'Already admitted disposable edit',
        reason: 'Historical review fixture',
        idempotencyKey: 'review-concurrent-edit',
        changes: [
          Assignment(
            recordId: original.identity.recordId,
            expected: original.recordVersionId,
            next: StoredVersion(
              versionId: later.recordVersionId,
              identity: later.identity,
              payload: later.payload.toWire(),
              digest: later.payloadDigest,
            ),
          ),
        ],
      ),
    );
    // A review remains an exact historical read; approval separately checks head.
    expect((await owner.review(reference(edit))).toText(), reviewed.toText());
  });

  SqliteValidationWorkflow authorService() => SqliteValidationWorkflow(
    package: package,
    authority: authority,
    principal: author,
  );

  Future<ProposalId> writingDraft() async {
    final opened = await service.openContext(contextRequest());
    final result = await service.checkChangesRequest(
      CheckChangesRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        changes: [
          ObjectChange(
            name: 'Iris',
            introduce: true,
            facts: [
              FactChange(
                property: 'colour',
                value: const FactTextValue('red'),
                scope: 'universe',
              ),
            ],
          ),
        ],
      ),
      isValidationActive: (_) => false,
    );
    return ProposalId.parse(result.check.candidateHandle!);
  }

  WireFields writingReview(CanonicalValue value) => WireFields(value, {
    'acceptance_options',
    'summary',
    'candidate',
    'validation',
    'impact',
    'publishable',
    'review',
  });

  Future<OpenedContext> knowledgeContext({
    KnowledgeMode mode = KnowledgeMode.authorEstablished,
  }) async {
    final clock = FictionalUniverseStart(
      calendarName: 'Knowledge clock',
      initialTick: '0',
      tickLabel: 'ticks',
    ).build(frames.calendar);
    final context = f.ref(55);
    final prop = PropositionRecord(
      subject: f.ref(80),
      predicate: f.ref(1),
      context: context,
      value: const BooleanValue(true),
      quantification: Quantification.particular,
    );
    kernel.commit(
      input('knowledge-writing-fixture', [
        f.row(10, clock.$2),
        f.row(
          55,
          RepresentedContextRecord(
            universe: f.u,
            kind: const ObjectiveContext(),
            chronology: clock.$1,
            labels: {},
          ),
        ),
        f.row(80, named.entity(labels: {'en': 'Mara'})),
        frames.fixture().first,
        f.row(2, prop),
        f.row(7, knowledge.policy(mode: mode, context: context)),
        f.row(
          6,
          EpistemicAttitudeRecord(
            holder: f.ref(80),
            proposition: f.ref(2),
            attitude: EpistemicAttitudeKind.knows,
            certainty: 'authored',
            validity: CalendarIntervalValidity(
              frames.calendar,
              const ExactBound('10'),
              const ExactBound('30'),
            ),
            basis: const AuthorDecisionBasis('Original author decision'),
            acquisition: KnowledgeAcquisition(
              truthContext: context,
              time: ExactTime(frames.calendar, '10'),
              basis: const AuthorEstablishedKnowledge(),
            ),
          ),
        ),
      ]),
    );
    return service.openContext(
      contextRequest(represented: ContextIdSelector(f.id(55))),
    );
  }

  EstablishKnowledgeWritingAction establishment(
    ContextId id, {
    String? world,
    String reason = 'Explicit author knowledge',
  }) => EstablishKnowledgeWritingAction(
    contextId: id,
    declaration: AuthorKnowledgeDeclaration(
      holder: 'Mara',
      claim: WritingClaim(
        subject: 'Mara',
        property: 'open',
        value: const FactBooleanValue(false),
      ),
      atTick: '9007199254740993',
      lifetime: const FactUntilLifetime(endTick: '9007199254740995'),
      world: world,
    ),
    rationale: reason,
    label: 'Author passage',
    text: 'Mara knows the gate is closed.',
  );

  test('private knowledge establishment reopens writer context and retains attributed knowledge without objective facts', () async {
    final selected = await knowledgeContext();
    final head = kernel.journal.head(continuity);
    final action = establishment(selected.contextId);
    final reviewed = writingReview(
      await authorService().authorWritingAction(
        action,
        isValidationActive: (_) => false,
      ),
    );
    final ref = ProposalRef.fromWire(reviewed.require('candidate'));
    final stored = StoredProposal.fromWire(
      WorkflowStorage(package.database).get(proposalKey(ref))!,
    );
    expect(stored.owner, author.id);
    expect(stored.authorOrigin, isTrue);
    expect(
      stored.proposal.operations.whereType<AssertPropositionOperation>(),
      isEmpty,
    );
    final attitude = stored.proposal.operations
        .whereType<AddBeliefOperation>()
        .single
        .record;
    expect(attitude.basis, AuthorDecisionBasis(action.rationale));
    expect(attitude.acquisition!.basis, isA<AuthorEstablishedKnowledge>());
    expect(
      attitude.acquisition!.time,
      ExactTime(frames.calendar, '9007199254740993'),
    );
    expect(attitude.acquisition!.world, isNull);
    expect(
      reviewed.array('summary').map(wireString),
      contains(
        contains('attributed knowledge only, no objective fact asserted'),
      ),
    );
    expect(kernel.journal.head(continuity), head);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final retry = writingReview(
      await authorService().establishWritingKnowledge(
        action,
        isValidationActive: (_) => false,
      ),
    );
    expect(ProposalRef.fromWire(retry.require('candidate')), ref);
    expect(
      WorkflowStorage(package.database).keys('source-version:'),
      hasLength(1),
    );
    final retained = StoredProposal.fromWire(
      WorkflowStorage(package.database).get(proposalKey(ref))!,
    );
    expect(retained.toWire().toText(), stored.toWire().toText());
    expect(retry.boolean('publishable'), isTrue);
    final report = ValidationV3.fromWire(retry.require('validation'));
    final receipt = CommitReceipt.fromWire(
      await authorService().authorWritingAction(
        PublishWritingAction(
          candidate: ref,
          validationRun: report.execution!.runId,
          idempotencyKey: 'publish-authored-knowledge',
        ),
        isValidationActive: (_) => false,
      ),
    );
    final published = canon(continuity, receipt.revision);
    expect(published.where((r) => r.payload is AssertionRecord), isEmpty);
    expect(
      published.where((r) => r.payload is EpistemicAttitudeRecord),
      hasLength(2),
    );
  });

  test('private knowledge edit changes only duration and retains original acquisition and basis across retry', () async {
    final selected = await knowledgeContext();
    final original =
        canon(
              continuity,
              kernel.journal.head(continuity),
            ).singleWhere((r) => r.identity.recordId == f.id(6)).payload
            as EpistemicAttitudeRecord;
    final action = EditKnowledgeWritingAction(
      contextId: selected.contextId,
      correction: WritingAttitudeCorrection(
        attitudeHandle: f.ver(6).value,
        reason: 'Correct the authored duration',
        endTick: '20',
      ),
      label: 'Corrected notes',
      text: 'Mara knew until tick twenty.',
    );
    final reviewed = writingReview(
      await authorService().authorWritingAction(
        action,
        isValidationActive: (_) => false,
      ),
    );
    final ref = ProposalRef.fromWire(reviewed.require('candidate'));
    final stored = StoredProposal.fromWire(
      WorkflowStorage(package.database).get(proposalKey(ref))!,
    );
    final replacement = stored.proposal.operations
        .whereType<ReviseAttitudeOperation>()
        .single
        .replacement;
    expect(replacement.proposition, original.proposition);
    expect(replacement.holder, original.holder);
    expect(replacement.certainty, original.certainty);
    expect(replacement.basis, original.basis);
    expect(
      replacement.acquisition!.toWire().toText(),
      original.acquisition!.toWire().toText(),
    );
    expect(
      replacement.validity,
      CalendarIntervalValidity(
        frames.calendar,
        const ExactBound('10'),
        const ExactBound('20'),
      ),
    );
    final retry = writingReview(
      await authorService().editWritingKnowledge(
        action,
        isValidationActive: (_) => false,
      ),
    );
    expect(ProposalRef.fromWire(retry.require('candidate')), ref);
    expect(
      WorkflowStorage(package.database).keys('source-version:'),
      hasLength(1),
    );
    await expectLater(
      authorService().editWritingKnowledge(
        EditKnowledgeWritingAction(
          contextId: selected.contextId,
          correction: WritingAttitudeCorrection(
            attitudeHandle: f.ver(6).value,
            reason: 'Try changing claim',
            value: const FactBooleanValue(false),
          ),
          label: 'Changed claim',
          text: 'Changed claim',
        ),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      WorkflowStorage(package.database).keys('source-version:'),
      hasLength(1),
    );
  });

  test('private knowledge rejects expired contexts unresolved worlds and ambiguous policies before source staging', () async {
    final selected = await knowledgeContext();
    final expired = ContextId.generate();
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry(
        'context:${expired.value}',
        StoredContext(
          owner: writer.id,
          scope: 'expired fixture',
          expires: BigInt.zero,
          frame: selected.frame,
        ).toWire(),
      ),
    ]);
    await expectLater(
      authorService().authorWritingAction(
        establishment(expired),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<ContextExpiredError>()),
    );
    await expectLater(
      authorService().authorWritingAction(
        establishment(selected.contextId, world: 'Missing world'),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    kernel.commit(
      input('second-knowledge-policy', [
        f.row(
          8,
          knowledge.policy(
            mode: KnowledgeMode.authorEstablished,
            context: f.ref(55),
          ),
        ),
      ]),
    );
    final current = await service.openContext(
      contextRequest(represented: ContextIdSelector(f.id(55))),
    );
    await expectLater(
      authorService().authorWritingAction(
        establishment(current.contextId),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    expect(WorkflowStorage(package.database).keys('source-version:'), isEmpty);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test('private knowledge requires exact policy current context explicit rationale and author rights', () async {
    final selected = await knowledgeContext(mode: KnowledgeMode.justified);
    final action = establishment(selected.contextId);
    await expectLater(
      authorService().establishWritingKnowledge(
        action,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    await expectLater(
      service.establishWritingKnowledge(
        action,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      authorService().establishWritingKnowledge(
        establishment(selected.contextId, reason: '\u2003'),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    final edit = EditKnowledgeWritingAction(
      contextId: selected.contextId,
      correction: WritingAttitudeCorrection(
        attitudeHandle: f.ver(6).value,
        reason: 'Correction',
        endTick: '20',
      ),
      label: 'Notes',
      text: 'Text',
    );
    await expectLater(
      service.editWritingKnowledge(edit, isValidationActive: (_) => false),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    kernel.commit(input('advance-before-knowledge', [f.row(77, f.entity())]));
    await expectLater(
      authorService().editWritingKnowledge(
        edit,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
    await expectLater(
      authorService().establishWritingKnowledge(
        action,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
    expect(WorkflowStorage(package.database).keys('source-version:'), isEmpty);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  Future<WireFields> resourceWritingReview() async {
    final clock = FictionalUniverseStart(
      calendarName: 'Campaign clock',
      initialTick: '0',
      tickLabel: 'ticks',
    ).build(resources.cal);
    kernel.commit(
      input('resource-writing-fixture', [
        ...resources.fixture(),
        f.row(6, clock.$2),
        f.row(
          5,
          RepresentedContextRecord(
            universe: f.u,
            kind: const ObjectiveContext(),
            chronology: clock.$1,
            labels: {},
          ),
        ),
      ]),
    );
    final owner = authorService();
    final opened = await owner.openContext(
      contextRequest(represented: ContextIdSelector(f.id(5))),
    );
    final draft = await owner.proposeRequest(
      CreateProposalRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        operations: [
          AddNameOperation(
            record: f.ref(3),
            expectedVersion: f.ver(3),
            name: const ContextualName(
              text: 'Actor',
              validity: UnspecifiedValidity(),
            ),
          ),
        ],
        submission: Submission.draft,
        rationale: 'Resource timeline review',
        idempotencyKey: 'resource-writing-draft',
      ),
      isValidationActive: (_) => false,
    );
    return writingReview(
      await owner.prepareWritingReview(
        candidate: draft.proposalId,
        label: 'Session notes',
        text: 'The actor acquired another round at tick five.',
        isValidationActive: (_) => false,
      ),
    );
  }

  test('private resource acceptance preserves exact source versions and requires separate approval across retry and reopen', () async {
    final reviewed = await resourceWritingReview();
    expect(reviewed.boolean('publishable'), isFalse);
    final ref = ProposalRef.fromWire(reviewed.require('candidate'));
    final option = WireFields(reviewed.array('acceptance_options').single, {
      'fingerprint',
      'scope',
    });
    final action = AcceptWritingAction(
      candidate: ref,
      fingerprint: FindingFingerprint(option.string('fingerprint')),
      scope: option.string('scope'),
      rationale: 'Author accepts this exact unexplained arrival',
    );
    final workflow = WorkflowStorage(package.database);
    final original = StoredProposal.fromWire(workflow.get(proposalKey(ref))!);
    final sourceVersions = original.changes
        .where((c) => c.next != null)
        .map((c) => RecordVersion.fromWire(c.next!.toCanonical()))
        .where((r) => r.payload is SourceVersionRecord)
        .map((r) => r.toWire().toText())
        .toList();
    final head = kernel.journal.head(continuity);
    final accepted = writingReview(
      await authorService().authorWritingAction(
        action,
        isValidationActive: (_) => false,
      ),
    );
    final next = ProposalRef.fromWire(accepted.require('candidate'));
    expect(next.proposalId, ref.proposalId);
    expect(next.version, ref.version + BigInt.one);
    expect(accepted.boolean('publishable'), isTrue);
    expect(accepted.array('acceptance_options'), isEmpty);
    final retained = StoredProposal.fromWire(workflow.get(proposalKey(next))!);
    expect(
      retained.changes
          .where((c) => c.next != null)
          .map((c) => RecordVersion.fromWire(c.next!.toCanonical()))
          .where((r) => r.payload is SourceVersionRecord)
          .map((r) => r.toWire().toText())
          .toList(),
      sourceVersions,
    );
    expect(
      retained.proposal.operations
          .whereType<RecordIssueDecisionOperation>()
          .single
          .record
          .rationale,
      action.rationale,
    );
    expect(kernel.journal.head(continuity), head);
    expect(workflow.keys('approval:'), isEmpty);
    expect(workflow.keys('source-version:'), hasLength(1));
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final retry = writingReview(
      await authorService().acceptWriting(
        action,
        isValidationActive: (_) => false,
      ),
    );
    expect(ProposalRef.fromWire(retry.require('candidate')), next);
    expect(
      WorkflowStorage(package.database).keys('source-version:'),
      hasLength(1),
    );
    final report = ValidationV3.fromWire(retry.require('validation'));
    final receipt = await authorService().publishWriting(
      PublishWritingAction(
        candidate: next,
        validationRun: report.execution!.runId,
        idempotencyKey: 'publish-resource-acceptance',
      ),
      isValidationActive: (_) => false,
    );
    expect(kernel.journal.head(continuity), receipt.revision);
    await expectLater(
      authorService().acceptWriting(action, isValidationActive: (_) => false),
      throwsA(isA<ApprovalStaleError>()),
    );
  });

  test('private resource acceptance denies wrong scope fingerprint blank reason and writer authority before revision', () async {
    final reviewed = await resourceWritingReview();
    final ref = ProposalRef.fromWire(reviewed.require('candidate'));
    final option = WireFields(reviewed.array('acceptance_options').single, {
      'fingerprint',
      'scope',
    });
    AcceptWritingAction action({
      String? scope,
      String? fingerprint,
      String reason = 'Explicit acceptance',
    }) => AcceptWritingAction(
      candidate: ref,
      fingerprint: FindingFingerprint(
        fingerprint ?? option.string('fingerprint'),
      ),
      scope: scope ?? option.string('scope'),
      rationale: reason,
    );
    final workflow = WorkflowStorage(package.database);
    final proposalKeys = workflow.keys('proposal:');
    await expectLater(
      authorService().acceptWriting(
        action(scope: 'general'),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    await expectLater(
      authorService().acceptWriting(
        action(fingerprint: 'a' * 64),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    await expectLater(
      authorService().acceptWriting(
        action(reason: '\u2003\n'),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    await expectLater(
      service.acceptWriting(action(), isValidationActive: (_) => false),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(workflow.keys('proposal:'), proposalKeys);
    expect(workflow.keys('approval:'), isEmpty);
    expect(workflow.keys('source-version:'), hasLength(1));
    kernel.commit(
      input('advance-before-resource-acceptance', [f.row(77, f.entity())]),
    );
    await expectLater(
      authorService().acceptWriting(action(), isValidationActive: (_) => false),
      throwsA(isA<ApprovalStaleError>()),
    );
    expect(workflow.keys('proposal:'), proposalKeys);
  });

  Future<CanonicalValue> writingEngine(EngineRequest request) =>
      authorService().executeWritingEngineRequest(
        EngineRequest.decode(request.toWire().toBytes()),
        isValidationActive: (_) => false,
      );

  test('private writing engine requests retain raw reviews and publication envelopes across alias and reopen', () async {
    final candidate = await writingDraft();
    final head = kernel.journal.head(continuity);
    authority.renameUniverse(author, id: f.u, name: 'Campaign');
    final staged = WireFields(
      await writingEngine(
        const StageSourceEngineRequest(
          universe: Selector('World'),
          label: 'Independent source',
          text: 'é😀',
        ),
      ),
      {'canonical', 'operations'},
    );
    expect(staged.boolean('canonical'), isFalse);
    expect(staged.array('operations'), hasLength(2));
    final prepared = writingReview(
      await writingEngine(
        AuthorWritingEngineRequest(
          universe: const Selector('World'),
          action: PrepareWritingAction(
            candidate: candidate,
            label: 'Author scene',
            text: 'Iris is red.',
          ),
        ),
      ),
    );
    final ref = ProposalRef.fromWire(prepared.require('candidate'));
    final raw = WireFields(
      await writingEngine(
        ReviewEngineRequest(
          universe: const Selector('Campaign'),
          proposalReference: ref,
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
    expect(Proposal.fromWire(raw.require('proposal')).digest, ref.digest);
    expect(kernel.journal.head(continuity), head);
    final inspected = writingReview(
      await writingEngine(
        AuthorWritingEngineRequest(
          universe: const Selector('World'),
          action: InspectWritingAction(candidate: ref),
        ),
      ),
    );
    final report = ValidationV3.fromWire(inspected.require('validation'));
    final approved = WireFields(
      await writingEngine(
        ApproveEngineRequest(
          universe: const Selector('Campaign'),
          proposalReference: ref,
          validationRun: report.execution!.runId,
        ),
      ),
      {'approved', 'validation_run'},
    );
    expect(ProposalRef.fromWire(approved.require('approved')), ref);
    final request = AuthorWritingEngineRequest(
      universe: const Selector('World'),
      action: PublishWritingAction(
        candidate: ref,
        validationRun: report.execution!.runId,
        idempotencyKey: 'engine-writing-publication',
      ),
    );
    final response = await writingEngine(request);
    final envelope = Envelope<CommitReceipt>.fromWire(
      response,
      CommitReceipt.fromWire,
    );
    expect(envelope.contractVersion, protocolVersion);
    expect(envelope.requestId, BigInt.zero);
    expect(envelope.universeId, f.u);
    expect(envelope.universe, const Selector('Campaign'));
    expect(envelope.aliasMatched, isTrue);
    expect(envelope.authorizationScope, 'universe grant');
    expect(envelope.delivery.complete, isTrue);
    expect(
      envelope.frame,
      Proposal.fromWire(raw.require('proposal')).baseFrame,
    );
    expect(kernel.journal.head(continuity), envelope.result.revision);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    expect((await writingEngine(request)).toText(), response.toText());
    expect(WorkflowStorage(package.database).keys('approval:'), hasLength(1));
  });

  test('private writing engine resolves the bound universe and author rights before staging', () async {
    final workflow = WorkflowStorage(package.database);
    final keys = workflow.keys('');
    const request = StageSourceEngineRequest(
      universe: Selector('World'),
      label: 'Writer',
      text: 'Private source',
    );
    await expectLater(
      service.executeWritingEngineRequest(
        EngineRequest.decode(request.toWire().toBytes()),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      writingEngine(
        const StageSourceEngineRequest(
          universe: Selector('Missing'),
          label: 'Missing',
          text: 'Text',
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final otherPath = '${directory.path}/packages/other.sqlite';
    final other = OwnedSqliteDatabase.create(otherPath);
    try {
      final foreign = SqliteKernel(other.database, UniverseId.generate());
      other.database.execute('BEGIN IMMEDIATE');
      foreign.journal.initialize(
        'Other universe',
        ContinuityId.generate(),
        PrincipalId.generate(),
      );
      other.database.execute('COMMIT');
    } finally {
      other.close();
    }
    authority.registerUniverse(author, name: 'Other', path: otherPath);
    await expectLater(
      writingEngine(
        const StageSourceEngineRequest(
          universe: Selector('Other'),
          label: 'Wrong worker',
          text: 'Text',
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    authority.revoke(author, writer.id);
    await expectLater(
      service.executeWritingEngineRequest(
        request,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(workflow.keys(''), keys);
  });

  test('private writing actions prepare inspect and publish once across changed head and reopen', () async {
    final candidate = await writingDraft();
    final owner = authorService();
    final head = kernel.journal.head(continuity);
    final prepared = writingReview(
      await owner.authorWritingAction(
        PrepareWritingAction(
          candidate: candidate,
          label: 'Author passage',
          text: 'Iris is red.',
        ),
        isValidationActive: (_) => false,
      ),
    );
    final ref = ProposalRef.fromWire(prepared.require('candidate'));
    expect(prepared.boolean('publishable'), isTrue);
    expect(kernel.journal.head(continuity), head);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    final inspected = writingReview(
      await owner.authorWritingAction(
        InspectWritingAction(candidate: ref),
        isValidationActive: (_) => false,
      ),
    );
    expect(ProposalRef.fromWire(inspected.require('candidate')), ref);
    final report = ValidationV3.fromWire(inspected.require('validation'));
    final action = PublishWritingAction(
      candidate: ref,
      validationRun: report.execution!.runId,
      idempotencyKey: 'writing-publication',
    );
    final receipt = CommitReceipt.fromWire(
      await owner.authorWritingAction(action, isValidationActive: (_) => false),
    );
    expect(kernel.journal.head(continuity), receipt.revision);
    expect(WorkflowStorage(package.database).keys('approval:'), hasLength(1));
    kernel.commit(input('after-writing-publication', [f.row(77, f.entity())]));
    final advanced = kernel.journal.head(continuity);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final retry = await authorService().publishWriting(
      action,
      isValidationActive: (_) => false,
    );
    expect(retry.toWire().toText(), receipt.toWire().toText());
    expect(kernel.journal.head(continuity), advanced);
    expect(WorkflowStorage(package.database).keys('approval:'), hasLength(1));
    await expectLater(
      authorService().publishWriting(
        PublishWritingAction(
          candidate: ref,
          validationRun: ValidationRunId.generate(),
          idempotencyKey: action.idempotencyKey,
        ),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
  });

  test('private writing rejection retains its original withdrawn receipt across changed head and reopen', () async {
    final candidate = await writingDraft();
    final action = RejectWritingAction(candidate: candidate);
    final head = kernel.journal.head(continuity);
    final withdrawn = Proposal.fromWire(
      await authorService().authorWritingAction(
        action,
        isValidationActive: (_) => false,
      ),
    );
    expect(withdrawn.withdrawn, isTrue);
    expect(withdrawn.version, BigInt.two);
    expect(kernel.journal.head(continuity), head);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    final frozen = StoredProposal.fromWire(
      WorkflowStorage(package.database).get(proposalKey(reference(withdrawn)))!,
    );
    expect(kernel.identityExists(frozen.changes.first.recordId), isFalse);
    kernel.commit(input('after-writing-rejection', [f.row(77, f.entity())]));
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final retry = await authorService().rejectWriting(
      action,
      isValidationActive: (_) => false,
    );
    expect(retry.toWire().toText(), withdrawn.toWire().toText());
    await expectLater(
      authorService().prepareWritingReview(
        candidate: candidate,
        label: 'Rejected',
        text: 'Iris is red.',
        isValidationActive: (_) => false,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
  });

  test(
    'private writing inspect requires a submitted author-prepared exact source',
    () async {
      await expectLater(
        authorService().inspectWriting(
          InspectWritingAction(candidate: proposal.reference),
        ),
        throwsA(isA<ApprovalStaleError>()),
      );
      final submitted = await propose(proposals.transition(proposal));
      await expectLater(
        authorService().inspectWriting(
          InspectWritingAction(candidate: reference(submitted)),
        ),
        throwsA(isA<PolicyDeniedError>()),
      );
      final opened = await authorService().openContext(contextRequest());
      final authored = await authorService().proposeRequest(
        CreateProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          operations: [
            CreateEntityOperation(
              clientRef: f.id(88).value,
              record: f.entity(),
            ),
          ],
          submission: Submission.submitted,
          rationale: 'An explicit author edit',
          idempotencyKey: 'author-without-source',
        ),
        isValidationActive: (_) => false,
      );
      await expectLater(
        authorService().inspectWriting(
          InspectWritingAction(candidate: reference(authored)),
        ),
        throwsA(isA<PolicyDeniedError>()),
      );
      expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    },
  );

  test('writer profiles cannot perform private writing actions or retain author decisions', () async {
    final workflow = WorkflowStorage(package.database);
    final keys = workflow.keys('');
    final denied = throwsA(isA<NotFoundOrNotAccessibleError>());
    await expectLater(
      service.prepareWritingReview(
        candidate: proposal.proposal.proposalId,
        label: 'Writer',
        text: 'Text',
        isValidationActive: (_) => false,
      ),
      denied,
    );
    await expectLater(
      service.inspectWriting(
        InspectWritingAction(candidate: proposal.reference),
      ),
      denied,
    );
    await expectLater(
      service.rejectWriting(
        RejectWritingAction(candidate: proposal.proposal.proposalId),
        isValidationActive: (_) => false,
      ),
      denied,
    );
    await expectLater(
      service.publishWriting(
        PublishWritingAction(
          candidate: proposal.reference,
          validationRun: checked.validation.runId,
          idempotencyKey: 'writer-publication',
        ),
        isValidationActive: (_) => false,
      ),
      denied,
    );
    expect(workflow.keys(''), keys);
  });

  test('author exact-source preparation retains immutable source versions across retry and owned reopen', () async {
    final opened = await service.openContext(contextRequest());
    final checked = await service.checkChangesRequest(
      CheckChangesRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        changes: [
          ObjectChange(
            name: 'Iris',
            introduce: true,
            facts: [
              FactChange(
                property: 'colour',
                value: const FactTextValue('red'),
                scope: 'universe',
              ),
            ],
          ),
        ],
      ),
      isValidationActive: (_) => false,
    );
    final candidate = ProposalId.parse(checked.check.candidateHandle!);
    SqliteValidationWorkflow owner() => SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: author,
    );
    final head = kernel.journal.head(continuity);
    final prepared = await owner().prepareWritingSource(
      candidate: candidate,
      label: 'Author passage',
      text: 'Iris: é😀\r\nred.',
      isValidationActive: (_) => false,
    );
    expect(prepared.submission, Submission.submitted);
    expect(prepared.version, BigInt.two);
    final key = proposalKey(reference(prepared));
    final workflow = WorkflowStorage(package.database);
    final stored = StoredProposal.fromWire(workflow.get(key)!);
    final bytes = stored.toWire().toText();
    expect(stored.owner, author.id);
    expect(stored.authorOrigin, isTrue);
    final rows = stored.changes
        .where((c) => c.next != null)
        .map((c) => RecordVersion.fromWire(c.next!.toCanonical()))
        .toList();
    final source = rows.singleWhere((r) => r.payload is SourceVersionRecord);
    final anchor =
        rows.singleWhere((r) => r.payload is AnchorRecord).payload
            as AnchorRecord;
    expect(anchor.sourceVersion.version, source.recordVersionId);
    expect(anchor.excerpt, 'Iris: é😀\r\nred.');
    expect(workflow.keys('source-version:'), hasLength(1));
    expect(workflow.keys('approval:'), isEmpty);
    expect(kernel.journal.head(continuity), head);
    final reviewed = WireFields(
      await owner().writingAuthorReview(reference(prepared)),
      {
        'acceptance_options',
        'summary',
        'candidate',
        'validation',
        'impact',
        'publishable',
        'review',
      },
    );
    expect(reviewed.boolean('publishable'), isTrue);
    expect(
      ProposalRef.fromWire(reviewed.require('candidate')),
      reference(prepared),
    );
    final summary = reviewed.array('summary').map(wireString).toList();
    expect(summary, contains(startsWith('Exact author source:')));
    expect(summary, contains(contains('Iris — colour = "red"')));
    final reviewValidation = ValidationV3.fromWire(
      reviewed.require('validation'),
    );
    expect(
      workflow.get('validation:${reviewValidation.execution!.runId.value}'),
      isNotNull,
    );
    expect(workflow.keys('approval:'), isEmpty);
    expect(kernel.journal.head(continuity), head);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    final retry = await owner().prepareWritingSource(
      candidate: candidate,
      label: 'Author passage',
      text: 'Iris: é😀\r\nred.',
      isValidationActive: (_) => false,
    );
    expect(retry.toWire().toText(), prepared.toWire().toText());
    expect(WorkflowStorage(package.database).get(key)!.toText(), bytes);
    expect(
      WorkflowStorage(package.database).keys('source-version:'),
      hasLength(1),
    );
    final admission = await owner().openContext(contextRequest());
    final validation = await owner().validateProposalRequest(
      ProposalValidationRequest(
        universe: const Selector('World'),
        contextId: admission.contextId,
        proposalReference: reference(prepared),
        checkScope: CheckScope.universe,
      ),
    );
    expect(validation.execution!.coverage, Coverage.complete);
    await owner().approve(reference(prepared), validation.execution!.runId);
    final receipt = await owner().commit(
      CommitRequest(
        universe: const Selector('World'),
        proposalReference: reference(prepared),
        expectedBaseRevision: head,
        validationRun: validation.execution!.runId,
        idempotencyKey: 'author-source-publication',
      ),
      isValidationActive: (_) => false,
    );
    expect(kernel.journal.head(continuity), receipt.revision);
    expect(kernel.identityExists(source.identity.recordId), isTrue);
    await expectLater(
      owner().writingAuthorReview(reference(prepared)),
      throwsA(isA<ApprovalStaleError>()),
    );
    await expectLater(
      owner().prepareWritingSource(
        candidate: candidate,
        label: 'Author passage',
        text: 'Iris: é😀\r\nred.',
        isValidationActive: (_) => false,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
  });

  test(
    'author source staging denies writer profiles before retaining bytes',
    () async {
      final workflow = WorkflowStorage(package.database);
      await expectLater(
        service.stageSource(label: 'Writer', text: 'A passage'),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(workflow.keys('source:'), isEmpty);
      final owner = SqliteValidationWorkflow(
        package: package,
        authority: authority,
        principal: author,
      );
      final staged = await owner.stageSource(label: 'Author', text: 'é😀\r\n');
      final fields = WireFields(staged, {'canonical', 'operations'});
      expect(fields.require('canonical'), const CanonicalBool(false));
      final operations = fields
          .array('operations')
          .map(DomainOperation.fromWire)
          .toList();
      expect(operations, hasLength(2));
      expect(workflow.keys('source-version:'), hasLength(1));
      expect(workflow.keys('approval:'), isEmpty);
      await expectLater(
        owner.stageSource(label: '', text: 'Passage'),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(workflow.keys('source-version:'), hasLength(1));
    },
  );

  test('author source preparation enforces current drafts and explicit contract review before staging', () async {
    final opened = await service.openContext(contextRequest());
    final checked = await service.checkChangesRequest(
      CheckChangesRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        units: [
          WritingUnit(
            name: 'metre',
            dimension: 'length',
            symbol: 'm',
            introduce: true,
          ),
        ],
      ),
      isValidationActive: (_) => false,
    );
    final candidate = ProposalId.parse(checked.check.candidateHandle!);
    final owner = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: author,
    );
    await expectLater(
      owner.prepareWritingSource(
        candidate: candidate,
        label: 'Units',
        text: 'A metre is the declared unit.',
        isValidationActive: (_) => false,
      ),
      throwsA(isA<PolicyDeniedError>()),
    );
    expect(WorkflowStorage(package.database).keys('source:'), isEmpty);
    await expectLater(
      service.prepareWritingSource(
        candidate: candidate,
        label: 'Units',
        text: 'A passage',
        contracts: true,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final prepared = await owner.prepareWritingSource(
      candidate: candidate,
      label: 'Units',
      text: 'A metre is the declared unit.',
      contracts: true,
      isValidationActive: (_) => false,
    );
    expect(prepared.submission, Submission.submitted);
    expect(prepared.rationale, contains('explicitly declared'));
    final reviewed = writingReview(
      await owner.authorWritingAction(
        PrepareContractsWritingAction(
          candidate: candidate,
          label: 'Units',
          text: 'A metre is the declared unit.',
        ),
        isValidationActive: (_) => false,
      ),
    );
    expect(
      ProposalRef.fromWire(reviewed.require('candidate')),
      reference(prepared),
    );
    expect(
      reviewed.array('summary').map(wireString),
      contains(contains('Author unit declaration: metre;')),
    );
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    await expectLater(
      owner.prepareWritingSource(
        candidate: candidate,
        label: 'Different',
        text: 'A different passage',
        contracts: true,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
    expect(
      WorkflowStorage(package.database).keys('source-version:'),
      hasLength(1),
    );
  });

  test('writer check retains an exact provisional candidate across retry and reopen without publication', () async {
    final opened = await service.openContext(contextRequest());
    final request = CheckChangesRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
      changes: [
        ObjectChange(
          name: 'Iris',
          introduce: true,
          facts: [
            FactChange(
              property: 'colour',
              value: const FactTextValue('red'),
              scope: 'universe',
            ),
          ],
        ),
      ],
    );
    final head = kernel.journal.head(continuity);
    final first = await service.checkChangesRequest(
      request,
      isValidationActive: (_) => false,
    );
    expect(first.check.status, 'checked_candidate');
    expect(first.check.candidateHandle, isNotNull);
    expect(first.frame, opened.frame);
    expect(first.check.unknowns, [
      'The story-time validity of the new facts remains unspecified.',
    ]);
    final workflow = WorkflowStorage(package.database);
    final proposalKeys = workflow.keys('proposal:');
    final retainedKey = proposalKeys.singleWhere(
      (key) => key.contains(first.check.candidateHandle!),
    );
    final retained = StoredProposal.fromWire(workflow.get(retainedKey)!);
    final retainedBytes = retained.toWire().toText();
    expect(retained.changes, hasLength(4));
    expect(retained.proposal.submission, Submission.draft);
    expect(retained.proposal.canonical, isFalse);
    expect(retained.proposal.baseFrame.time, isA<TimelessFrameTime>());
    expect(workflow.keys('approval:'), isEmpty);
    expect(kernel.journal.head(continuity), head);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final retry = await service.checkChangesRequest(
      request,
      isValidationActive: (_) => false,
    );
    expect(retry.check.status, 'checked_candidate');
    expect(retry.check.candidateHandle, first.check.candidateHandle);
    expect(retry.check.additions, [
      'Reused the exact original uncommitted candidate.',
    ]);
    final reopened = WorkflowStorage(package.database);
    expect(reopened.keys('proposal:'), proposalKeys);
    expect(reopened.get(retainedKey)!.toText(), retainedBytes);
    expect(reopened.keys('request:${writer.id.value}:propose:'), hasLength(1));
    expect(reopened.keys('approval:'), isEmpty);
    expect(kernel.journal.head(continuity), head);
  });

  test(
    'writer clarification and empty changes create no candidate or reservation',
    () async {
      final opened = await service.openContext(contextRequest());
      final workflow = WorkflowStorage(package.database);
      final before = workflow.keys('proposal:');
      final result = await service.checkChangesRequest(
        CheckChangesRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          changes: [ObjectChange(name: 'Iris', introduce: true)],
          questions: ['Clarify this identity'],
        ),
        isValidationActive: (_) => false,
      );
      expect(result.check.status, 'needs_clarification');
      expect(result.check.candidateHandle, isNull);
      expect(result.check.additions, ['New object: Iris']);
      final empty = await service.checkChangesRequest(
        CheckChangesRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
        ),
        isValidationActive: (_) => false,
      );
      expect(empty.check.status, 'no_changes');
      expect(workflow.keys('proposal:'), before);
      expect(workflow.keys('reservation:'), isEmpty);
      expect(workflow.keys('request:${writer.id.value}:propose:'), isEmpty);
      expect(workflow.keys('validation:'), isEmpty);
      final invalidDate = await service.checkChangesRequest(
        CheckChangesRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          changes: [
            ObjectChange(
              name: 'Iris',
              introduce: true,
              facts: [
                FactChange(
                  property: 'colour',
                  value: const FactTextValue('red'),
                  atDate: '2000-01-01',
                ),
              ],
            ),
          ],
        ),
        isValidationActive: (_) => false,
      );
      expect(invalidDate.check.status, 'needs_clarification');
      expect(invalidDate.check.additions, isEmpty);
      expect(workflow.keys('proposal:'), before);
    },
  );

  test('writer check refuses a research perspective before compiling and enforces current proposal grants', () async {
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: null,
          propose: false,
          edit: true,
          protected: true,
        ),
      ),
    );
    final opened = await service.openContext(contextRequest());
    await expectLater(
      service.checkChangesRequest(
        CheckChangesRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          changes: [ObjectChange(name: 'Iris', introduce: true)],
        ),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<PolicyDeniedError>()),
    );
    final frame = Frame(
      universe: f.u,
      continuity: continuity,
      revision: opened.frame.revision,
      context: f.ref(99),
      time: const TimelessFrameTime(),
      perspective: CharacterPerspective(f.id(20)),
    );
    final id = ContextId.generate();
    final scope = await authority.withUniverseAuthority(
      writer,
      f.u,
      (current) => current.scopeHash,
    );
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry(
        'context:${id.value}',
        StoredContext(
          owner: writer.id,
          scope: scope,
          expires: BigInt.from(
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          ),
          frame: frame,
        ).toWire(),
      ),
    ]);
    final research = await service.checkChangesRequest(
      CheckChangesRequest(
        universe: const Selector('World'),
        contextId: id,
        changes: [ObjectChange(name: '', introduce: true)],
      ),
      isValidationActive: (_) => false,
    );
    expect(research.check.status, 'needs_clarification');
    expect(research.check.clarifications.single, contains('research only'));
    expect(research.check.candidateHandle, isNull);
    expect(
      WorkflowStorage(package.database)
          .keys('request:${writer.id.value}:propose:'),
      isEmpty,
    );
  });

  test('writer check preserves a conflicting candidate for review without approval', () async {
    kernel.commit(
      input('conflicting-rule', [
        f.row(
          50,
          frames.rule(
            expr: const LiteralExpr(false),
            validity: const UnspecifiedValidity(),
          ),
        ),
      ]),
    );
    final opened = await service.openContext(contextRequest());
    final head = kernel.journal.head(continuity);
    final result = await service.checkChangesRequest(
      CheckChangesRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        changes: [ObjectChange(name: 'Iris', introduce: true)],
      ),
      isValidationActive: (_) => false,
    );
    expect(result.check.status, 'conflict');
    expect(result.check.candidateHandle, isNotNull);
    final retained = StoredProposal.fromWire(
      WorkflowStorage(package.database).get(
        WorkflowStorage(package.database)
            .latestKey('proposal:${result.check.candidateHandle}:')!,
      )!,
    );
    final review = WireFields(
      await SqliteValidationWorkflow(
        package: package,
        authority: authority,
        principal: author,
      ).writingAuthorReview(retained.reference),
      {
        'acceptance_options',
        'summary',
        'candidate',
        'validation',
        'impact',
        'publishable',
        'review',
      },
    );
    expect(review.boolean('publishable'), isFalse);
    expect(
      ValidationV3.fromWire(result.check.validation!)
          .execution!
          .findings
          .single
          .outcome,
      EvidenceOutcome.refuted,
    );
    expect(kernel.journal.head(continuity), head);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test('writer scene facts preserve exact calendar ticks while proposal review uses all validities', () async {
    final clock = FictionalUniverseStart(
      calendarName: 'Campaign time',
      initialTick: '10',
      tickLabel: 'ticks',
    ).build(f.cal);
    kernel.commit(
      input('writer-clock', [
        f.row(1, clock.$2),
        f.row(
          10,
          RepresentedContextRecord(
            universe: f.u,
            kind: const ObjectiveContext(),
            chronology: clock.$1,
            labels: {},
          ),
        ),
      ]),
    );
    final opened = await service.openContext(
      contextRequest(
        represented: ContextIdSelector(f.id(10)),
        time: AtFrameTime(ExactTime(f.cal, '9007199254740993')),
      ),
    );
    final result = await service.checkChangesRequest(
      CheckChangesRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        changes: [
          ObjectChange(
            name: 'Iris',
            introduce: true,
            facts: [
              FactChange(
                property: 'count',
                value: FactNumberValue(
                  const CanonicalNumber('9007199254740993'),
                ),
                scope: 'universe',
                atTick: '9007199254740994',
                lifetime: const FactUntilLifetime(endTick: '9007199254740996'),
              ),
            ],
          ),
        ],
      ),
      isValidationActive: (_) => false,
    );
    expect(result.check.status, 'checked_candidate');
    expect(result.frame.time, opened.frame.time);
    final workflow = WorkflowStorage(package.database);
    final key = workflow
        .keys('proposal:')
        .singleWhere((k) => k.contains(result.check.candidateHandle!));
    final stored = StoredProposal.fromWire(workflow.get(key)!);
    expect(stored.proposal.baseFrame.time, isA<TimelessFrameTime>());
    final assertion = stored.changes
        .where((c) => c.next != null)
        .map((c) => RecordPayload.fromWire(c.next!.payload))
        .whereType<AssertionRecord>()
        .single;
    expect(
      assertion.validity,
      CalendarIntervalValidity(
        f.cal,
        const ExactBound('9007199254740994'),
        const ExactBound('9007199254740996'),
      ),
    );
    expect(
      stored.changes
          .where((c) => c.next != null)
          .map((c) => RecordPayload.fromWire(c.next!.payload))
          .whereType<PropositionRecord>()
          .single
          .value,
      const IntegerValue('9007199254740993'),
    );
    expect(result.check.unknowns, isEmpty);
  });

  test(
    'writer exact retry rechecks context authority after grant revocation',
    () async {
      final opened = await service.openContext(contextRequest());
      final request = CheckChangesRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        changes: [ObjectChange(name: 'Iris', introduce: true)],
      );
      final checked = await service.checkChangesRequest(
        request,
        isValidationActive: (_) => false,
      );
      expect(checked.check.candidateHandle, isNotNull);
      final workflow = WorkflowStorage(package.database);
      final before = workflow.keys('proposal:');
      await authority.coordinate(
        author,
        () => authority.grant(
          author,
          GrantSpec(
            profileId: writer.id,
            universeId: f.u,
            worlds: null,
            propose: false,
            edit: false,
            protected: false,
          ),
        ),
      );
      await expectLater(
        service.checkChangesRequest(request, isValidationActive: (_) => false),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(workflow.keys('proposal:'), before);
      expect(workflow.keys('approval:'), isEmpty);
    },
  );

  test('native descriptions discover current continuity and pin visible world definitions', () async {
    RuleRecord rule(int n, Applicability applicability) => RuleRecord(
      namespace: 'discovery',
      key: 'rule$n',
      labels: {},
      kind: RuleKind.physicalConstraint,
      commitPolicy: CommitPolicy.blockUnlessException,
      applicability: applicability,
      targetPredicates: [],
      expression: const LiteralExpr(true),
      capabilities: ['basic.v1'],
      executable: true,
      validity: const UnspecifiedValidity(),
    );
    kernel.commit(
      input('discovery-worlds', [
        f.row(50, WorldRecord(selector: 'Campaign', aliases: ['Play'])),
        f.row(51, WorldRecord(selector: 'Private')),
        f.row(80, rule(80, const UniverseApplicability())),
        f.row(81, rule(81, WorldsApplicability([permissions.world(50)]))),
        f.row(82, rule(82, WorldsApplicability([permissions.world(51)]))),
      ]),
    );
    final summary = await service.describeRequest(
      DescribeSummaryRequest(
        universe: const Selector('World'),
        universeId: f.u,
      ),
    );
    expect(summary.frame, isNull);
    expect(summary.description.worlds, isEmpty);
    expect(summary.description.continuities.single.id, continuity);
    expect(
      summary.description.continuities.single.revisionId,
      kernel.journal.head(continuity),
    );
    expect(
      summary.description.continuities.single.representedContexts.single.id,
      f.id(99),
    );
    final opened = await service.openContext(contextRequest());
    final definitions = DescribeDefinitionsRequest(
      universe: const Selector('World'),
      universeId: f.u,
      contextId: opened.contextId,
      world: const Selector('Play'),
      worldId: permissions.world(50),
    );
    final first = await service.describeRequest(definitions);
    expect(first.frame, opened.frame);
    expect(first.focus, permissions.world(50));
    expect(first.description.definitionIds, containsAll([f.id(80), f.id(81)]));
    expect(first.description.definitionIds, isNot(contains(f.id(82))));
    expect(first.description.worlds.map((w) => w.name.value), [
      'Campaign',
      'Private',
    ]);
    kernel.commit(
      input('discovery-later', [f.row(52, WorldRecord(selector: 'Later'))]),
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.describeRequest(definitions);
    expect(
      reopened.description.toWire().toText(),
      first.description.toWire().toText(),
    );
    final fresh = await service.describeRequest(
      DescribeSummaryRequest(universe: const Selector('World')),
    );
    expect(
      fresh.description.continuities.single.revisionId,
      kernel.journal.head(continuity),
    );
    await expectLater(
      service.describeRequest(
        DescribeCapabilitiesRequest(
          universe: const Selector('World'),
          universeId: UniverseId.generate(),
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('native discovery hides a private continuity and retains readable context kinds after reopen', () async {
    kernel.commit(
      input('private-discovery', [
        f.row(50, WorldRecord(selector: 'Campaign')),
        f.row(51, WorldRecord(selector: 'Private')),
        f.row(61, permissions.entity(worlds: [51])),
        f.row(
          31,
          RepresentedContextRecord(
            universe: f.u,
            kind: CharacterContext(f.ref(61)),
            labels: {'en': 'Private narrator'},
          ),
        ),
      ]),
    );
    final fork = ContinuityId.generate();
    final genesis = RevisionId.parse(
      package.database.select(
            'SELECT id FROM commits WHERE universe_id=? AND continuity_id=? AND sequence=0',
            [f.u.value, continuity.value],
          ).single['id']
          as String,
    );
    package.database.execute('BEGIN IMMEDIATE');
    kernel.journal.branch(fork, continuity, genesis, PrincipalId.generate());
    package.database.execute('COMMIT');
    final rows =
        [
              f.row(51, WorldRecord(selector: 'Private')),
              f.row(61, permissions.entity(worlds: [51])),
              f.row(
                31,
                RepresentedContextRecord(
                  universe: f.u,
                  kind: CharacterContext(f.ref(61)),
                  labels: {'en': 'Private narrator'},
                ),
              ),
            ]
            .map(
              (row) => RecordVersion.build(
                recordVersionId: RecordVersionId.generate(),
                identity: row.identity,
                payload: row.payload,
              ),
            )
            .toList();
    kernel.commit(
      CommitInput(
        universe: f.u,
        continuity: fork,
        expectedHead: kernel.journal.head(fork),
        principal: PrincipalId.generate(),
        decision: 'Disposable private continuity',
        reason: 'Discovery fixture',
        idempotencyKey: 'private-fork',
        changes: rows.map(
          (r) => Assignment(
            recordId: r.identity.recordId,
            next: StoredVersion(
              versionId: r.recordVersionId,
              identity: r.identity,
              payload: r.payload.toWire(),
              digest: r.payloadDigest,
            ),
          ),
        ),
      ),
    );
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry(
        'continuity-name:${fork.value}',
        CanonicalString('Private continuity'),
      ),
    ]);
    final request = DescribeSummaryRequest(
      universe: const Selector('World'),
      universeId: f.u,
    );
    final complete = await service.describeRequest(request);
    expect(complete.description.continuities.length, 2);
    expect(
      complete.description.continuities.firstWhere((c) => c.id == fork).name,
      'Private continuity',
    );
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    final scoped = await service.describeRequest(request);
    expect(scoped.description.continuities.single.id, continuity);
    expect(
      scoped.description.continuities.single.representedContexts.map(
        (c) => c.id,
      ),
      [f.id(99)],
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.describeRequest(request);
    expect(
      reopened.description.toWire().toText(),
      scoped.description.toWire().toText(),
    );
    final opened = await service.openContext(contextRequest());
    final worlds = await service.describeRequest(
      DescribeWorldsRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
      ),
    );
    expect(worlds.description.worlds.map((w) => w.name.value), ['Campaign']);
  });

  test('native context opening pins current canon and feeds proposal dispatch after reopen', () async {
    final opened = await service.openContext(contextRequest());
    expect(opened.frame.revision, kernel.journal.head(continuity));
    final stored = StoredContext.fromWire(
      WorkflowStorage(package.database)
          .get('context:${opened.contextId.value}')!,
    );
    expect(stored.owner, writer.id);
    expect(stored.frame.toWire().toText(), opened.frame.toWire().toText());
    final template = creation();
    final request = CreateProposalRequest(
      universe: template.universe,
      universeId: f.u,
      contextId: opened.contextId,
      operations: template.operations,
      submission: template.submission,
      rationale: template.rationale,
      idempotencyKey: template.idempotencyKey,
    );
    final created = await service.proposeRequest(
      request,
      isValidationActive: (_) => false,
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    expect(
      (await service.proposeRequest(
        request,
        isValidationActive: (_) => false,
      )).toWire().toText(),
      created.toWire().toText(),
    );
    expect(kernel.identityExists(f.id(20)), isFalse);
  });

  test(
    'unavailable perspective context and calendar retain no native context',
    () async {
      await expectLater(
        service.openContext(
          contextRequest(perspective: CharacterPerspective(f.id(20))),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        service.openContext(
          contextRequest(time: AtFrameTime(ExactTime(f.cal, '10'))),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        service.openContext(
          contextRequest(represented: ContextIdSelector(f.id(98))),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(WorkflowStorage(package.database).keys('context:'), isEmpty);
    },
  );

  Future<void> retainedContext({ProfileId? owner, BigInt? expires}) =>
      authority.withUniverseAuthority(writer, f.u, (current) {
        final stored = StoredContext(
          owner: owner ?? writer.id,
          scope: current.scopeHash,
          expires:
              expires ??
              BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600),
          frame: proposal.proposal.baseFrame,
        );
        WorkflowStorage(package.database).compareAppend({}, [
          MapEntry('context:${proposals.contextId.value}', stored.toWire()),
        ]);
      });

  ProposalValidationRequest synchronousCheck({UniverseId? guard}) =>
      ProposalValidationRequest(
        universe: const Selector('World'),
        universeId: guard ?? f.u,
        contextId: proposals.contextId,
        proposalReference: proposal.reference,
        checkScope: CheckScope.candidate,
      );

  InlineValidationRequest inlineCheck({
    List<DomainOperation>? operations,
    Selector? world,
    WorldId? guard,
  }) => InlineValidationRequest(
    universe: const Selector('World'),
    universeId: f.u,
    contextId: proposals.contextId,
    world: world,
    worldId: guard,
    operations: operations ?? creation().operations,
    checkScope: CheckScope.universe,
  );

  GetRequest readRecords(
    ContextId context,
    List<RecordId> ids,
    List<FieldGroup> groups,
  ) => GetRequest(
    universe: const Selector('World'),
    universeId: f.u,
    contextId: context,
    recordIds: ids,
    fieldGroups: groups,
  );

  SearchRequest searchRecords(
    ContextId context, {
    String query = '',
    int limit = 100,
    String? cursor,
    List<RecordKind> kinds = const [],
  }) => SearchRequest(
    universe: const Selector('World'),
    contextId: context,
    query: query,
    typedFilters: Filters(recordKinds: kinds),
    limit: limit,
    cursor: cursor,
  );

  test('native plain contracts retain pinned declarations and filter current scope before handles', () async {
    final rows = actions.fixture();
    final original = rows.firstWhere((r) => r.identity.recordId == f.id(5));
    rows[rows.indexOf(original)] = f.row(
      5,
      f.patch(original.payload, {
        'labels': CanonicalObject([MapEntry('en', CanonicalString('Charge'))]),
      }),
    );
    rows.addAll([
      structure.context(10),
      f.row(
        9,
        CalendarRecord(
          namespace: 'test',
          key: 'clock',
          labels: {},
          unitStructure: {},
        ),
      ),
      f.row(50, WorldRecord(selector: 'Campaign')),
      f.row(51, WorldRecord(selector: 'Private')),
      f.row(
        81,
        ActionDefinitionRecord(
          namespace: 'private',
          key: 'Hidden',
          labels: {},
          requirements: [],
          scope: Scope(
            context: f.ref(10),
            applicability: WorldsApplicability([permissions.world(51)]),
          ),
          validity: const UnspecifiedValidity(),
        ),
      ),
    ]);
    kernel.commit(input('contract-read-base', rows));
    OpenContextRequest context() =>
        contextRequest(represented: ContextIdSelector(f.id(10)));
    final opened = await service.openContext(context());
    ReadContractsRequest request(
      ContextId id, {
      List<String> names = const [],
    }) => ReadContractsRequest(
      universe: const Selector('World'),
      contextId: id,
      actionNames: names,
    );
    final head = kernel.journal.head(continuity);
    final first = await service.readContractsRequest(request(opened.contextId));
    expect(writing.list(first.contracts, 'actions').length, 2);
    final alias = await service.readContractsRequest(
      request(opened.contextId, names: ['Charge']),
    );
    expect(
      wireString(
        writing.field(writing.list(alias.contracts, 'actions').single, 'name'),
      ),
      'charged_action',
    );
    expect(kernel.journal.head(continuity), head);
    kernel.commit(
      input('later-contract', [
        f.row(
          82,
          ActionDefinitionRecord(
            namespace: 'test',
            key: 'Future',
            labels: {},
            requirements: [],
            scope: actions.scope,
            validity: const UnspecifiedValidity(),
          ),
        ),
      ]),
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.readContractsRequest(
      request(opened.contextId),
    );
    expect(reopened.contracts.toText(), first.contracts.toText());
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    await expectLater(
      service.readContractsRequest(request(opened.contextId)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final scoped = await service.openContext(context());
    final restricted = await service.readContractsRequest(
      request(scoped.contextId),
    );
    expect(writing.list(restricted.contracts, 'actions').length, 2);
    expect(
      writing
          .list(restricted.contracts, 'actions')
          .map((value) => wireString(writing.field(value, 'name'))),
      isNot(contains('Hidden')),
    );
    expect(
      wireString(writing.field(restricted.contracts, 'coverage')),
      'restricted',
    );
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
  });

  test('native plain facts preserve pinned evidence and hide name counts after scope changes', () async {
    final rows = objects.withInstance();
    objects.edit(rows, 4, {
      'labels': CanonicalObject([MapEntry('en', CanonicalString('Cedar'))]),
    });
    rows.addAll([
      f.row(
        10,
        CalendarRecord(
          namespace: 'test',
          key: 'clock',
          labels: {},
          unitStructure: {},
        ),
      ),
      f.row(50, WorldRecord(selector: 'Campaign')),
    ]);
    kernel.commit(input('plain-read-base', rows));
    OpenContextRequest context() =>
        contextRequest(time: AtFrameTime(ExactTime(objects.cal, '15')));
    final opened = await service.openContext(context());
    ReadFactsRequest request(
      ContextId id, {
      List<String> names = const ['Cedar'],
    }) => ReadFactsRequest(
      universe: const Selector('World'),
      contextId: id,
      objectNames: names,
    );
    final first = await service.readFactsRequest(request(opened.contextId));
    final plain = writing.list(first.facts, 'objects').single;
    expect(wireString(writing.field(plain, 'identity')), 'resolved');
    expect(
      writing.field(writing.list(plain, 'facts').single, 'value').toText(),
      'false',
    );
    expect(
      writing
          .field(writing.list(plain, 'inherited_attributes').single, 'value')
          .toText(),
      'true',
    );
    final head = kernel.journal.head(continuity);
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    kernel.commit(
      input('private-duplicate-name', [
        f.row(51, WorldRecord(selector: 'Private')),
        f.row(21, permissions.entity(worlds: [51], labels: {'en': 'Cedar'})),
        f.row(22, permissions.entity(worlds: [51], labels: {'en': 'Secret'})),
      ]),
    );
    final fresh = await service.openContext(context());
    final ambiguous = await service.readFactsRequest(request(fresh.contextId));
    expect(
      wireString(
        writing.field(
          writing.list(ambiguous.facts, 'objects').single,
          'identity',
        ),
      ),
      'ambiguous',
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.readFactsRequest(request(opened.contextId));
    expect(reopened.frame.revision, head);
    expect(reopened.facts.toText(), first.facts.toText());
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    await expectLater(
      service.readFactsRequest(request(opened.contextId)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final scoped = await service.openContext(context());
    final result = await service.readFactsRequest(
      request(scoped.contextId, names: ['Cedar', 'Secret']),
    );
    final visible = writing.list(result.facts, 'objects');
    expect(wireString(writing.field(visible.first, 'identity')), 'resolved');
    expect(wireString(writing.field(visible.last, 'identity')), 'not_found');
    expect(writing.field(visible.last, 'matches').toText(), '0');
    expect(wireString(writing.field(result.facts, 'coverage')), 'restricted');
    await expectLater(
      service.readFactsRequest(
        ReadFactsRequest(
          universe: const Selector('World'),
          contextId: scoped.contextId,
          world: 'Private',
          objectNames: ['Secret'],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
  });

  test('native state reads retain exact initialization history only at the pinned revision', () async {
    final rows = [
      ...initialization.fixture(),
      f.row(
        6,
        CalendarRecord(
          namespace: 'test',
          key: 'clock',
          labels: {},
          unitStructure: {},
        ),
      ),
    ];
    kernel.commit(input('state-initial-base', rows));
    OpenContextRequest request() => contextRequest(
      represented: ContextIdSelector(f.id(5)),
      time: AtFrameTime(ExactTime(initialization.calendar, '10')),
    );
    final before = await service.openContext(request());
    final changes = <Assignment>[];
    compileInitializations(
      universe: f.u,
      revision: before.frame.revision,
      base: canon(continuity, before.frame.revision),
      operations: [initialization.operation()],
      changes: changes,
    );
    kernel.commit(
      CommitInput(
        universe: f.u,
        continuity: continuity,
        expectedHead: before.frame.revision,
        principal: PrincipalId.parse(
          author.id.value.replaceFirst('prf_', 'prn_'),
        ),
        decision: 'Already admitted initialization fixture',
        reason: 'Functional fixture',
        idempotencyKey: 'state-init',
        changes: changes,
      ),
    );
    final after = await service.openContext(request());
    GetStateRequest state(ContextId context) => GetStateRequest(
      universe: const Selector('World'),
      contextId: context,
      entityIds: [f.id(3)],
      predicateFilters: [f.id(4)],
    );
    final old = await service.getStateRequest(state(before.contextId));
    expect(old.state.objects.single.initializationReceipts, isEmpty);
    final current = await service.getStateRequest(state(after.contextId));
    final receipt = current.state.objects.single.initializationReceipts.single;
    expect(receipt.sourceRevision, before.frame.revision);
    expect(
      current.state.objects.single.initializationHistoryCoverage,
      Coverage.complete,
    );
    expect(current.frame.revision, after.frame.revision);
    final entry = await service.getStateRequest(
      GetStateRequest(
        universe: const Selector('World'),
        contextId: after.contextId,
        entityIds: [f.id(3)],
        predicateFilters: [f.id(4)],
        event: f.id(9),
        eventSide: EventTimeSide.before,
      ),
    );
    final exit = await service.getStateRequest(
      GetStateRequest(
        universe: const Selector('World'),
        contextId: after.contextId,
        entityIds: [f.id(3)],
        predicateFilters: [f.id(4)],
        event: f.id(9),
        eventSide: EventTimeSide.after,
      ),
    );
    expect(entry.state.assertions, isEmpty);
    expect(exit.state.assertions.length, 1);
    expect(exit.frame.time, isA<AtEventFrameTime>());
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.getStateRequest(state(after.contextId));
    expect(
      reopened.state.objects.single.initializationReceipts.single
          .toWire()
          .toText(),
      receipt.toWire().toText(),
    );
  });

  test(
    'native state read denies expired contexts and unavailable entities',
    () async {
      await retainedContext(expires: BigInt.zero);
      await expectLater(
        service.getStateRequest(
          GetStateRequest(
            universe: const Selector('World'),
            contextId: proposals.contextId,
            entityIds: [f.id(20)],
            predicateFilters: [],
          ),
        ),
        throwsA(isA<ContextExpiredError>()),
      );
      final opened = await service.openContext(contextRequest());
      await expectLater(
        service.getStateRequest(
          GetStateRequest(
            universe: const Selector('World'),
            contextId: opened.contextId,
            entityIds: [f.id(20)],
            predicateFilters: [],
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    },
  );

  test('native search pins indexed results and pages across restart with exact cursor admission', () async {
    final rows = [
      f.row(20, permissions.entity(labels: {'en': 'Alpha Québec'})),
      f.row(21, permissions.entity(labels: {'en': 'Alpha second'})),
    ];
    kernel.commit(input('search-records', rows));
    final opened = await service.openContext(contextRequest());
    kernel.commit(
      input('search-later', [
        f.row(22, permissions.entity(labels: {'en': 'Alpha later'})),
      ]),
    );
    final first = await service.searchRequest(
      searchRecords(
        opened.contextId,
        query: 'Alpha',
        limit: 1,
        kinds: [RecordKind.entity],
      ),
    );
    expect(first.results.hits.single.recordId, f.id(20));
    expect(first.delivery.complete, isFalse);
    await expectLater(
      service.searchRequest(
        searchRecords(
          opened.contextId,
          query: 'Changed',
          limit: 1,
          cursor: first.delivery.cursor,
          kinds: [RecordKind.entity],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final last = await service.searchRequest(
      searchRecords(
        opened.contextId,
        query: 'Alpha',
        limit: 1,
        cursor: first.delivery.cursor,
        kinds: [RecordKind.entity],
      ),
    );
    expect(last.results.hits.single.recordId, f.id(21));
    expect(last.delivery.complete, isTrue);
    expect(last.delivery.cursor, isNull);
    final fallback = await service.searchRequest(
      searchRecords(opened.contextId, query: 'QUÉ', kinds: [RecordKind.entity]),
    );
    expect(fallback.results.hits.single.recordId, f.id(20));
    final exact = await service.searchRequest(
      searchRecords(opened.contextId, query: f.id(21).value),
    );
    expect(exact.results.hits.single.recordId, f.id(21));
    final literal = await service.searchRequest(
      searchRecords(opened.contextId, query: 'Alpha OR second'),
    );
    expect(literal.results.hits, isEmpty);
    final cursorCount = WorkflowStorage(package.database)
        .keys('cursor:')
        .length;
    await expectLater(
      service.searchRequest(
        searchRecords(opened.contextId, query: List.filled(1025, 'x').join()),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      WorkflowStorage(package.database).keys('cursor:').length,
      cursorCount,
    );
  });

  test('native search denies expired context and invalid limits without retaining cursor state', () async {
    await retainedContext(expires: BigInt.zero);
    await expectLater(
      service.searchRequest(
        searchRecords(proposals.contextId, cursor: 'unknown'),
      ),
      throwsA(isA<ContextExpiredError>()),
    );
    await expectLater(
      service.searchRequest(searchRecords(proposals.contextId, limit: 0)),
      throwsA(isA<InvalidArgumentError>()),
    );
    expect(WorkflowStorage(package.database).keys('cursor:'), isEmpty);
  });

  test('record reads pin payload summary and tombstone history to the admitted revision', () async {
    final original = f.row(20, permissions.entity(labels: {'en': 'Original'}));
    kernel.commit(input('read-record', [original]));
    final old = await service.openContext(contextRequest());
    kernel.commit(
      CommitInput(
        universe: f.u,
        continuity: continuity,
        expectedHead: kernel.journal.head(continuity),
        principal: PrincipalId.parse(
          author.id.value.replaceFirst('prf_', 'prn_'),
        ),
        decision: 'Admitted disposable deletion',
        reason: 'Fixture tombstone',
        idempotencyKey: 'read-delete',
        changes: [
          Assignment(recordId: f.id(20), expected: original.recordVersionId),
        ],
      ),
    );
    final pinned = await service.getRequest(
      readRecords(
        old.contextId,
        [f.id(20)],
        [FieldGroup.payload, FieldGroup.summary, FieldGroup.history],
      ),
    );
    expect(pinned.records.single.recordVersionId, original.recordVersionId);
    expect(pinned.summaries.single.label, 'Original');
    expect(
      pinned.history.single.record!.recordVersionId,
      original.recordVersionId,
    );
    expect(pinned.historyCoverage, Coverage.complete);
    final current = await service.openContext(contextRequest());
    final deleted = await service.getRequest(
      readRecords(current.contextId, [f.id(20)], [FieldGroup.history]),
    );
    expect(deleted.records, isEmpty);
    expect(deleted.history.length, 2);
    expect(deleted.history.first.record, isNull);
    expect(deleted.history.first.reason, 'Fixture tombstone');
    await expectLater(
      service.getRequest(readRecords(current.contextId, [f.id(20)], [])),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      service.getRequest(
        readRecords(current.contextId, [f.id(22)], [FieldGroup.history]),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('record reads enforce scope and perspective before payload or history disclosure', () async {
    kernel.commit(
      input('read-scopes', [
        f.row(50, WorldRecord(selector: 'Campaign')),
        f.row(51, WorldRecord(selector: 'Private')),
        f.row(20, permissions.entity(worlds: [50], labels: {'en': 'Visible'})),
        f.row(21, permissions.entity(worlds: [51], labels: {'en': 'Hidden'})),
        f.row(
          30,
          RepresentedContextRecord(
            universe: f.u,
            kind: CharacterContext(f.ref(20)),
            labels: {},
          ),
        ),
      ]),
    );
    final character = await service.openContext(
      contextRequest(
        perspective: CharacterPerspective(f.id(20)),
        represented: ContextIdSelector(f.id(30)),
      ),
    );
    final perspectiveRead = await service.getRequest(
      readRecords(
        character.contextId,
        [f.id(20)],
        [FieldGroup.payload, FieldGroup.history],
      ),
    );
    final perspectiveWorlds = await service.describeRequest(
      DescribeWorldsRequest(
        universe: const Selector('World'),
        universeId: f.u,
        contextId: character.contextId,
      ),
    );
    expect(perspectiveWorlds.description.worlds.map((w) => w.name.value), [
      'Campaign',
    ]);
    expect(perspectiveRead.historyCoverage, Coverage.restricted);
    expect(perspectiveRead.history, isEmpty);
    await expectLater(
      service.getRequest(
        readRecords(character.contextId, [f.id(21)], [FieldGroup.payload]),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    final scoped = await service.openContext(contextRequest());
    final scopeRead = await service.getRequest(
      readRecords(
        scoped.contextId,
        [f.id(20)],
        [FieldGroup.summary, FieldGroup.history],
      ),
    );
    expect(scopeRead.records, isEmpty);
    expect(scopeRead.summaries.single.label, 'Visible');
    expect(scopeRead.historyCoverage, Coverage.restricted);
    expect(scopeRead.history, isEmpty);
    final scopedState = await service.getStateRequest(
      GetStateRequest(
        universe: const Selector('World'),
        contextId: scoped.contextId,
        entityIds: [f.id(20)],
        predicateFilters: [],
      ),
    );
    expect(
      scopedState.state.objects.single.initializationHistoryCoverage,
      Coverage.restricted,
    );
    expect(scopedState.state.objects.single.initializationReceipts, isEmpty);
    await expectLater(
      service.getStateRequest(
        GetStateRequest(
          universe: const Selector('World'),
          contextId: scoped.contextId,
          entityIds: [f.id(21)],
          predicateFilters: [],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final scopedSearch = await service.searchRequest(
      searchRecords(scoped.contextId, kinds: [RecordKind.entity]),
    );
    expect(scopedSearch.results.hits.map((hit) => hit.recordId), [f.id(20)]);
    final hiddenSearch = await service.searchRequest(
      searchRecords(scoped.contextId, query: 'Hidden'),
    );
    expect(hiddenSearch.results.hits, isEmpty);
    final scopedBrief = await service.getContextRequest(
      GetContextRequest(
        universe: const Selector('World'),
        contextId: scoped.contextId,
        focusIds: [f.id(20)],
        purpose: 'Research',
        byteBudget: 100000,
      ),
    );
    expect(scopedBrief.brief.coverage, Coverage.partial);
    expect(
      scopedBrief.brief.records.any((r) => r.identity.recordId == f.id(21)),
      isFalse,
    );
    await expectLater(
      service.getContextRequest(
        GetContextRequest(
          universe: const Selector('World'),
          contextId: scoped.contextId,
          focusIds: [f.id(21)],
          purpose: 'Research',
          byteBudget: 100000,
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final focused = await service.getRequest(
      GetRequest(
        universe: const Selector('World'),
        contextId: scoped.contextId,
        world: const Selector('Campaign'),
        worldId: permissions.world(50),
        recordIds: [f.id(20)],
        fieldGroups: [],
      ),
    );
    expect(focused.records.single.identity.recordId, f.id(20));
    await expectLater(
      service.getRequest(
        GetRequest(
          universe: const Selector('World'),
          contextId: scoped.contextId,
          world: const Selector('Campaign'),
          worldId: permissions.world(51),
          recordIds: [f.id(20)],
          fieldGroups: [],
        ),
      ),
      throwsA(isA<WorldScopeConflictError>()),
    );
    await expectLater(
      service.getRequest(
        readRecords(
          scoped.contextId,
          [f.id(20), f.id(21)],
          [FieldGroup.payload],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      service.getRequest(readRecords(character.contextId, [f.id(20)], [])),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('record read denies expired contexts before snapshot access', () async {
    await retainedContext(expires: BigInt.zero);
    await expectLater(
      service.getRequest(readRecords(proposals.contextId, [f.id(99)], [])),
      throwsA(isA<ContextExpiredError>()),
    );
  });

  test('native evidence read follows subject facts without including unrelated facts sharing a predicate', () async {
    PropositionRecord fact(int subject) => PropositionRecord(
      subject: f.ref(subject),
      predicate: f.ref(1),
      context: f.ref(99),
      value: const BooleanValue(true),
      quantification: Quantification.particular,
    );
    AssertionRecord evidence(int proposition) => AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: f.ref(proposition),
      polarity: Polarity.support,
      scope: Scope(
        context: f.ref(99),
        applicability: const UniverseApplicability(),
      ),
      validity: const UnspecifiedValidity(),
      persistence: PersistenceSemantics.explicitInterval,
      precision: Precision.exact,
      basis: const AuthorDecisionBasis('Fixture'),
    );
    kernel.commit(
      input('read-evidence', [
        frames.fixture().first,
        f.row(20, f.entity()),
        f.row(21, f.entity()),
        f.row(4, fact(20)),
        f.row(5, evidence(4)),
        f.row(6, fact(21)),
        f.row(7, evidence(6)),
      ]),
    );
    final opened = await service.openContext(contextRequest());
    final result = await service.getRequest(
      readRecords(opened.contextId, [f.id(20)], [FieldGroup.evidence]),
    );
    expect(result.records, isEmpty);
    expect(result.evidence.map((r) => r.identity.recordId).toSet(), {
      f.id(1),
      f.id(4),
      f.id(5),
      f.id(99),
    });
  });

  test('context brief pages retain exact cursors across restart without claiming complete evidence', () async {
    final rows = [for (var n = 20; n < 24; n++) f.row(n, f.entity())];
    kernel.commit(input('brief-records', rows));
    final opened = await service.openContext(contextRequest());
    final budget =
        ContextBrief(
          records: [rows.first],
          requiredDependencies: [],
          coverage: Coverage.partial,
        ).toWire().toBytes().length +
        30;
    GetContextRequest request({String? cursor, String purpose = 'Research'}) =>
        GetContextRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          focusIds: rows.map((r) => r.identity.recordId),
          purpose: purpose,
          byteBudget: budget,
          cursor: cursor,
        );
    final first = await service.getContextRequest(request());
    expect(first.delivery.complete, isFalse);
    expect(first.brief.records.length, 1);
    expect(first.brief.coverage, Coverage.partial);
    await expectLater(
      service.getContextRequest(
        request(cursor: first.delivery.cursor, purpose: 'Changed'),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final collected = [...first.brief.records];
    var cursor = first.delivery.cursor;
    while (cursor != null) {
      final page = await service.getContextRequest(request(cursor: cursor));
      expect(page.brief.coverage, Coverage.partial);
      collected.addAll(page.brief.records);
      cursor = page.delivery.cursor;
      if (cursor == null) expect(page.delivery.complete, isTrue);
    }
    expect(
      collected.map((r) => r.identity.recordId),
      rows.map((r) => r.identity.recordId),
    );
    final full = await service.getContextRequest(
      GetContextRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        focusIds: rows.map((r) => r.identity.recordId),
        purpose: 'Research',
        byteBudget: 100000,
      ),
    );
    expect(full.delivery.complete, isTrue);
    expect(full.brief.coverage, Coverage.complete);
  });

  test('context brief refuses a mandatory record that cannot fit without retaining a cursor', () async {
    final opened = await service.openContext(contextRequest());
    await expectLater(
      service.getContextRequest(
        GetContextRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          focusIds: [f.id(99)],
          purpose: 'Research',
          byteBudget: 1,
        ),
      ),
      throwsA(isA<EvaluationLimitReachedError>()),
    );
    expect(WorkflowStorage(package.database).keys('cursor:'), isEmpty);
  });

  test('expired context cannot retrieve a brief or consume a cursor', () async {
    await retainedContext(expires: BigInt.zero);
    await expectLater(
      service.getContextRequest(
        GetContextRequest(
          universe: const Selector('World'),
          contextId: proposals.contextId,
          focusIds: [f.id(99)],
          purpose: 'Research',
          byteBudget: 100000,
          cursor: 'unknown',
        ),
      ),
      throwsA(isA<ContextExpiredError>()),
    );
  });

  test('inline research retains query evidence without write rights or durable proposal state', () async {
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: null,
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    await retainedContext();
    final request = inlineCheck();
    final before = kernel.journal.head(continuity);
    final report =
        await service.validateInlineRequest(request) as EvaluatedValidation;
    final query = report.submittedInput as QueryInput;
    expect(query.frame, proposal.proposal.baseFrame);
    expect(query.checkScope, CheckScope.universe);
    expect(report.assessment, isA<AbsentAssessment>());
    expect(report.finalBindingDigest, isNull);
    expect(report.execution.operationId, isNull);
    expect(report.execution.inputDigest, canonicalDigest(request.toArgs()));
    final workflow = WorkflowStorage(package.database);
    final retained = CheckedValidation.fromWire(
      workflow.get('validation:${report.execution.runId.value}')!,
    );
    expect(retained.admissible, isTrue);
    expect(retained.capture, isNull);
    expect(retained.report!.toWire().toText(), report.toWire().toText());
    expect(workflow.keys('proposal:').length, 1);
    expect(workflow.keys('operation:'), isEmpty);
    expect(workflow.keys('reserved-record:'), isEmpty);
    expect(workflow.keys('approval:'), isEmpty);
    expect(kernel.identityExists(f.id(20)), isFalse);
    expect(kernel.journal.head(continuity), before);
  });

  test(
    'failed inline preview retains no query result and leaves canon intact',
    () async {
      await retainedContext();
      await expectLater(
        service.validateInlineRequest(
          inlineCheck(
            operations: [
              CreateEntityOperation(
                clientRef: f.id(20).value,
                record: f.entity(classification: f.id(999)),
              ),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
      expect(kernel.identityExists(f.id(20)), isFalse);
      expect(package.database.autocommit, isTrue);
    },
  );

  test(
    'inline named world rejects a shared footprint before retaining evidence',
    () async {
      kernel.commit(
        input('inline-world', [f.row(50, WorldRecord(selector: 'Campaign'))]),
      );
      final opened = await service.openContext(contextRequest());
      await expectLater(
        service.validateInlineRequest(
          InlineValidationRequest(
            universe: const Selector('World'),
            contextId: opened.contextId,
            world: const Selector('Campaign'),
            operations: creation().operations,
            checkScope: CheckScope.candidate,
          ),
        ),
        throwsA(isA<WorldScopeConflictError>()),
      );
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    },
  );

  test('scoped inline research never compiles hidden definitions or retains a result', () async {
    kernel.commit(
      input('inline-world', [f.row(50, WorldRecord(selector: 'Campaign'))]),
    );
    final invalid = [CreateEntityOperation(clientRef: '', record: f.entity())];
    final opened = await service.openContext(contextRequest());
    InlineValidationRequest request(ContextId context, {Selector? world}) =>
        InlineValidationRequest(
          universe: const Selector('World'),
          contextId: context,
          world: world,
          operations: invalid,
          checkScope: CheckScope.candidate,
        );
    await expectLater(
      service.validateInlineRequest(request(opened.contextId)),
      throwsA(isA<InvalidArgumentError>()),
    );
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    final scoped = await service.openContext(contextRequest());
    expect(
      await service.validateInlineRequest(
        request(scoped.contextId, world: const Selector('Campaign')),
      ),
      isA<RestrictedValidation>(),
    );
    await expectLater(
      service.validateInlineRequest(
        request(scoped.contextId, world: const Selector('Hidden')),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    expect(WorkflowStorage(package.database).keys('proposal:').length, 1);
  });

  test('native impact uses pinned universe closure and includes unpublished proposal changes', () async {
    kernel.commit(
      input('impact-worlds', [
        f.row(50, WorldRecord(selector: 'Campaign')),
        f.row(51, WorldRecord(selector: 'Private')),
        f.row(60, permissions.entity(worlds: [50])),
        f.row(61, permissions.entity(worlds: [51])),
      ]),
    );
    final opened = await service.openContext(contextRequest());
    InlineImpactRequest inline({int budget = 65536, UniverseId? guard}) =>
        InlineImpactRequest(
          universe: const Selector('World'),
          universeId: guard ?? f.u,
          contextId: opened.contextId,
          world: const Selector('Campaign'),
          changedRecords: [f.id(60)],
          scope: CheckScope.candidate,
          byteBudget: budget,
        );
    final first = await service.getImpactRequest(inline());
    expect(first.focus, permissions.world(50));
    expect(first.frame, opened.frame);
    expect(first.impact.coverage, Coverage.complete);
    expect(first.impact.records, contains(f.id(61)));
    final draft = await service.proposeRequest(
      CreateProposalRequest(
        universe: const Selector('World'),
        universeId: f.u,
        contextId: opened.contextId,
        operations: [
          CreateEntityOperation(
            clientRef: f.id(20).value,
            record: permissions.entity(worlds: [50]),
          ),
        ],
        submission: Submission.draft,
        rationale: 'Impact fixture',
        idempotencyKey: 'impact-draft',
      ),
      isValidationActive: (_) => false,
    );
    ProposalImpactRequest proposed(ContextId context, {int budget = 65536}) =>
        ProposalImpactRequest(
          universe: const Selector('World'),
          universeId: f.u,
          contextId: context,
          proposalReference: reference(draft),
          scope: CheckScope.universe,
          byteBudget: budget,
        );
    final candidate = await service.getImpactRequest(
      proposed(opened.contextId),
    );
    expect(candidate.impact.records, contains(f.id(20)));
    expect(candidate.impact.records, containsAll(first.impact.records));
    expect(kernel.identityExists(f.id(20)), isFalse);
    await expectLater(
      service.getImpactRequest(inline(budget: 0)),
      throwsA(isA<EvaluationLimitReachedError>()),
    );
    await expectLater(
      service.getImpactRequest(inline(guard: UniverseId.generate())),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    kernel.commit(input('later-impact-canon', [f.row(70, f.entity())]));
    final fresh = await service.openContext(contextRequest());
    await expectLater(
      service.getImpactRequest(proposed(fresh.contextId)),
      stale,
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.getImpactRequest(proposed(opened.contextId));
    expect(
      reopened.impact.toWire().toText(),
      candidate.impact.toWire().toText(),
    );
    expect(reopened.impact.records, isNot(contains(f.id(70))));
    expect(kernel.identityExists(f.id(20)), isFalse);
  });

  test(
    'native impact admits read-only scope and denies hidden seed or world',
    () async {
      kernel.commit(
        input('scoped-impact-worlds', [
          f.row(50, WorldRecord(selector: 'Campaign')),
          f.row(51, WorldRecord(selector: 'Private')),
          f.row(60, permissions.entity(worlds: [50])),
          f.row(61, permissions.entity(worlds: [51])),
        ]),
      );
      await authority.coordinate(
        author,
        () => authority.grant(
          author,
          GrantSpec(
            profileId: writer.id,
            universeId: f.u,
            worlds: [permissions.world(50)],
            propose: false,
            edit: false,
            protected: false,
          ),
        ),
      );
      final opened = await service.openContext(contextRequest());
      InlineImpactRequest request(
        RecordId seed, {
        Selector? world,
        int budget = 65536,
      }) => InlineImpactRequest(
        universe: const Selector('World'),
        universeId: f.u,
        contextId: opened.contextId,
        world: world,
        changedRecords: [seed],
        scope: CheckScope.universe,
        byteBudget: budget,
      );
      final result = await service.getImpactRequest(request(f.id(60)));
      expect(result.impact.coverage, Coverage.restricted);
      expect(result.impact.records, contains(f.id(60)));
      expect(result.impact.records, isNot(contains(f.id(61))));
      expect(result.impact.worldIds, [permissions.world(50)]);
      await expectLater(
        service.getImpactRequest(request(f.id(61), budget: 0)),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        service.getImpactRequest(
          request(f.id(60), world: const Selector('Private')),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    },
  );

  test('synchronous check retains completed evidence across owned reopen without publishing', () async {
    await retainedContext();
    final before = kernel.journal.head(continuity);
    final report = await service.validateProposalRequest(synchronousCheck());
    expect(report, isA<EvaluatedValidation>());
    final execution = report.execution!;
    expect(execution.operationId, isNull);
    expect(execution.coverage, Coverage.complete);
    final validationKey = 'validation:${execution.runId.value}';
    final workflow = WorkflowStorage(package.database);
    final retained = CheckedValidation.fromWire(workflow.get(validationKey)!);
    expect(retained.admissible, isTrue);
    expect(retained.capture, isNotNull);
    expect(retained.report!.toWire().toText(), report.toWire().toText());
    expect(workflow.keys('operation:'), isEmpty);
    expect(workflow.keys('request:${writer.id.value}:validate:'), isEmpty);
    expect(kernel.journal.head(continuity), before);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    expect(
      CheckedValidation.fromWire(
        WorkflowStorage(package.database).get(validationKey)!,
      ).report!.toWire().toText(),
      report.toWire().toText(),
    );
    expect(kernel.journal.head(continuity), before);
  });

  test('synchronous check rejects expired context and universe guard without retaining evidence', () async {
    await retainedContext(expires: BigInt.zero);
    await expectLater(
      service.validateProposalRequest(synchronousCheck()),
      throwsA(isA<ContextExpiredError>()),
    );
    await expectLater(
      service.validateInlineRequest(inlineCheck()),
      throwsA(isA<ContextExpiredError>()),
    );
    await expectLater(
      service.validateProposalRequest(
        synchronousCheck(guard: UniverseId.generate()),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
  });

  test('context validation rejects non-author perspective before proposal frame comparison', () async {
    await authority.withUniverseAuthority(writer, f.u, (current) {
      final frame = proposal.proposal.baseFrame;
      WorkflowStorage(package.database).compareAppend({}, [
        MapEntry(
          'context:${proposals.contextId.value}',
          StoredContext(
            owner: writer.id,
            scope: current.scopeHash,
            expires: BigInt.from(
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            ),
            frame: Frame(
              universe: frame.universe,
              continuity: frame.continuity,
              revision: frame.revision,
              context: frame.context,
              time: frame.time,
              perspective: CharacterPerspective(f.id(20)),
            ),
          ).toWire(),
        ),
      ]);
    });
    await expectLater(
      service.getImpactRequest(
        InlineImpactRequest(
          universe: const Selector('World'),
          universeId: f.u,
          contextId: proposals.contextId,
          changedRecords: [f.id(999)],
          scope: CheckScope.universe,
          byteBudget: 0,
        ),
      ),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
    await expectLater(
      service.validateProposalRequest(synchronousCheck()),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
    await expectLater(
      service.validateInlineRequest(inlineCheck()),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
    await expectLater(
      service.queueValidationRequest(
        queued(),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
    final workflow = WorkflowStorage(package.database);
    expect(workflow.keys('validation:'), isEmpty);
    expect(workflow.keys('operation:'), isEmpty);
  });

  test(
    'context-backed proposal dispatch retains an exact native proposal',
    () async {
      await retainedContext();
      final created = await service.proposeRequest(
        creation(),
        isValidationActive: (_) => false,
      );
      expect(
        created.baseFrame.toWire().toText(),
        proposal.proposal.baseFrame.toWire().toText(),
      );
      expect(
        (await service.proposeRequest(
          creation(),
          isValidationActive: (_) => false,
        )).toWire().toText(),
        created.toWire().toText(),
      );
      await authority.coordinate(
        author,
        () => authority.grant(
          author,
          GrantSpec(
            profileId: writer.id,
            universeId: f.u,
            worlds: null,
            propose: true,
            edit: false,
            protected: true,
          ),
        ),
      );
      await expectLater(
        service.proposeRequest(
          creation(key: 'changed-scope', record: 21),
          isValidationActive: (_) => false,
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(
        WorkflowStorage(package.database).get(proposalReservationKey(f.id(21))),
        isNull,
      );
    },
  );

  test('context-backed dispatch resolves scoped world aliases and guards before reservation', () async {
    kernel.commit(
      input('context-world', [
        f.row(50, WorldRecord(selector: 'Campaign', aliases: ['The Realm'])),
      ]),
    );
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: true,
          edit: true,
          protected: false,
        ),
      ),
    );
    final frame = Frame(
      universe: f.u,
      continuity: continuity,
      revision: kernel.journal.head(continuity),
      context: f.ref(99),
      time: const TimelessFrameTime(),
      perspective: const AuthorPerspective(),
    );
    await authority.withUniverseAuthority(
      writer,
      f.u,
      (current) => WorkflowStorage(package.database).compareAppend({}, [
        MapEntry(
          'context:${proposals.contextId.value}',
          StoredContext(
            owner: writer.id,
            scope: current.scopeHash,
            expires: BigInt.from(
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            ),
            frame: frame,
          ).toWire(),
        ),
      ]),
    );
    CreateProposalRequest scoped(WorldId guard) => CreateProposalRequest(
      universe: const Selector('World'),
      contextId: proposals.contextId,
      world: const Selector('the realm'),
      worldId: guard,
      operations: [
        CreateEntityOperation(
          clientRef: f.id(20).value,
          record: permissions.entity(worlds: [50]),
        ),
      ],
      submission: Submission.draft,
      rationale: 'Scoped campaign entity',
      idempotencyKey: 'scoped-native-create',
    );
    await expectLater(
      service.proposeRequest(
        scoped(permissions.world(51)),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<WorldScopeConflictError>()),
    );
    expect(
      WorkflowStorage(package.database).get(proposalReservationKey(f.id(20))),
      isNull,
    );
    final created = await service.proposeRequest(
      scoped(permissions.world(50)),
      isValidationActive: (_) => false,
    );
    expect(created.worldScope, permissions.world(50));
    expect(created.baseFrame.toWire().toText(), frame.toWire().toText());
    expect(kernel.identityExists(f.id(20)), isFalse);
  });

  test(
    'expired retained context denies dispatch before idempotent retry',
    () async {
      await retainedContext(expires: BigInt.zero);
      await propose(creation());
      await expectLater(
        service.proposeRequest(creation(), isValidationActive: (_) => false),
        throwsA(isA<ContextExpiredError>()),
      );
    },
  );

  test('another context owner cannot supply a proposal frame', () async {
    await retainedContext(owner: author.id);
    await expectLater(
      service.proposeRequest(creation(), isValidationActive: (_) => false),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(
      WorkflowStorage(package.database)
          .keys('request:${writer.id.value}:propose:'),
      isEmpty,
    );
  });

  test(
    'native proposal history, reservations and retries survive owned reopen',
    () async {
      final first = await propose(creation());
      final workflow = WorkflowStorage(package.database);
      final original = workflow.get(proposalKey(reference(first)))!.toText();
      expect(first.version, BigInt.one);
      expect(
        (await propose(creation())).toWire().toText(),
        first.toWire().toText(),
      );
      expect(workflow.get(proposalReservationKey(f.id(20))), isNotNull);
      final revised = await propose(
        ReviseProposalRequest(
          universe: const Selector('World'),
          contextId: proposals.contextId,
          proposalReference: reference(first),
          operations: first.operations,
          submission: Submission.draft,
          rationale: 'Revised native draft',
          idempotencyKey: 'native-revise',
        ),
      );
      expect(revised.version, BigInt.two);
      final submit = SubmitProposalRequest(
        universe: const Selector('World'),
        contextId: proposals.contextId,
        proposalReference: reference(revised),
        idempotencyKey: 'native-submit',
      );
      final submitted = await propose(submit);
      expect(submitted.submission, Submission.submitted);
      final withdrawn = await propose(
        WithdrawProposalRequest(
          universe: const Selector('World'),
          contextId: proposals.contextId,
          proposalReference: reference(submitted),
          idempotencyKey: 'native-withdraw',
        ),
      );
      expect(withdrawn.withdrawn, isTrue);
      expect(withdrawn.version, BigInt.from(4));
      expect(workflow.get(proposalKey(reference(first)))!.toText(), original);
      expect(kernel.identityExists(f.id(20)), isFalse);
      package.close();
      package = OwnedSqliteDatabase.openExisting(
        '${directory.path}/packages/world.sqlite',
      );
      package.recover();
      kernel = SqliteKernel(package.database, f.u);
      service = SqliteValidationWorkflow(
        package: package,
        authority: authority,
        principal: writer,
      );
      expect(
        (await propose(submit)).toWire().toText(),
        submitted.toWire().toText(),
      );
      expect(
        (await propose(creation())).toWire().toText(),
        first.toWire().toText(),
      );
      expect(
        WorkflowStorage(package.database)
            .latestKey('proposal:${first.proposalId.value}:'),
        proposalKey(reference(withdrawn)),
      );
    },
  );

  test('native proposal admission rejects conflicting reservations and changed request keys', () async {
    final first = await propose(creation());
    await expectLater(
      propose(creation(key: 'other-create')),
      throwsA(isA<InvalidArgumentError>()),
    );
    await expectLater(
      propose(creation(record: 21)),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
    final submitted = await propose(
      SubmitProposalRequest(
        universe: const Selector('World'),
        contextId: proposals.contextId,
        proposalReference: reference(first),
        idempotencyKey: 'submit-new',
      ),
    );
    await expectLater(
      propose(
        WithdrawProposalRequest(
          universe: const Selector('World'),
          contextId: proposals.contextId,
          proposalReference: reference(first),
          idempotencyKey: 'withdraw-old',
        ),
      ),
      stale,
    );
    final workflow = WorkflowStorage(package.database);
    expect(
      workflow.latestKey('proposal:${first.proposalId.value}:'),
      proposalKey(reference(submitted)),
    );
    expect(workflow.keys('request:${writer.id.value}:propose:').length, 2);
    expect(workflow.get(proposalReservationKey(f.id(21))), isNull);
    expect(kernel.identityExists(f.id(20)), isFalse);
  });

  test('native proposal retrieval pages real frozen changes across restart and rechecks current rights', () async {
    final opened = await service.openContext(contextRequest());
    final draft = await service.proposeRequest(
      CreateProposalRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        operations: [
          for (var n = 20; n < 45; n++)
            CreateEntityOperation(clientRef: f.id(n).value, record: f.entity()),
        ],
        submission: Submission.draft,
        rationale: 'Paged native proposal',
        idempotencyKey: 'paged-proposal',
      ),
      isValidationActive: (_) => false,
    );
    GetProposalRequest request({String? cursor}) => GetProposalRequest(
      universe: const Selector('World'),
      proposalId: draft.proposalId,
      version: draft.version,
      cursor: cursor,
    );
    final first = await service.getProposalRequest(request());
    final frozen = (first.result as FrozenProposalView).proposal;
    expect(frozen.operations.length, 20);
    expect(frozen.compiledChanges.length, 20);
    expect(frozen.digest, draft.digest);
    expect(first.delivery.complete, isFalse);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final last = await service.getProposalRequest(
      request(cursor: first.delivery.cursor),
    );
    expect(
      (last.result as FrozenProposalView).proposal.compiledChanges.length,
      5,
    );
    expect(last.delivery.complete, isTrue);
    expect(kernel.identityExists(f.id(20)), isFalse);
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: null,
          propose: false,
          edit: false,
          protected: false,
        ),
      ),
    );
    await expectLater(
      service.getProposalRequest(request(cursor: first.delivery.cursor)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test(
    'failed native preview retains no proposal receipt or reservation',
    () async {
      final request = CreateProposalRequest(
        universe: const Selector('World'),
        contextId: proposals.contextId,
        operations: [
          CreateEntityOperation(
            clientRef: f.id(20).value,
            record: f.entity(classification: f.id(999)),
          ),
        ],
        submission: Submission.draft,
        rationale: 'Invalid missing classification',
        idempotencyKey: 'invalid-preview',
      );
      await expectLater(propose(request), throwsA(isA<FormatException>()));
      final workflow = WorkflowStorage(package.database);
      expect(workflow.keys('request:${writer.id.value}:propose:'), isEmpty);
      expect(workflow.keys('reserved-record:'), isEmpty);
      expect(workflow.keys('proposal:').length, 1);
      expect(kernel.identityExists(f.id(20)), isFalse);
      expect(package.database.autocommit, isTrue);
    },
  );

  test('preparation freezes the actual preview and retains running without publishing', () async {
    final head = kernel.journal.head(continuity);
    final queuedStatus = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final task = (await service.prepareValidation(
      queuedStatus.operationId,
      isValidationActive: (_) => false,
    ))!;
    expect(task.operationId, queuedStatus.operationId);
    expect(task.base.map((r) => r.identity.recordId), [f.id(99)]);
    expect(task.candidate.map((r) => r.identity.recordId), contains(f.id(10)));
    expect(task.capture!.authoritySequence, checked.capture!.authoritySequence);
    final result = task.evaluate();
    expect(result.validation.coverage, checked.validation.coverage);
    expect(result.admissible, checked.admissible);
    expect(result.capture, same(task.capture));
    final workflow = WorkflowStorage(package.database);
    expect(
      workflow.get('job:${queuedStatus.operationId.value}:running'),
      isNotNull,
    );
    expect(workflow.keys('validation:'), isEmpty);
    expect(kernel.journal.head(continuity), head);
    expect(kernel.identityExists(f.id(10)), isFalse);
    expect(package.database.autocommit, isTrue);
  });

  Future<OperationId> startValidation() async {
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    await service.prepareValidation(
      status.operationId,
      isValidationActive: (_) => true,
    );
    return status.operationId;
  }

  CancelOperationRequest cancellation(
    OperationId id, {
    String key = 'cancel-check',
  }) => CancelOperationRequest(
    universe: const Selector('World'),
    universeId: f.u,
    operationId: id,
    idempotencyKey: key,
  );

  test(
    'scheduler deduplicates, bounds validation and retains isolate results',
    () async {
      final status = await service.queueValidation(
        queued(),
        resolvedFrame: proposal.proposal.baseFrame,
        isValidationActive: (_) => false,
      );
      final scheduler = NativeValidationScheduler(capacity: 1);
      final done = scheduler.schedule(service, status.operationId);
      expect(scheduler.isActive(f.u, status.operationId), isTrue);
      expect(scheduler.schedule(service, status.operationId), same(done));
      expect(
        () => scheduler.schedule(service, OperationId.generate()),
        throwsA(isA<EvaluationLimitReachedError>()),
      );
      await done;
      expect(scheduler.isActive(f.u, status.operationId), isFalse);
      expect(
        (await service.operation(
          status.operationId,
          isValidationActive: (_) => false,
        )).status.state,
        OperationState.succeeded,
      );
      await scheduler.schedule(service, status.operationId);
      expect(WorkflowStorage(package.database).keys('validation:').length, 1);
      await scheduler.close();
      expect(
        () => scheduler.schedule(service, OperationId.generate()),
        throwsA(isA<EvaluationLimitReachedError>()),
      );
    },
  );

  test('purge retirement stops queued preparation without retaining evidence and leaves scheduler reusable', () async {
    final scheduler = NativeValidationScheduler();
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final done = scheduler.schedule(service, status.operationId);
    scheduler.cancelUniverse(f.u);
    await done;
    expect(scheduler.isActive(f.u, status.operationId), isFalse);
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    await scheduler.schedule(service, status.operationId);
    expect(
      (await service.operation(
        status.operationId,
        isValidationActive: (_) => false,
      )).status.state,
      OperationState.succeeded,
    );
    await scheduler.close();
  });

  test(
    'retired validation cannot retain failure evidence after package close',
    () async {
      final scheduler = NativeValidationScheduler();
      final status = await service.queueValidation(
        queued(),
        resolvedFrame: proposal.proposal.baseFrame,
        isValidationActive: (_) => false,
      );
      final done = scheduler.schedule(service, status.operationId);
      scheduler.cancelUniverse(f.u);
      final path = package.path;
      package.close();
      await done;
      expect(scheduler.isActive(f.u, status.operationId), isFalse);
      package = OwnedSqliteDatabase.openExisting(path);
      package.recover();
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
      await scheduler.close();
    },
  );

  test('scheduler cancellation during preparation never retains completed evidence', () async {
    final scheduler = NativeValidationScheduler();
    bool active(OperationId id) => scheduler.isActive(f.u, id);
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: active,
    );
    final done = scheduler.schedule(service, status.operationId);
    final cancelled = await service.cancelOperation(
      cancellation(status.operationId),
      isValidationActive: active,
      signalCancellation: (id) => scheduler.cancel(f.u, id),
    );
    await done;
    expect(cancelled.state, OperationState.cancelled);
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    expect(
      (await service.operation(
        status.operationId,
        isValidationActive: active,
      )).status.state,
      OperationState.cancelled,
    );
    await scheduler.close();
  });

  test(
    'shutdown drains preparation without retaining a completed result',
    () async {
      final scheduler = NativeValidationScheduler();
      final status = await service.queueValidation(
        queued(),
        resolvedFrame: proposal.proposal.baseFrame,
        isValidationActive: (_) => false,
      );
      final done = scheduler.schedule(service, status.operationId);
      await scheduler.close();
      await done;
      expect(scheduler.isActive(f.u, status.operationId), isFalse);
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
      expect(
        (await service.operation(
          status.operationId,
          isValidationActive: (_) => false,
        )).status.state,
        OperationState.interrupted,
      );
    },
  );

  test(
    'cancellation retains before signaling and retries after owned reopen',
    () async {
      final id = await startValidation();
      var signals = 0;
      final cancelled = await service.cancelOperation(
        cancellation(id),
        isValidationActive: (_) => true,
        signalCancellation: (operation) {
          signals++;
          expect(operation, id);
          expect(
            WorkflowStorage(package.database).get('cancel:${id.value}'),
            isNotNull,
          );
        },
      );
      expect(cancelled.state, OperationState.cancelled);
      expect(cancelled.cancellationRequested, isTrue);
      expect(signals, 1);
      await service.finishValidation(
        id,
        checked,
        isValidationActive: (_) => true,
      );
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
      package.close();
      package = OwnedSqliteDatabase.openExisting(
        '${directory.path}/packages/world.sqlite',
      );
      package.recover();
      kernel = SqliteKernel(package.database, f.u);
      service = SqliteValidationWorkflow(
        package: package,
        authority: authority,
        principal: writer,
      );
      final retry = await service.cancelOperation(
        cancellation(id),
        isValidationActive: (_) => false,
        signalCancellation: (_) => fail('Retry must not signal again'),
      );
      expect(retry.toWire().toText(), cancelled.toWire().toText());
      expect(
        WorkflowStorage(package.database)
            .keys('request:${writer.id.value}:cancel:')
            .length,
        1,
      );
      expect(kernel.identityExists(f.id(10)), isFalse);
    },
  );

  test('cancellation preserves completed evidence and rejects changed idempotent requests', () async {
    final id = await startValidation();
    await service.finishValidation(
      id,
      checked,
      isValidationActive: (_) => true,
    );
    final before = await service.operationStatus(
      id,
      isValidationActive: (_) => false,
    );
    final after = await service.cancelOperation(
      cancellation(id),
      isValidationActive: (_) => false,
      signalCancellation: (_) {},
    );
    expect(after.toWire().toText(), before.toWire().toText());
    expect(WorkflowStorage(package.database).get('cancel:${id.value}'), isNull);
    final changed = CancelOperationRequest(
      universe: const Selector('Renamed World'),
      universeId: f.u,
      operationId: id,
      idempotencyKey: 'cancel-check',
    );
    await expectLater(
      service.cancelOperation(
        changed,
        isValidationActive: (_) => false,
        signalCancellation: (_) => fail('Rejected request must not signal'),
      ),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
  });

  test('another principal cannot cancel the retained operation', () async {
    final id = await startValidation();
    final other = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: author,
    );
    await expectLater(
      other.cancelOperation(
        cancellation(id),
        isValidationActive: (_) => true,
        signalCancellation: (_) => fail('Denied cancellation must not signal'),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(WorkflowStorage(package.database).get('cancel:${id.value}'), isNull);
    expect(
      WorkflowStorage(package.database)
          .keys('request:${author.id.value}:cancel:'),
      isEmpty,
    );
  });

  test(
    'narrowed world scope cannot cancel a shared retained operation',
    () async {
      final id = await startValidation();
      await authority.coordinate(
        author,
        () => authority.grant(
          author,
          GrantSpec(
            profileId: writer.id,
            universeId: f.u,
            worlds: [permissions.world(50)],
            propose: true,
            edit: true,
            protected: false,
          ),
        ),
      );
      await expectLater(
        service.cancelOperation(
          cancellation(id),
          isValidationActive: (_) => true,
          signalCancellation: (_) =>
              fail('Denied cancellation must not signal'),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      final workflow = WorkflowStorage(package.database);
      expect(workflow.get('cancel:${id.value}'), isNull);
      expect(workflow.keys('request:${writer.id.value}:cancel:'), isEmpty);
    },
  );

  test('completion atomically retains exact evidence and terminal status across reopen', () async {
    final id = await startValidation();
    await service.finishValidation(
      id,
      checked,
      isValidationActive: (_) => true,
    );
    final workflow = WorkflowStorage(package.database);
    final retained = CheckedValidation.fromWire(workflow.get(key())!);
    expect(retained.validation.operationId, id);
    expect(
      (retained.report as EvaluatedValidation).finalBindingDigest,
      isNotNull,
    );
    final status = await service.operationStatus(
      id,
      isValidationActive: (_) => false,
    );
    expect(status.state, OperationState.succeeded);
    expect(
      status.validation!.toWire().toText(),
      retained.report!.toWire().toText(),
    );
    final terminal = workflow.get('job:${id.value}:terminal')!.toText();
    await service.failValidation(
      id,
      StateError('late failure'),
      isValidationActive: (_) => false,
    );
    expect(workflow.get('job:${id.value}:terminal')!.toText(), terminal);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    expect(
      (await service.operationStatus(
        id,
        isValidationActive: (_) => false,
      )).toWire().toText(),
      status.toWire().toText(),
    );
    expect(kernel.identityExists(f.id(10)), isFalse);
  });

  test(
    'stale completion retains failure with original pending validation only',
    () async {
      final id = await startValidation();
      await authority.coordinate(
        author,
        () => authority.grant(author, grant()),
      );
      await service.finishValidation(
        id,
        checked,
        isValidationActive: (_) => true,
      );
      final workflow = WorkflowStorage(package.database);
      expect(workflow.keys('validation:'), isEmpty);
      final status = await service.operationStatus(
        id,
        isValidationActive: (_) => false,
      );
      expect(status.state, OperationState.failed);
      expect(status.failure, isNotNull);
      final initial = StoredOperation.fromWire(
        workflow.get('operation:${id.value}')!,
      );
      final terminal = StoredOperation.fromWire(
        workflow.get('job:${id.value}:terminal')!,
      );
      expect(
        terminal.status.validation!.toWire().toText(),
        initial.status.validation!.toWire().toText(),
      );
      expect(
        (status.validation as EvaluatedValidation).finalBindingDigest,
        isNull,
      );
    },
  );

  test(
    'worker failure retains terminal state and suppresses late completion',
    () async {
      final id = await startValidation();
      await service.failValidation(
        id,
        StateError('evaluation failed'),
        isValidationActive: (_) => true,
      );
      expect(
        (await service.operation(
          id,
          isValidationActive: (_) => false,
        )).status.state,
        OperationState.failed,
      );
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
      await service.finishValidation(
        id,
        checked,
        isValidationActive: (_) => false,
      );
      expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    },
  );

  test(
    'preparation rejects stale authority before retaining running',
    () async {
      final status = await service.queueValidation(
        queued(),
        resolvedFrame: proposal.proposal.baseFrame,
        isValidationActive: (_) => false,
      );
      await authority.coordinate(
        author,
        () => authority.grant(author, grant()),
      );
      await expectLater(
        service.prepareValidation(
          status.operationId,
          isValidationActive: (_) => false,
        ),
        stale,
      );
      expect(WorkflowStorage(package.database).keys('job:'), isEmpty);
    },
  );

  test('cancelled validation is not prepared', () async {
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final workflow = WorkflowStorage(package.database);
    workflow.compareAppend({}, [
      MapEntry(
        'cancel:${status.operationId.value}',
        CanonicalObject([
          MapEntry('owner', CanonicalString(writer.id.value)),
          MapEntry('cancelled', const CanonicalBool(true)),
        ]),
      ),
    ]);
    expect(
      await service.prepareValidation(
        status.operationId,
        isValidationActive: (_) => false,
      ),
      isNull,
    );
    expect(workflow.get('job:${status.operationId.value}:running'), isNull);
    await service.finishValidation(
      status.operationId,
      checked,
      isValidationActive: (_) => false,
    );
    await service.failValidation(
      status.operationId,
      StateError('late failure'),
      isValidationActive: (_) => false,
    );
    expect(workflow.get('job:${status.operationId.value}:terminal'), isNull);
    expect(workflow.keys('validation:'), isEmpty);
  });

  test('queued validation retains one exact capture and retry identity across owned reopen', () async {
    final first = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    expect(first.state, OperationState.queued);
    final pending = first.validation as EvaluatedValidation;
    expect(pending.execution.coverage, Coverage.partial);
    expect(pending.execution.operationId, first.operationId);
    expect(pending.finalBindingDigest, isNull);
    final workflow = WorkflowStorage(package.database);
    final stored = StoredOperation.fromWire(
      workflow.get('operation:${first.operationId.value}')!,
    );
    expect(stored.owner, writer.id);
    expect(stored.validationCapture!.latestProposalKey, proposal.key);
    expect(
      stored.validationCapture!.authoritySequence,
      checked.capture!.authoritySequence,
    );
    expect(workflow.keys('request:').length, 1);
    expect(workflow.keys('validation:'), isEmpty);
    final retry = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    expect(retry.toWire().toText(), first.toWire().toText());
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopened = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    expect(reopened.toWire().toText(), first.toWire().toText());
    expect(WorkflowStorage(package.database).keys('operation:').length, 1);
    expect(kernel.identityExists(proposal.changes.single.recordId), isFalse);
  });

  test('native operation lookup pages retained findings across restart and pins changing results', () async {
    final initial = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final workflow = WorkflowStorage(package.database);
    final stored = StoredOperation.fromWire(
      workflow.get('operation:${initial.operationId.value}')!,
    );
    final v = checked.validation;
    Validation execution(int count) => Validation(
      operationId: initial.operationId,
      runId: v.runId,
      coverage: v.coverage,
      findings: [
        for (var n = 0; n < count; n++)
          Finding(
            message: 'Retained fixture finding $n',
            fingerprint: FindingFingerprint('a' * 64),
            ruleId: f.id(99),
            outcome: EvidenceOutcome.supported,
            evidence: [],
            coverage: Coverage.complete,
          ),
      ],
      unsupportedCapabilities: v.unsupportedCapabilities,
      inputDigest: v.inputDigest,
      evaluatorVersion: v.evaluatorVersion,
    );
    StoredOperation retained(Validation v, OperationState state) =>
        StoredOperation(
          owner: stored.owner,
          digest: stored.digest,
          input: stored.input,
          footprint: stored.footprint,
          validationCapture: stored.validationCapture,
          status: OperationStatus(
            operationId: initial.operationId,
            kind: OperationKind.validate,
            state: state,
            proposal: stored.status.proposal,
            validation: v,
            cancellationRequested: false,
          ),
        );
    final running = retained(execution(205), OperationState.running);
    workflow.compareAppend({}, [
      MapEntry('job:${initial.operationId.value}:running', running.toWire()),
    ]);
    GetOperationIdRequest byId({String? cursor, UniverseId? universeId}) =>
        GetOperationIdRequest(
          universe: const Selector('World'),
          universeId: universeId ?? f.u,
          operationId: initial.operationId,
          cursor: cursor,
        );
    GetOperationKeyRequest byKey({String? cursor}) => GetOperationKeyRequest(
      universe: const Selector('World'),
      universeId: f.u,
      operationKind: OperationKind.validate,
      idempotencyKey: queued().idempotencyKey,
      cursor: cursor,
    );
    final first = await service.getOperationRequest(
      byId(),
      isValidationActive: (_) => true,
    );
    final alias = await service.getOperationRequest(
      byKey(),
      isValidationActive: (_) => true,
    );
    expect(alias.status.toWire().toText(), first.status.toWire().toText());
    expect(first.frame, proposal.proposal.baseFrame);
    expect(first.status.state, OperationState.running);
    expect(first.status.validation!.execution!.findings.length, 100);
    expect(first.delivery.complete, isFalse);
    expect(
      (first.status.validation as EvaluatedValidation).finalBindingDigest,
      isNull,
    );
    await expectLater(
      service.getOperationRequest(
        byKey(cursor: first.delivery.cursor),
        isValidationActive: (_) => true,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      service.getOperationRequest(
        byId(universeId: UniverseId.generate()),
        isValidationActive: (_) => true,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final other = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: author,
    );
    await expectLater(
      other.getOperationRequest(byId(), isValidationActive: (_) => true),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final middle = await service.getOperationRequest(
      byId(cursor: first.delivery.cursor),
      isValidationActive: (_) => false,
    );
    expect(middle.status.state, OperationState.interrupted);
    expect(
      middle.status.validation!.execution!.findings.first.message,
      'Retained fixture finding 100',
    );
    expect(middle.delivery.complete, isFalse);
    final last = await service.getOperationRequest(
      byId(cursor: middle.delivery.cursor),
      isValidationActive: (_) => false,
    );
    expect(last.status.validation!.execution!.findings.length, 5);
    expect(last.delivery.complete, isTrue);
    final changed = execution(206);
    final report = checked.capture!.report(
      proposal: proposal.reference,
      baseFrame: proposal.proposal.baseFrame,
      execution: changed,
      finished: true,
    );
    final completed = CheckedValidation(
      proposalDigest: checked.proposalDigest,
      validation: changed,
      admissible: checked.admissible,
      capture: checked.capture,
      report: report,
    );
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry('validation:${changed.runId.value}', completed.toWire()),
      MapEntry(
        'job:${initial.operationId.value}:terminal',
        retained(changed, OperationState.succeeded).toWire(),
      ),
    ]);
    await expectLater(
      service.getOperationRequest(
        byId(cursor: first.delivery.cursor),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final refreshed = await service.getOperationRequest(
      byKey(),
      isValidationActive: (_) => false,
    );
    expect(refreshed.status.state, OperationState.succeeded);
    expect(
      (refreshed.status.validation as EvaluatedValidation).finalBindingDigest,
      report.finalBindingDigest,
    );
    expect(kernel.identityExists(proposal.changes.single.recordId), isFalse);
  });

  test('queued retry resolves retained terminal state and rejects a changed request', () async {
    final initial = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final workflow = WorkflowStorage(package.database);
    final op = StoredOperation.fromWire(
      workflow.get('operation:${initial.operationId.value}')!,
    );
    final failed = StoredOperation(
      owner: op.owner,
      digest: op.digest,
      input: op.input,
      footprint: op.footprint,
      validationCapture: op.validationCapture,
      status: OperationStatus(
        operationId: initial.operationId,
        kind: OperationKind.validate,
        state: OperationState.failed,
        failure: 'Interrupted check fixture',
        proposal: op.status.proposal,
        validation: op.status.validation,
        cancellationRequested: false,
      ),
    );
    workflow.compareAppend({}, [
      MapEntry('job:${initial.operationId.value}:terminal', failed.toWire()),
    ]);
    final retry = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    expect(retry.state, OperationState.failed);
    expect(
      (retry.validation as EvaluatedValidation).finalBindingDigest,
      isNull,
    );
    await expectLater(
      service.queueValidation(
        queued(scope: CheckScope.universe),
        resolvedFrame: proposal.proposal.baseFrame,
        isValidationActive: (_) => false,
      ),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
    expect(workflow.keys('operation:').length, 1);
    expect(package.database.autocommit, isTrue);
  });

  test(
    'queue rejects a different resolved frame without retaining a request',
    () async {
      final frame = proposal.proposal.baseFrame;
      await expectLater(
        service.queueValidation(
          queued(),
          resolvedFrame: Frame(
            universe: frame.universe,
            continuity: frame.continuity,
            revision: RevisionId.generate(),
            context: frame.context,
            time: frame.time,
            perspective: frame.perspective,
          ),
          isValidationActive: (_) => false,
        ),
        stale,
      );
      expect(WorkflowStorage(package.database).keys('request:'), isEmpty);
      expect(WorkflowStorage(package.database).keys('operation:'), isEmpty);
      expect(package.database.autocommit, isTrue);
    },
  );

  test('scoped queue retains no complete assessment capture and returns restricted validation', () async {
    kernel.commit(
      input('world-fixture', [f.row(50, WorldRecord(selector: 'Campaign'))]),
    );
    expect(
      package.database
          .select('SELECT text FROM search_index WHERE version_id=?', [
            f.ver(50).value,
          ])
          .map((row) => row['text']),
      contains('Campaign'),
    );
    final head = kernel.journal.head(continuity);
    proposal = proposals.prepare(
      principal: writer.id,
      request: proposals.create(
        operations: [
          CreateEntityOperation(
            clientRef: f.id(10).value,
            record: permissions.entity(worlds: [50]),
          ),
        ],
      ),
      frame: Frame(
        universe: f.u,
        continuity: continuity,
        revision: head,
        context: f.ref(99),
        time: const TimelessFrameTime(),
        perspective: const AuthorPerspective(),
      ),
      base: canon(continuity, head),
    );
    WorkflowStorage(package.database)
        .compareAppend({}, [MapEntry(proposal.key, proposal.toWire())]);
    await authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: [permissions.world(50)],
          propose: true,
          edit: true,
          protected: false,
        ),
      ),
    );
    await retainedContext();
    final restricted = await service.validateProposalRequest(
      synchronousCheck(),
    );
    expect(restricted, isA<RestrictedValidation>());
    final retainedSynchronous = CheckedValidation.fromWire(
      WorkflowStorage(package.database)
          .get(WorkflowStorage(package.database).keys('validation:').single)!,
    );
    expect(retainedSynchronous.admissible, isFalse);
    expect(retainedSynchronous.capture, isNull);
    expect(retainedSynchronous.validation.coverage, Coverage.restricted);
    final result = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    expect(result.validation, isA<RestrictedValidation>());
    expect(result.proposal, isNull);
    final op = StoredOperation.fromWire(
      WorkflowStorage(package.database)
          .get('operation:${result.operationId.value}')!,
    );
    expect(op.validationCapture, isNull);
    expect(op.status.state, OperationState.queued);
    expect(op.status.validation!.coverage, Coverage.partial);
    final task = (await service.prepareValidation(
      result.operationId,
      isValidationActive: (_) => false,
    ))!;
    expect(task.base, isEmpty);
    expect(task.candidate, isEmpty);
    expect(task.capture, isNull);
    final evaluated = task.evaluate();
    expect(evaluated.validation.coverage, Coverage.restricted);
    expect(evaluated.admissible, isFalse);
    expect(evaluated.capture, isNull);
    await service.finishValidation(
      result.operationId,
      evaluated,
      isValidationActive: (_) => true,
    );
    final completed = await service.operationStatus(
      result.operationId,
      isValidationActive: (_) => false,
    );
    expect(completed.state, OperationState.succeeded);
    expect(completed.validation, isA<RestrictedValidation>());
    expect(completed.proposal, isNull);
    GetOperationIdRequest lookup({String? cursor}) => GetOperationIdRequest(
      universe: const Selector('World'),
      universeId: f.u,
      operationId: result.operationId,
      cursor: cursor,
    );
    final public = await service.getOperationRequest(
      lookup(),
      isValidationActive: (_) => false,
    );
    expect(public.status.validation, isA<RestrictedValidation>());
    expect(public.status.proposal, isNull);
    expect(public.status.failure, isNull);
    expect(public.delivery.complete, isTrue);
    expect(public.delivery.cursor, isNull);
    await expectLater(
      service.getOperationRequest(
        lookup(cursor: 'untrusted'),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final retained = CheckedValidation.fromWire(
      WorkflowStorage(package.database)
          .get('validation:${evaluated.validation.runId.value}')!,
    );
    expect(retained.admissible, isFalse);
    expect(retained.capture, isNull);
    expect(retained.report, isA<RestrictedValidation>());
    expect(package.database.autocommit, isTrue);
  });

  test('retained validation resolves interrupted state after owned package reopen without rewriting history', () async {
    final id = OperationId.generate();
    final op = StoredOperation(
      owner: writer.id,
      digest: 'a' * 64,
      input: null,
      footprint: proposal.footprint,
      validationCapture: checked.capture,
      status: OperationStatus(
        operationId: id,
        kind: OperationKind.validate,
        state: OperationState.running,
        proposal: proposal.proposal,
        validation: checked.validation,
        cancellationRequested: false,
      ),
    );
    WorkflowStorage(package.database)
        .compareAppend({}, [MapEntry('operation:${id.value}', op.toWire())]);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final recovered = await service.operation(
      id,
      isValidationActive: (_) => false,
    );
    expect(recovered.status.state, OperationState.interrupted);
    final public = await service.operationStatus(
      id,
      isValidationActive: (_) => false,
    );
    expect(public.state, OperationState.interrupted);
    final unfinished = public.validation as EvaluatedValidation;
    expect(
      (unfinished.assessment as UnavailableAssessment).reason,
      UnavailableReason.failedOrCancelledCheck,
    );
    expect(unfinished.finalBindingDigest, isNull);
    expect(
      recovered.validationCapture!.toWire().toText(),
      checked.capture!.toWire().toText(),
    );
    expect(
      WorkflowStorage(package.database).get('operation:${id.value}')!.toText(),
      op.toWire().toText(),
    );
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry(
        'cancel:${id.value}',
        CanonicalObject([
          MapEntry('owner', CanonicalString(writer.id.value)),
          MapEntry('cancelled', const CanonicalBool(true)),
        ]),
      ),
    ]);
    expect(
      (await service.operation(
        id,
        isValidationActive: (_) => true,
      )).status.state,
      OperationState.cancelled,
    );
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
  });

  test('lost commit response recovers the real durable receipt ahead of a cancellation marker', () async {
    final id = OperationId.generate();
    final commit = await proposalCommitInput(
      stored: proposal,
      universe: f.u,
      principal: writer.id,
      idempotencyKey: 'commit-recovery-fixture',
      readCanon: canon,
    );
    final op = StoredOperation(
      owner: writer.id,
      digest: 'b' * 64,
      input: commit,
      footprint: proposal.footprint,
      status: OperationStatus(
        operationId: id,
        kind: OperationKind.commit,
        state: OperationState.committing,
        proposal: proposal.proposal,
        cancellationRequested: false,
      ),
    );
    // Already checked disposable input; application approval remains unimplemented.
    final revision = kernel.commit(commit);
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry('operation:${id.value}', op.toWire()),
      MapEntry(
        'cancel:${id.value}',
        CanonicalObject([
          MapEntry('owner', CanonicalString(writer.id.value)),
          MapEntry('cancelled', const CanonicalBool(true)),
        ]),
      ),
    ]);
    final recovered = await service.operation(
      id,
      isValidationActive: (_) => false,
    );
    expect(recovered.status.state, OperationState.succeeded);
    expect(recovered.status.receipt!.revision, revision);
    expect(recovered.status.receipt!.proposalId, proposal.reference.proposalId);
    expect(kernel.journal.head(continuity), revision);
    expect(
      WorkflowStorage(package.database).get('operation:${id.value}')!.toText(),
      op.toWire().toText(),
    );
  });

  Future<SourceAssessmentV1> submittedAssessment() async {
    final workflow = WorkflowStorage(package.database);
    workflow.compareAppend(
      {},
      sources.staging(sources.source()).entries.toList(),
    );
    kernel.commit(
      input('sources', [
        f.row(
          1,
          SourceRecord(
            label: 'External source',
            origin: const OriginMetadata(),
            versions: [f.id(2)],
          ),
        ),
        f.row(2, sources.source()),
      ]),
    );
    final head = kernel.journal.head(continuity);
    proposal = proposals.prepare(
      principal: writer.id,
      request: CreateProposalRequest(
        universe: const Selector('World'),
        contextId: proposals.contextId,
        operations: proposals.create().operations,
        submission: Submission.submitted,
        rationale: 'External evidence review',
        idempotencyKey: 'submitted',
      ),
      frame: Frame(
        universe: f.u,
        continuity: continuity,
        revision: head,
        context: f.ref(99),
        time: const TimelessFrameTime(),
        perspective: const AuthorPerspective(),
      ),
      base: canon(continuity, head),
    );
    workflow.compareAppend({}, [MapEntry(proposal.key, proposal.toWire())]);
    var wire = accounting.replace(assessments.body().toWire(), [
      'proposal',
    ], proposal.reference.toWire());
    wire = accounting.replace(wire, [
      'base_frame',
    ], proposal.proposal.baseFrame.toWire());
    wire = accounting.replace(wire, [
      'assessor',
      'principal',
    ], CanonicalString(writer.id.value.replaceFirst('prf_', 'prn_')));
    return SourceAssessmentV1.fromWire(wire);
  }

  Future<CheckedValidation> completedSubmitted() async {
    final body = await submittedAssessment();
    await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'approval-assessment',
    );
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final task = (await service.prepareValidation(
      status.operationId,
      isValidationActive: (_) => true,
    ))!;
    final result = task.evaluate();
    await service.finishValidation(
      status.operationId,
      result,
      isValidationActive: (_) => true,
    );
    return CheckedValidation.fromWire(
      WorkflowStorage(package.database)
          .get('validation:${result.validation.runId.value}')!,
    );
  }

  test('native assessment retrieval fragments exact evidence and rejects a changed selection cursor', () async {
    var body = await submittedAssessment();
    CanonicalValue wire = body.toWire();
    final text = List.filled(2300, '漢🙂').join();
    wire = accounting.replace(
      wire,
      ['assessor', 'tool'],
      ToolIdentity(
        name: text,
        version: 'fixture',
        modelRevision: 'fixture',
        procedureDigest: Sha256Hex('a' * 64),
      ).toWire(),
    );
    wire = accounting.replace(wire, [
      'assessor',
      'method',
    ], CanonicalString(Method.externalModelReview.wireName));
    wire = accounting.replace(wire, [
      'inventory_declaration',
      'rationale',
    ], CanonicalString(text));
    body = SourceAssessmentV1.fromWire(wire);
    final attached = await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'paged-assessment',
    );
    GetProposalRequest request({String? cursor, AssessmentRef? exact}) =>
        GetProposalRequest(
          universe: const Selector('World'),
          proposalId: proposal.reference.proposalId,
          version: proposal.reference.version,
          viewGroup: ProposalView.assessment,
          cursor: cursor,
          assessmentReference: exact,
        );
    final first = await service.getProposalRequest(request());
    final firstPage = (first.result as AssessmentProposalView).assessment;
    expect(firstPage.state, isA<BoundAssessment>());
    expect(firstPage.fragment, isNotNull);
    expect(first.delivery.complete, isFalse);
    final finalPage = await service.getProposalRequest(
      request(cursor: first.delivery.cursor),
    );
    final last = (finalPage.result as AssessmentProposalView).assessment;
    expect(finalPage.delivery.complete, isTrue);
    final canonical =
        firstPage.fragment!.canonicalEnvelopeUtf8 +
        last.fragment!.canonicalEnvelopeUtf8;
    expect(
      canonical,
      WorkflowStorage(package.database)
          .get('assessment:${attached.selected!.assessmentId.value}')!
          .toText(),
    );
    await service.selectAssessment(
      proposal.reference,
      expectedGeneration: BigInt.one,
      selected: null,
      idempotencyKey: 'paged-clear',
    );
    await expectLater(
      service.getProposalRequest(request(cursor: first.delivery.cursor)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final historical = await service.getProposalRequest(
      request(exact: attached.selected),
    );
    expect(
      (historical.result as AssessmentProposalView).assessment.state,
      isA<AbsentAssessment>(),
    );
    expect(
      (historical.result as AssessmentProposalView).assessment.fragment,
      isNotNull,
    );
  });

  test(
    'context-backed assessment and validation bind exact submitted sources',
    () async {
      final body = await submittedAssessment();
      final opened = await service.openContext(contextRequest());
      final attach = AttachAssessmentRequest(
        universe: const Selector('World'),
        universeId: f.u,
        contextId: opened.contextId,
        proposalReference: proposal.reference,
        expectedSelectionGeneration: BigInt.zero,
        body: body,
        idempotencyKey: 'context-attach',
      );
      final attached = await service.assessmentRequest(attach);
      expect(attached.generation, BigInt.one);
      expect(
        (await service.assessmentRequest(attach)).toWire().toText(),
        attached.toWire().toText(),
      );
      final completed = await service.validateProposalRequest(
        ProposalValidationRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: proposal.reference,
          checkScope: CheckScope.candidate,
        ),
      );
      expect(
        (completed as EvaluatedValidation).submittedInput,
        isA<SourceAssessedCandidateInput>(),
      );
      expect(completed.execution.operationId, isNull);
      final queued = await service.queueValidationRequest(
        QueuedProposalValidationRequest(
          universe: const Selector('World'),
          universeId: f.u,
          contextId: opened.contextId,
          proposalReference: proposal.reference,
          checkScope: CheckScope.candidate,
          idempotencyKey: 'context-source-check',
        ),
        isValidationActive: (_) => false,
      );
      expect(
        (queued.validation as EvaluatedValidation).submittedInput,
        isA<SourceAssessedCandidateInput>(),
      );
      final cleared = await service.assessmentRequest(
        SelectAssessmentRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: proposal.reference,
          expectedSelectionGeneration: BigInt.one,
          assessmentReference: null,
          idempotencyKey: 'context-clear',
        ),
      );
      expect(cleared.generation, BigInt.two);
      expect(cleared.selected, isNull);
    },
  );

  test(
    'expired context blocks queued validation and assessment mutation',
    () async {
      await retainedContext(expires: BigInt.zero);
      await expectLater(
        service.queueValidationRequest(
          queued(),
          isValidationActive: (_) => false,
        ),
        throwsA(isA<ContextExpiredError>()),
      );
      await expectLater(
        service.assessmentRequest(
          SelectAssessmentRequest(
            universe: const Selector('World'),
            contextId: proposals.contextId,
            proposalReference: proposal.reference,
            expectedSelectionGeneration: BigInt.zero,
            assessmentReference: null,
            idempotencyKey: 'expired-clear',
          ),
        ),
        throwsA(isA<ContextExpiredError>()),
      );
      final workflow = WorkflowStorage(package.database);
      expect(workflow.keys('request:${writer.id.value}:validate:'), isEmpty);
      expect(workflow.keys('assessment-receipt:'), isEmpty);
    },
  );

  test(
    'different pinned context cannot queue or attach to a submitted proposal',
    () async {
      final old = kernel.journal.head(continuity);
      final body = await submittedAssessment();
      final opened = await service.openContext(
        OpenContextRequest(
          universe: const Selector('World'),
          continuityId: continuity,
          revision: ExactRevisionSelector(revisionId: old),
          representedContext: ContextIdSelector(f.id(99)),
          temporalQuery: const TimelessFrameTime(),
          temporalSystems: [],
          perspective: const AuthorPerspective(),
        ),
      );
      await expectLater(
        service.validateProposalRequest(
          ProposalValidationRequest(
            universe: const Selector('World'),
            contextId: opened.contextId,
            proposalReference: proposal.reference,
            checkScope: CheckScope.candidate,
          ),
        ),
        stale,
      );
      await expectLater(
        service.queueValidationRequest(
          QueuedProposalValidationRequest(
            universe: const Selector('World'),
            contextId: opened.contextId,
            proposalReference: proposal.reference,
            checkScope: CheckScope.candidate,
            idempotencyKey: 'wrong-frame-check',
          ),
          isValidationActive: (_) => false,
        ),
        stale,
      );
      await expectLater(
        service.assessmentRequest(
          AttachAssessmentRequest(
            universe: const Selector('World'),
            contextId: opened.contextId,
            proposalReference: proposal.reference,
            expectedSelectionGeneration: BigInt.zero,
            body: body,
            idempotencyKey: 'wrong-frame-attach',
          ),
        ),
        stale,
      );
      expect(
        WorkflowStorage(package.database).keys('assessment-receipt:'),
        isEmpty,
      );
      expect(
        WorkflowStorage(package.database)
            .keys('request:${writer.id.value}:validate:'),
        isEmpty,
      );
    },
  );

  test('author approval binds the exact retained assessment and checked digest across reopen', () async {
    final completed = await completedSubmitted();
    expect(completed.admissible, isTrue);
    final review = await authorService().review(proposal.reference);
    final reviewFields = WireFields(review, {
      'proposal',
      'changes',
      'diff',
      'footprint',
      'latest',
      'assessment_review',
    });
    final assessment = AssessmentReview.fromWire(
      reviewFields.require('assessment_review'),
    );
    expect(assessment.envelope, isNotNull);
    final reviewHead = kernel.journal.head(continuity);
    final approved = await authorService().approve(
      proposal.reference,
      completed.validation.runId,
    );
    final approvalKey =
        'approval:${author.id.value}:${proposal.reference.digest}:${completed.validation.runId.value}';
    final value = WorkflowStorage(package.database).get(approvalKey)!;
    final evidence = WireFields(value, {
      'author',
      'proposal',
      'validation_digest',
      'evaluator',
    });
    expect(evidence.string('author'), author.id.value);
    expect(
      evidence.string('validation_digest'),
      canonicalDigest(completed.toWire()),
    );
    expect(evidence.string('evaluator'), completed.validation.evaluatorVersion);
    expect(kernel.identityExists(f.id(10)), isFalse);
    expect(kernel.journal.head(continuity), reviewHead);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    expect(
      (await authorService().review(proposal.reference)).toText(),
      review.toText(),
    );
    expect(
      (await authorService().approve(
        proposal.reference,
        completed.validation.runId,
      )).toText(),
      approved.toText(),
    );
    expect(
      WorkflowStorage(package.database).get(approvalKey)!.toText(),
      value.toText(),
    );
  });

  test(
    'contributor cannot approve and selection changes invalidate approval',
    () async {
      final completed = await completedSubmitted();
      await expectLater(
        service.approve(proposal.reference, completed.validation.runId),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await service.selectAssessment(
        proposal.reference,
        expectedGeneration: BigInt.one,
        selected: null,
        idempotencyKey: 'clear-before-approval',
      );
      await expectLater(
        authorService().approve(proposal.reference, completed.validation.runId),
        stale,
      );
      expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    },
  );

  CommitRequest publication(
    CheckedValidation checked, {
    String key = 'publish',
  }) => CommitRequest(
    universe: const Selector('World'),
    universeId: f.u,
    proposalReference: proposal.reference,
    expectedBaseRevision: proposal.proposal.baseFrame.revision,
    validationRun: checked.validation.runId,
    idempotencyKey: key,
  );

  for (final includeEvents in [false, true]) {
    for (final requiresReview in [false, true]) {
      test(
        'scoped evidence policy validates and publishes through SQLite with review=$requiresReview events=$includeEvents',
        () async {
          final rows =
              (includeEvents
                      ? event_evidence.fixture(effect: true)
                      : evidence.fixture())
                  .where(
                    (r) => ![
                      f.id(99),
                      f.id(10),
                      f.id(40),
                    ].contains(r.identity.recordId),
                  )
                  .toList();
          final sourceRow = rows.singleWhere(
            (r) => r.identity.recordId == f.id(12),
          );
          final source = SourceVersionRecord.fromWire(
            accounting.replace(sourceRow.payload.toWire(), [
              'source',
            ], f.ref(14).toCanonical()),
          );
          evidence.replace(rows, 12, source);
          rows.add(
            f.row(
              10,
              CalendarRecord(
                namespace: 'test',
                key: 'clock',
                labels: {},
                unitStructure: {},
              ),
            ),
          );
          rows.add(
            f.row(
              14,
              SourceRecord(
                label: 'Private recollection',
                origin: const OriginMetadata(),
                versions: [f.id(12)],
              ),
            ),
          );
          final workflow = WorkflowStorage(package.database);
          workflow.compareAppend({}, [
            MapEntry('source-version:${f.id(12).value}', source.toWire()),
            MapEntry(
              'source:${source.contentDigest}',
              CanonicalString(sources.sourceText),
            ),
          ]);
          kernel.commit(input('evidence-fixture', rows));
          final head = kernel.journal.head(continuity);
          proposal = proposals.prepare(
            principal: writer.id,
            author: false,
            frame: Frame(
              universe: f.u,
              continuity: continuity,
              revision: head,
              context: f.ref(99),
              time: const TimelessFrameTime(),
              perspective: const AuthorPerspective(),
            ),
            base: canon(continuity, head),
            versions: {f.id(40): f.ver(40)},
            request: CreateProposalRequest(
              universe: const Selector('World'),
              contextId: proposals.contextId,
              operations: [
                DefineRuleOperation(
                  clientRef: f.id(40).value,
                  record: evidence.policy(
                    predicates: includeEvents ? [] : ['test:answer'],
                    reviewMethods: requiresReview
                        ? [EvidenceReviewMethod.humanReview]
                        : [],
                  ),
                ),
              ],
              submission: Submission.submitted,
              rationale: 'Scoped evidence policy',
              idempotencyKey: 'scoped-policy',
            ),
          );
          workflow.compareAppend({}, [
            MapEntry(proposal.key, proposal.toWire()),
          ]);
          final opened = await service.openContext(contextRequest());
          Future<CheckedValidation> validate() async {
            final report = await service.validateProposalRequest(
              ProposalValidationRequest(
                universe: const Selector('World'),
                contextId: opened.contextId,
                proposalReference: proposal.reference,
                checkScope: CheckScope.candidate,
              ),
            ) as EvaluatedValidation;
            return CheckedValidation.fromWire(
              workflow.get('validation:${report.execution.runId.value}')!,
            );
          }

          final initial = await validate();
          expect(initial.admissible, !requiresReview);
          if (requiresReview) {
            CanonicalValue body =
                (includeEvents
                        ? event_evidence.review(rows, includeEffect: true)
                        : reviews.review())
                    .envelope!
                    .body
                    .toWire();
            body = accounting.replace(body, [
              'proposal',
            ], proposal.reference.toWire());
            body = accounting.replace(body, [
              'base_frame',
            ], proposal.proposal.baseFrame.toWire());
            body = accounting.replace(body, [
              'assessor',
              'principal',
            ], CanonicalString(writer.id.value.replaceFirst('prf_', 'prn_')));
            await service.attachAssessment(
              proposal.reference,
              expectedGeneration: BigInt.zero,
              body: SourceAssessmentV1.fromWire(body),
              idempotencyKey: 'scoped-review',
            );
            expect((await validate()).admissible, isTrue);
          }
          final queuedStatus = await service.queueValidation(
            queued(),
            resolvedFrame: proposal.proposal.baseFrame,
            isValidationActive: (_) => false,
          );
          final task = (await service.prepareValidation(
            queuedStatus.operationId,
            isValidationActive: (_) => true,
          ))!;
          expect(task.selectedAssessment != null, requiresReview);
          final evaluated = await ValidationEvaluationWorker(task).result;
          expect(evaluated.admissible, isTrue);
          await service.finishValidation(
            queuedStatus.operationId,
            evaluated,
            isValidationActive: (_) => true,
          );
          final retained = CheckedValidation.fromWire(
            workflow.get('validation:${evaluated.validation.runId.value}')!,
          );
          await authorService().approve(
            proposal.reference,
            retained.validation.runId,
          );
          final receipt = await service.commit(
            publication(retained),
            isValidationActive: (_) => false,
          );
          expect(kernel.journal.head(continuity), receipt.revision);
          expect(kernel.identityExists(f.id(40)), isTrue);
          final researchContext = await service.openContext(contextRequest());
          final inline = await service.validateInlineRequest(
            InlineValidationRequest(
              universe: const Selector('World'),
              contextId: researchContext.contextId,
              operations: [
                ReviseDefinitionOperation(
                  record: f.ref(2),
                  expectedVersion: f.ver(2),
                  replacement: rows
                      .singleWhere((r) => r.identity.recordId == f.id(2))
                      .payload,
                ),
              ],
              checkScope: CheckScope.candidate,
            ),
          ) as EvaluatedValidation;
          expect(
            inline.execution.findings.any(
              (finding) =>
                  finding.ruleId == f.id(40) &&
                  finding.outcome == EvidenceOutcome.notEstablished,
            ),
            requiresReview,
          );
          expect(kernel.journal.head(continuity), receipt.revision);
        },
      );
    }
  }
  test('synchronous source check feeds exact author approval and reviewed publication', () async {
    final body = await submittedAssessment();
    await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'synchronous-assessment',
    );
    await retainedContext();
    final report = await service.validateProposalRequest(
      synchronousCheck(),
    ) as EvaluatedValidation;
    expect(report.finalBindingDigest, isNotNull);
    final completed = CheckedValidation.fromWire(
      WorkflowStorage(package.database)
          .get('validation:${report.execution.runId.value}')!,
    );
    await authorService().approve(
      proposal.reference,
      completed.validation.runId,
    );
    final request = publication(completed);
    final receipt = await service.commit(
      request,
      isValidationActive: (_) => false,
    );
    expect(kernel.identityExists(f.id(10)), isTrue);
    expect(kernel.journal.head(continuity), receipt.revision);
    final lookup = GetOperationKeyRequest(
      universe: const Selector('World'),
      universeId: f.u,
      operationKind: OperationKind.commit,
      idempotencyKey: request.idempotencyKey,
    );
    final recoveredLookup = await service.getOperationRequest(
      lookup,
      isValidationActive: (_) => false,
    );
    expect(recoveredLookup.status.state, OperationState.succeeded);
    expect(
      recoveredLookup.status.receipt!.toWire().toText(),
      receipt.toWire().toText(),
    );
    expect(recoveredLookup.delivery.complete, isTrue);
    await expectLater(
      service.getOperationRequest(
        GetOperationIdRequest(
          universe: const Selector('World'),
          universeId: f.u,
          operationId: receipt.operationId,
          cursor: 'untrusted',
        ),
        isValidationActive: (_) => false,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('native authoring journey submits checks approves and publishes without seeded proposals', () async {
    final opened = await service.openContext(contextRequest());
    final template = creation();
    final draft = await service.proposeRequest(
      CreateProposalRequest(
        universe: template.universe,
        universeId: f.u,
        contextId: opened.contextId,
        operations: template.operations,
        submission: template.submission,
        rationale: template.rationale,
        idempotencyKey: template.idempotencyKey,
      ),
      isValidationActive: (_) => false,
    );
    final submitted = await service.proposeRequest(
      SubmitProposalRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        proposalReference: reference(draft),
        idempotencyKey: 'journey-submit',
      ),
      isValidationActive: (_) => false,
    );
    proposal = StoredProposal.fromWire(
      WorkflowStorage(package.database).get(proposalKey(reference(submitted)))!,
    );
    final scheduler = NativeValidationScheduler();
    bool active(OperationId id) => scheduler.isActive(f.u, id);
    final queuedStatus = await service.queueValidationRequest(
      QueuedProposalValidationRequest(
        universe: const Selector('World'),
        universeId: f.u,
        contextId: opened.contextId,
        proposalReference: proposal.reference,
        checkScope: CheckScope.candidate,
        idempotencyKey: 'context-queued-check',
      ),
      isValidationActive: active,
    );
    await scheduler.schedule(service, queuedStatus.operationId);
    final status = await service.operationStatus(
      queuedStatus.operationId,
      isValidationActive: active,
    );
    expect(status.state, OperationState.succeeded);
    final report = status.validation as EvaluatedValidation;
    expect(report.finalBindingDigest, isNotNull);
    final completed = CheckedValidation.fromWire(
      WorkflowStorage(package.database)
          .get('validation:${report.execution.runId.value}')!,
    );
    await authorService().approve(
      proposal.reference,
      completed.validation.runId,
    );
    final receipt = await service.commit(
      publication(completed),
      isValidationActive: active,
    );
    expect(kernel.identityExists(f.id(20)), isTrue);
    expect(kernel.journal.head(continuity), receipt.revision);
    await scheduler.close();
  });

  test('reviewed publication commits canon once and recovers the exact receipt across reopen', () async {
    final completed = await completedSubmitted();
    await authorService().approve(
      proposal.reference,
      completed.validation.runId,
    );
    final request = publication(completed);
    final receipt = await service.commit(
      request,
      isValidationActive: (_) => false,
    );
    expect(kernel.identityExists(f.id(10)), isTrue);
    expect(kernel.journal.head(continuity), receipt.revision);
    expect(
      (await service.commit(
        request,
        isValidationActive: (_) => false,
      )).toWire().toText(),
      receipt.toWire().toText(),
    );
    final recovered = await service.operation(
      receipt.operationId,
      isValidationActive: (_) => false,
    );
    final changed = CommitRequest(
      universe: request.universe,
      universeId: request.universeId,
      proposalReference: request.proposalReference,
      expectedBaseRevision: request.expectedBaseRevision,
      validationRun: ValidationRunId.generate(),
      idempotencyKey: request.idempotencyKey,
    );
    await expectLater(
      service.commit(changed, isValidationActive: (_) => false),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
    expect(recovered.status.state, OperationState.succeeded);
    expect(
      recovered.status.receipt!.toWire().toText(),
      receipt.toWire().toText(),
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    expect(
      (await service.commit(
        request,
        isValidationActive: (_) => false,
      )).toWire().toText(),
      receipt.toWire().toText(),
    );
    expect(kernel.journal.head(continuity), receipt.revision);
    await expectLater(
      service.commit(
        publication(completed, key: 'different-publish'),
        isValidationActive: (_) => false,
      ),
      stale,
    );
  });

  test('cancelled retained publication cannot resume into canon', () async {
    final completed = await completedSubmitted();
    await authorService().approve(
      proposal.reference,
      completed.validation.runId,
    );
    final request = publication(completed);
    final commitInput = await proposalCommitInput(
      stored: proposal,
      universe: f.u,
      principal: writer.id,
      idempotencyKey: request.idempotencyKey,
      readCanon: canon,
    );
    final id = OperationId.generate();
    final retained = StoredOperation(
      owner: writer.id,
      digest: canonicalDigest(request.toArgs()),
      input: commitInput,
      footprint: proposal.footprint,
      status: OperationStatus(
        operationId: id,
        kind: OperationKind.commit,
        state: OperationState.committing,
        proposal: proposal.proposal,
        cancellationRequested: false,
      ),
    );
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry(
        operationRequestKey(writer.id, 'commit', request.idempotencyKey),
        retained.toWire(),
      ),
      MapEntry('operation:${id.value}', retained.toWire()),
    ]);
    await service.cancelOperation(
      cancellation(id),
      isValidationActive: (_) => false,
      signalCancellation: (_) {},
    );
    await expectLater(
      service.commit(request, isValidationActive: (_) => false),
      throwsA(isA<PolicyDeniedError>()),
    );
    expect(kernel.identityExists(f.id(10)), isFalse);
    expect(kernel.journal.receipt(commitInput), isNull);
    expect(
      (await service.operation(
        id,
        isValidationActive: (_) => false,
      )).status.state,
      OperationState.cancelled,
    );
  });

  test(
    'publication requires exact approval and unchanged selected evidence',
    () async {
      final completed = await completedSubmitted();
      final head = kernel.journal.head(continuity);
      await expectLater(
        service.commit(
          publication(completed),
          isValidationActive: (_) => false,
        ),
        throwsA(isA<ApprovalRequiredError>()),
      );
      expect(
        WorkflowStorage(package.database)
            .keys('request:${writer.id.value}:commit:'),
        isEmpty,
      );
      await authorService().approve(
        proposal.reference,
        completed.validation.runId,
      );
      await service.selectAssessment(
        proposal.reference,
        expectedGeneration: BigInt.one,
        selected: null,
        idempotencyKey: 'clear-before-publish',
      );
      await expectLater(
        service.commit(
          publication(completed),
          isValidationActive: (_) => false,
        ),
        stale,
      );
      expect(kernel.identityExists(f.id(10)), isFalse);
      expect(kernel.journal.head(continuity), head);
    },
  );

  test('delegated publication observes explicit shared-work limits', () async {
    kernel.commit(
      input('delegation-base', [frames.fixture().first, f.row(2, f.entity())]),
    );
    final head = kernel.journal.head(continuity);
    proposal = proposals.prepare(
      principal: writer.id,
      request: CreateProposalRequest(
        universe: const Selector('World'),
        contextId: proposals.contextId,
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
      frame: Frame(
        universe: f.u,
        continuity: continuity,
        revision: head,
        context: f.ref(99),
        time: const TimelessFrameTime(),
        perspective: const AuthorPerspective(),
      ),
      base: canon(continuity, head),
    );
    WorkflowStorage(package.database)
        .compareAppend({}, [MapEntry(proposal.key, proposal.toWire())]);
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final task = (await service.prepareValidation(
      status.operationId,
      isValidationActive: (_) => true,
    ))!;
    final checked = task.evaluate();
    await service.finishValidation(
      status.operationId,
      checked,
      isValidationActive: (_) => true,
    );
    final completed = CheckedValidation.fromWire(
      WorkflowStorage(package.database)
          .get('validation:${checked.validation.runId.value}')!,
    );
    Future<void> delegation(bool shared) => authority.coordinate(
      author,
      () => authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: null,
          propose: true,
          edit: true,
          protected: true,
          limits: GrantLimits(
            entities: [f.id(2)],
            predicates: [f.id(1)],
            continuities: [continuity],
            expiresAt: BigInt.from(
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            ),
            delegatedCommit: true,
            allowShared: shared,
          ),
        ),
      ),
    );
    await delegation(false);
    await expectLater(
      service.commit(publication(completed), isValidationActive: (_) => false),
      throwsA(isA<ApprovalRequiredError>()),
    );
    expect(kernel.identityExists(f.id(10)), isFalse);
    await delegation(true);
    final receipt = await service.commit(
      publication(completed),
      isValidationActive: (_) => false,
    );
    expect(kernel.journal.head(continuity), receipt.revision);
    expect(kernel.identityExists(f.id(10)), isTrue);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test('draft proposals cannot receive author approval', () async {
    await service.persist(proposal.reference, checked);
    await expectLater(
      authorService().approve(proposal.reference, checked.validation.runId),
      stale,
    );
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test(
    'blocked and incomplete retained evidence cannot authorize approval',
    () async {
      final completed = await completedSubmitted();
      for (final blocked in [true, false]) {
        final run = ValidationRunId.generate();
        var wire = accounting.replace(completed.toWire(), [
          'validation',
          'run_id',
        ], CanonicalString(run.value));
        wire = accounting.replace(wire, [
          'admissible',
        ], CanonicalBool(!blocked));
        wire = accounting.replace(wire, ['report'], const CanonicalNull());
        final retained = CheckedValidation.fromWire(wire);
        await service.persist(proposal.reference, retained);
        await expectLater(
          authorService().approve(proposal.reference, run),
          blocked ? throwsA(isA<PolicyDeniedError>()) : stale,
        );
      }
      expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    },
  );

  test('advanced canon blocks exact author approval', () async {
    final completed = await completedSubmitted();
    kernel.commit(input('advance-before-approval', [f.row(77, f.entity())]));
    await expectLater(
      authorService().approve(proposal.reference, completed.validation.runId),
      stale,
    );
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test('source-assessed completion retains the submitted inventory and final binding', () async {
    final body = await submittedAssessment();
    await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'attach-completed',
    );
    final status = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final task = (await service.prepareValidation(
      status.operationId,
      isValidationActive: (_) => true,
    ))!;
    final result = task.evaluate();
    await service.finishValidation(
      status.operationId,
      result,
      isValidationActive: (_) => true,
    );
    final completed = await service.operationStatus(
      status.operationId,
      isValidationActive: (_) => false,
    );
    expect(completed.state, OperationState.succeeded);
    final report = completed.validation as EvaluatedValidation;
    expect(
      report.submittedInput.toWire().toText(),
      task.capture!.submittedInput.toWire().toText(),
    );
    expect(report.assessment, isA<BoundAssessment>());
    expect(report.finalBindingDigest, isNotNull);
    expect(report.execution.operationId, status.operationId);
    expect(kernel.identityExists(f.id(10)), isFalse);
  });

  test('attachment, clear, reselection and historical retry retain exact immutable evidence', () async {
    final body = await submittedAssessment();
    final first = await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'attach',
    );
    expect(first.generation, BigInt.one);
    final reference = first.selected!;
    final envelopeKey = 'assessment:${reference.assessmentId.value}';
    final original = WorkflowStorage(package.database)
        .get(envelopeKey)!
        .toText();
    final captured = await service.capture(proposal.reference);
    expect(captured.submittedInput, isA<SourceAssessedCandidateInput>());
    final queue = await service.queueValidation(
      queued(),
      resolvedFrame: proposal.proposal.baseFrame,
      isValidationActive: (_) => false,
    );
    final pending = queue.validation as EvaluatedValidation;
    expect(pending.submittedInput, isA<SourceAssessedCandidateInput>());
    expect(
      (pending.assessment as BoundAssessment).selectionGeneration,
      BigInt.one,
    );
    expect(pending.finalBindingDigest, isNull);
    final task = (await service.prepareValidation(
      queue.operationId,
      isValidationActive: (_) => true,
    ))!;
    expect(task.capture!.submittedInput, isA<SourceAssessedCandidateInput>());
    expect(task.capture!.selection.generation, BigInt.one);
    expect(task.evaluate().capture, same(task.capture));
    final clear = await service.selectAssessment(
      proposal.reference,
      expectedGeneration: BigInt.one,
      selected: null,
      idempotencyKey: 'clear',
    );
    expect(clear.generation, BigInt.two);
    expect(clear.selected, isNull);
    await expectLater(
      service.prepareValidation(
        queue.operationId,
        isValidationActive: (_) => true,
      ),
      stale,
    );
    await service.finishValidation(
      queue.operationId,
      task.evaluate(),
      isValidationActive: (_) => true,
    );
    expect(
      (await service.operation(
        queue.operationId,
        isValidationActive: (_) => false,
      )).status.state,
      OperationState.failed,
    );
    expect(WorkflowStorage(package.database).keys('validation:'), isEmpty);
    final retry = await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'attach',
    );
    expect(retry.toWire().toText(), first.toWire().toText());
    expect(
      (await service.capture(proposal.reference)).selection.generation,
      BigInt.two,
    );
    final selected = await service.selectAssessment(
      proposal.reference,
      expectedGeneration: BigInt.two,
      selected: reference,
      idempotencyKey: 'select',
    );
    expect(selected.generation, BigInt.from(3));
    expect(selected.selected!.toWire().toText(), reference.toWire().toText());
    await expectLater(
      service.selectAssessment(
        proposal.reference,
        expectedGeneration: BigInt.from(3),
        selected: reference,
        idempotencyKey: 'unchanged',
      ),
      f.fails('selection is unchanged', field: 'assessment'),
    );
    await expectLater(
      service.attachAssessment(
        proposal.reference,
        expectedGeneration: BigInt.one,
        body: body,
        idempotencyKey: 'attach',
      ),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
    expect(
      WorkflowStorage(package.database).get(envelopeKey)!.toText(),
      original,
    );
    expect(
      WorkflowStorage(package.database).keys('assessment-receipt:').length,
      3,
    );
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final reopenedRetry = await service.attachAssessment(
      proposal.reference,
      expectedGeneration: BigInt.zero,
      body: body,
      idempotencyKey: 'attach',
    );
    expect(reopenedRetry.toWire().toText(), first.toWire().toText());
    expect(
      WorkflowStorage(package.database).get(envelopeKey)!.toText(),
      original,
    );
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    expect(package.database.autocommit, isTrue);
  });

  test(
    'wrong assessor, generation and invalid key retain no partial attachment',
    () async {
      final body = await submittedAssessment();
      final wrong = SourceAssessmentV1.fromWire(
        accounting.replace(body.toWire(), [
          'assessor',
          'principal',
        ], CanonicalString(author.id.value.replaceFirst('prf_', 'prn_'))),
      );
      await expectLater(
        service.attachAssessment(
          proposal.reference,
          expectedGeneration: BigInt.zero,
          body: wrong,
          idempotencyKey: 'wrong',
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        service.attachAssessment(
          proposal.reference,
          expectedGeneration: BigInt.one,
          body: body,
          idempotencyKey: 'stale',
        ),
        stale,
      );
      await expectLater(
        service.attachAssessment(
          proposal.reference,
          expectedGeneration: BigInt.zero,
          body: body,
          idempotencyKey: '',
        ),
        f.fails('invalid idempotency key', field: 'assessment'),
      );
      final workflow = WorkflowStorage(package.database);
      expect(workflow.keys('assessment:'), isEmpty);
      expect(workflow.keys('assessment-receipt:'), isEmpty);
      expect(workflow.keys('assessment-selection:'), isEmpty);
      expect(package.database.autocommit, isTrue);
    },
  );

  test(
    'fresh attachment requires submitted current proposal and pinned head',
    () async {
      final body = await submittedAssessment();
      kernel.commit(input('advance-assessment-head', [f.row(40, f.entity())]));
      await expectLater(
        service.attachAssessment(
          proposal.reference,
          expectedGeneration: BigInt.zero,
          body: body,
          idempotencyKey: 'advanced',
        ),
        stale,
      );
      final head = kernel.journal.head(continuity);
      final draft = proposals.prepare(
        principal: writer.id,
        frame: Frame(
          universe: f.u,
          continuity: continuity,
          revision: head,
          context: f.ref(99),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        ),
        base: canon(continuity, head),
      );
      WorkflowStorage(package.database)
          .compareAppend({}, [MapEntry(draft.key, draft.toWire())]);
      var wire = accounting.replace(body.toWire(), [
        'proposal',
      ], draft.reference.toWire());
      wire = accounting.replace(wire, [
        'base_frame',
      ], draft.proposal.baseFrame.toWire());
      await expectLater(
        service.attachAssessment(
          draft.reference,
          expectedGeneration: BigInt.zero,
          body: SourceAssessmentV1.fromWire(wire),
          idempotencyKey: 'draft',
        ),
        stale,
      );
      expect(
        WorkflowStorage(package.database).keys('assessment-receipt:'),
        isEmpty,
      );
      expect(package.database.autocommit, isTrue);
    },
  );

  test('kernel-checked capture is retained atomically and survives owned package reopen', () async {
    expect(checked.admissible, isTrue);
    final head = kernel.journal.head(continuity);
    await service.persist(proposal.reference, checked);
    await service.persist(proposal.reference, checked);
    expect(kernel.journal.head(continuity), head);
    expect(kernel.identityExists(proposal.changes.single.recordId), isFalse);
    final id = OperationId.generate();
    final completed = StoredOperation(
      owner: writer.id,
      digest: 'c' * 64,
      input: null,
      footprint: proposal.footprint,
      validationCapture: checked.capture,
      status: OperationStatus(
        operationId: id,
        kind: OperationKind.validate,
        state: OperationState.succeeded,
        proposal: proposal.proposal,
        validation: checked.validation,
        cancellationRequested: false,
      ),
    );
    WorkflowStorage(package.database).compareAppend({}, [
      MapEntry('operation:${id.value}', completed.toWire()),
    ]);
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    final retained = CheckedValidation.fromWire(
      WorkflowStorage(package.database).get(key())!,
    );
    expect(retained.toWire().toText(), checked.toWire().toText());
    service = SqliteValidationWorkflow(
      package: package,
      authority: authority,
      principal: writer,
    );
    final status = await service.operationStatus(
      id,
      isValidationActive: (_) => false,
    );
    expect(status.state, OperationState.succeeded);
    expect(
      status.validation!.toWire().toText(),
      checked.report!.toWire().toText(),
    );
    expect(package.database.autocommit, isTrue);
    expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
  });

  test(
    'identical regrant invalidates capture and leaves no partial retention',
    () async {
      await authority.coordinate(
        author,
        () => authority.grant(author, grant()),
      );
      await expectLater(service.persist(proposal.reference, checked), stale);
      expect(WorkflowStorage(package.database).get(key()), isNull);
      expect(package.database.autocommit, isTrue);
    },
  );

  test(
    'competing selection and advanced head invalidate captured results',
    () async {
      final prefix = checked.capture!.comparisons().keys.first;
      WorkflowStorage(package.database).compareAppend({}, [
        MapEntry(
          '${prefix}00000000000000000001',
          AssessmentSelection(
            proposal: proposal.reference,
            generation: BigInt.one,
            selected: null,
          ).toWire(),
        ),
      ]);
      await expectLater(service.persist(proposal.reference, checked), stale);
      expect(WorkflowStorage(package.database).get(key()), isNull);
      final fresh = await service.capture(proposal.reference);
      final next = CheckedValidation(
        proposalDigest: checked.proposalDigest,
        validation: checked.validation,
        admissible: checked.admissible,
        capture: fresh,
      );
      kernel.commit(input('advance', [f.row(40, f.entity())]));
      await expectLater(service.persist(proposal.reference, next), stale);
      expect(WorkflowStorage(package.database).get(key()), isNull);
      expect(package.database.autocommit, isTrue);
    },
  );

  test(
    'revoked authentication is rejected before retaining a completed check',
    () async {
      await authority.coordinate(
        author,
        () => authority.revoke(author, writer.id),
      );
      await expectLater(
        service.persist(proposal.reference, checked),
        throwsA(isA<InstallationException>()),
      );
      expect(WorkflowStorage(package.database).get(key()), isNull);
      expect(package.database.autocommit, isTrue);
    },
  );
}
