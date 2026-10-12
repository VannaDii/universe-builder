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
import 'source_verification_test.dart' as sources;
import 'instance_initialization_test.dart' as initialization;
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

  SqliteValidationWorkflow authorService() => SqliteValidationWorkflow(
    package: package,
    authority: authority,
    principal: author,
  );

  test('author approval binds the exact retained assessment and checked digest across reopen', () async {
    final completed = await completedSubmitted();
    expect(completed.admissible, isTrue);
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
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    kernel = SqliteKernel(package.database, f.u);
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
    final receipt = await service.commit(
      publication(completed),
      isValidationActive: (_) => false,
    );
    expect(kernel.identityExists(f.id(10)), isTrue);
    expect(kernel.journal.head(continuity), receipt.revision);
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
