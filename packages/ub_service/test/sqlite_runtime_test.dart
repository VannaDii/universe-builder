@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/sqlite_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'proposal_authorization_test.dart' as permissions;
import 'rule_checks_test.dart' as frames;
import 'structural_checks_test.dart' as structure;
import 'writing_units_test.dart' as units;
import 'source_verification_test.dart' as sources;
import 'assessment_validation_test.dart' as assessments;
import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;

void main() {
  late Directory root;
  late SqliteInstallationStore installation;
  late InstallationAuthority authority;
  late InstallationPrincipal author, writer;
  late NativeSqliteRuntime runtime;
  late StoredProposal draft;
  late String path;
  EngineHello hello(ProfileId profile, {String version = protocolVersion}) =>
      EngineHello(
        protocolVersion: version,
        profileId: profile,
        credential: Credential(
          ProfileCredentialStore.read(root: root.path, profile: profile),
        ),
        clientName: 'Disposable runtime client',
      );
  const stage = StageSourceEngineRequest(
    universe: Selector('World'),
    label: 'Session notes',
    text: 'Exact author bytes: é😀',
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('universe-builder-runtime-');
    installation = SqliteInstallationStore.create(root.path);
    authority = InstallationAuthority(installation);
    author = authority.authenticateHello(hello(authority.initializeAuthor()));
    writer = authority.authenticateHello(hello(authority.enroll(author)));
    path = '${root.path}/packages/world.sqlite';
    final package = OwnedSqliteDatabase.create(path);
    try {
      final kernel = SqliteKernel(package.database, f.u);
      final continuity = frames.frame().continuity;
      package.database.execute('BEGIN IMMEDIATE');
      kernel.journal.initialize(
        'Disposable runtime world',
        continuity,
        PrincipalId.generate(),
      );
      package.database.execute('COMMIT');
      final context = structure.context(99);
      kernel.commit(
        CommitInput(
          universe: f.u,
          continuity: continuity,
          expectedHead: kernel.journal.head(continuity),
          principal: PrincipalId.generate(),
          decision: 'Already admitted fixture',
          reason: 'Runtime fixture',
          idempotencyKey: 'context',
          changes: [
            Assignment(
              recordId: context.identity.recordId,
              next: StoredVersion(
                versionId: context.recordVersionId,
                identity: context.identity,
                payload: context.payload.toWire(),
                digest: context.payloadDigest,
              ),
            ),
          ],
        ),
      );
      draft = proposals.prepare(
        author: true,
        principal: author.id,
        frame: Frame(
          universe: f.u,
          continuity: continuity,
          revision: kernel.journal.head(continuity),
          context: f.ref(99),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        ),
        base: [context],
        request: proposals.create(
          operations: [
            DefineUnitOperation(
              clientRef: f.id(10).value,
              record: units.unit(),
            ),
          ],
        ),
      );
      WorkflowStorage(package.database)
          .compareAppend({}, [MapEntry(draft.key, draft.toWire())]);
    } finally {
      package.close();
    }
    authority.registerUniverse(author, name: 'World', path: path);
    runtime = NativeSqliteRuntime(authority: authority);
  });
  tearDown(() async {
    await runtime.close();
    installation.close();
    root.deleteSync(recursive: true);
  });

  Future<Envelope<CanonicalValue>> tool(
    NativeSqliteConnection connection,
    Request request,
  ) async {
    final decoded = EngineRequest.decode(
      ToolEngineRequest(request: request).toWire().toBytes(),
    );
    return Envelope.fromWire(await connection.execute(decoded), (v) => v);
  }

  test('public discovery and context envelopes retain exact frames and current aliases', () async {
    final connection = runtime.connect(hello(author.id));
    final summary = await tool(
      connection,
      DescribeSummaryRequest(
        universe: const Selector('World'),
        universeId: f.u,
      ),
    );
    expect(summary.contractVersion, protocolVersion);
    expect(summary.requestId, BigInt.zero);
    expect(summary.universeId, f.u);
    expect(summary.aliasMatched, isFalse);
    expect(summary.authorizationScope, 'universe grant');
    expect(summary.delivery.complete, isTrue);
    expect(summary.delivery.cursor, isNull);
    expect(summary.frame, isNull);
    expect(summary.worldFocus, isNull);
    final discovered = Description.fromWire(summary.result);
    final continuity = discovered.continuities.single;
    expect(continuity.id, draft.proposal.baseFrame.continuity);
    final openedEnvelope = await tool(
      connection,
      OpenContextRequest(
        universe: const Selector('World'),
        universeId: f.u,
        continuityId: continuity.id,
        revision: const HeadRevisionSelector(),
        representedContext: ContextIdSelector(f.id(99)),
        temporalQuery: const TimelessFrameTime(),
        temporalSystems: [],
        perspective: const AuthorPerspective(),
      ),
    );
    final opened = OpenedContext.fromWire(openedEnvelope.result);
    expect(
      openedEnvelope.frame!.toWire().toText(),
      opened.frame.toWire().toText(),
    );
    expect(opened.frame.revision, continuity.revisionId);
    authority.renameUniverse(author, id: f.u, name: 'Campaign');
    final worlds = await tool(
      connection,
      DescribeWorldsRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
      ),
    );
    expect(worlds.universe.value, 'Campaign');
    expect(worlds.aliasMatched, isTrue);
    expect(worlds.frame!.toWire().toText(), opened.frame.toWire().toText());
    expect(Description.fromWire(worlds.result).worlds, isEmpty);
    final capabilities = await tool(
      connection,
      DescribeCapabilitiesRequest(universe: const Selector('Campaign')),
    );
    expect(capabilities.aliasMatched, isFalse);
    expect(Description.fromWire(capabilities.result).capabilities, isNotEmpty);
    final definitions = await tool(
      connection,
      DescribeDefinitionsRequest(
        universe: const Selector('Campaign'),
        contextId: opened.contextId,
      ),
    );
    expect(definitions.frame!.revision, continuity.revisionId);
    await expectLater(
      tool(
        connection,
        DescribeSummaryRequest(
          universe: const Selector('Campaign'),
          universeId: UniverseId.generate(),
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('public requests use current grants and cannot reuse another profile context', () async {
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: null,
        propose: false,
        edit: false,
        protected: false,
      ),
    );
    final authorConnection = runtime.connect(hello(author.id));
    final writerConnection = runtime.connect(hello(writer.id));
    OpenContextRequest open() => OpenContextRequest(
      universe: const Selector('World'),
      continuityId: draft.proposal.baseFrame.continuity,
      revision: const HeadRevisionSelector(),
      representedContext: ContextIdSelector(f.id(99)),
      temporalQuery: const TimelessFrameTime(),
      temporalSystems: [],
      perspective: const AuthorPerspective(),
    );
    final opened = OpenedContext.fromWire(
      (await tool(writerConnection, open())).result,
    );
    final describe = DescribeWorldsRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
    );
    await tool(writerConnection, describe);
    await expectLater(
      tool(authorConnection, describe),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    authority.withdrawGrant(author, profile: writer.id, universe: f.u);
    await expectLater(
      tool(writerConnection, describe),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      tool(
        writerConnection,
        DescribeSummaryRequest(universe: const Selector('World')),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await tool(
      authorConnection,
      DescribeSummaryRequest(universe: const Selector('World')),
    );
    authority.revoke(author, writer.id);
    await expectLater(
      tool(writerConnection, open()),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  void seedReadRows(List<RecordVersion> rows) {
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      final kernel = SqliteKernel(package.database, f.u);
      kernel.commit(
        CommitInput(
          universe: f.u,
          continuity: draft.proposal.baseFrame.continuity,
          expectedHead: kernel.journal.head(
            draft.proposal.baseFrame.continuity,
          ),
          principal: PrincipalId.generate(),
          decision: 'Already admitted read fixture',
          reason: 'Runtime read fixture',
          idempotencyKey: 'runtime-reads',
          changes: rows.map(
            (row) => Assignment(
              recordId: row.identity.recordId,
              next: StoredVersion(
                versionId: row.recordVersionId,
                identity: row.identity,
                payload: row.payload.toWire(),
                digest: row.payloadDigest,
              ),
            ),
          ),
        ),
      );
    } finally {
      package.close();
    }
  }

  Future<OpenedContext> readContext(NativeSqliteConnection connection) async =>
      OpenedContext.fromWire(
        (await tool(
          connection,
          OpenContextRequest(
            universe: const Selector('World'),
            continuityId: draft.proposal.baseFrame.continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(f.id(99)),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
        )).result,
      );

  test('public paged reads resume across runtime restart with exact cursor binding', () async {
    final rows = [
      for (var n = 20; n < 24; n++)
        f.row(n, permissions.entity(labels: {'en': 'Alpha $n'})),
    ];
    seedReadRows(rows);
    var connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    SearchRequest search({String? cursor, String query = 'Alpha'}) =>
        SearchRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          query: query,
          typedFilters: Filters(recordKinds: [RecordKind.entity]),
          limit: 1,
          cursor: cursor,
        );
    final first = await tool(connection, search());
    expect(first.delivery.complete, isFalse);
    expect(SearchResults.fromWire(first.result).hits.single.recordId, f.id(20));
    final budget =
        ContextBrief(
          records: [rows.first],
          requiredDependencies: [],
          coverage: Coverage.partial,
        ).toWire().toBytes().length +
        30;
    GetContextRequest brief({String? cursor, String purpose = 'Research'}) =>
        GetContextRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          focusIds: rows.map((r) => r.identity.recordId),
          purpose: purpose,
          byteBudget: budget,
          cursor: cursor,
        );
    final firstBrief = await tool(connection, brief());
    expect(firstBrief.delivery.complete, isFalse);
    expect(ContextBrief.fromWire(firstBrief.result).coverage, Coverage.partial);
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    await expectLater(
      tool(connection, search(cursor: first.delivery.cursor, query: 'Changed')),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      tool(
        connection,
        brief(cursor: firstBrief.delivery.cursor, purpose: 'Changed'),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final collected = [
      SearchResults.fromWire(first.result).hits.single.recordId,
    ];
    var cursor = first.delivery.cursor;
    while (cursor != null) {
      final page = await tool(connection, search(cursor: cursor));
      expect(page.frame!.toWire().toText(), opened.frame.toWire().toText());
      collected.addAll(
        SearchResults.fromWire(page.result).hits.map((h) => h.recordId),
      );
      cursor = page.delivery.cursor;
      expect(page.delivery.complete, cursor == null);
    }
    expect(collected, rows.map((r) => r.identity.recordId));
    final briefRows = [...ContextBrief.fromWire(firstBrief.result).records];
    cursor = firstBrief.delivery.cursor;
    while (cursor != null) {
      final page = await tool(connection, brief(cursor: cursor));
      expect(page.frame!.revision, opened.frame.revision);
      briefRows.addAll(ContextBrief.fromWire(page.result).records);
      cursor = page.delivery.cursor;
      expect(page.delivery.complete, cursor == null);
    }
    expect(
      briefRows.map((r) => r.identity.recordId),
      rows.map((r) => r.identity.recordId),
    );
  });

  test('public record state and plain reads preserve a pinned frame after head advances', () async {
    seedReadRows([
      f.row(20, permissions.entity(labels: {'en': 'Alpha'})),
    ]);
    var connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      final kernel = SqliteKernel(package.database, f.u);
      kernel.commit(
        CommitInput(
          universe: f.u,
          continuity: opened.frame.continuity,
          expectedHead: opened.frame.revision,
          principal: PrincipalId.generate(),
          decision: 'Already admitted later read fixture',
          reason: 'Advance fixture head',
          idempotencyKey: 'later-read',
          changes: [
            Assignment(
              recordId: f.id(21),
              next: StoredVersion(
                versionId: f.ver(21),
                identity: f.row(21, f.entity()).identity,
                payload: f.entity().toWire(),
                digest: f.row(21, f.entity()).payloadDigest,
              ),
            ),
          ],
        ),
      );
    } finally {
      package.close();
    }
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    final requests = <Request>[
      GetRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        recordIds: [f.id(20)],
        fieldGroups: [
          FieldGroup.payload,
          FieldGroup.summary,
          FieldGroup.history,
        ],
      ),
      GetStateRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        entityIds: [f.id(20)],
        predicateFilters: [],
      ),
      ReadFactsRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        objectNames: ['Alpha'],
      ),
      ReadContractsRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
      ),
    ];
    for (final request in requests) {
      final response = await tool(connection, request);
      expect(response.frame!.toWire().toText(), opened.frame.toWire().toText());
      expect(response.delivery.complete, isTrue);
      expect(response.delivery.cursor, isNull);
      if (request is GetRequest) {
        expect(
          Records.fromWire(response.result).records.single.identity.recordId,
          f.id(20),
        );
        expect(Records.fromWire(response.result).history, isNotEmpty);
      }
      if (request is GetStateRequest) State.fromWire(response.result);
    }
    await expectLater(
      tool(
        connection,
        GetRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          recordIds: [f.id(21)],
          fieldGroups: [FieldGroup.payload],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('public world reads retain effective grant and focus without disclosing hidden records', () async {
    seedReadRows([
      f.row(50, WorldRecord(selector: 'Campaign', aliases: ['Play'])),
      f.row(51, WorldRecord(selector: 'Private')),
      f.row(
        20,
        permissions.entity(worlds: [50], labels: {'en': 'Alpha visible'}),
      ),
      f.row(
        21,
        permissions.entity(worlds: [51], labels: {'en': 'Alpha hidden'}),
      ),
    ]);
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: [permissions.world(50)],
        propose: false,
        edit: false,
        protected: false,
      ),
    );
    final connection = runtime.connect(hello(writer.id));
    final opened = await readContext(connection);
    final requests = <Request>[
      GetRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        world: const Selector('Play'),
        worldId: permissions.world(50),
        recordIds: [f.id(20)],
        fieldGroups: [FieldGroup.payload],
      ),
      SearchRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        world: const Selector('Play'),
        query: 'Alpha',
        typedFilters: Filters(recordKinds: [RecordKind.entity]),
        limit: 10,
      ),
      GetStateRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        world: const Selector('Play'),
        entityIds: [f.id(20)],
        predicateFilters: [],
      ),
      GetContextRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        world: const Selector('Play'),
        focusIds: [f.id(20)],
        purpose: 'Research',
        byteBudget: 65536,
      ),
      ReadFactsRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        world: 'Play',
        objectNames: ['Alpha visible'],
      ),
    ];
    for (final request in requests) {
      final response = await tool(connection, request);
      expect(response.authorizationScope, 'world-scoped grant');
      expect(response.worldFocus, permissions.world(50));
      expect(response.frame!.revision, opened.frame.revision);
      if (request is SearchRequest) {
        expect(
          SearchResults.fromWire(response.result).hits.map((h) => h.recordId),
          [f.id(20)],
        );
      }
    }
    await expectLater(
      tool(
        connection,
        GetRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          recordIds: [f.id(21)],
          fieldGroups: [FieldGroup.payload, FieldGroup.history],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      tool(
        connection,
        GetRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          world: const Selector('Private'),
          recordIds: [f.id(20)],
          fieldGroups: [FieldGroup.payload],
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    authority.withdrawGrant(author, profile: writer.id, universe: f.u);
    for (final request in requests) {
      await expectLater(
        tool(connection, request),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    }
  });

  test('public proposals validate require exact approval and recover publication receipts', () async {
    var connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    final operations = [
      DefineUnitOperation(clientRef: f.id(10).value, record: units.unit()),
    ];
    final inline = await tool(
      connection,
      InlineValidationRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        operations: operations,
        checkScope: CheckScope.candidate,
      ),
    );
    expect(ValidationV3.fromWire(inline.result), isA<EvaluatedValidation>());
    expect(inline.frame!.toWire().toText(), opened.frame.toWire().toText());
    final create = CreateProposalRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
      operations: operations,
      submission: Submission.draft,
      rationale: 'Explicit unit review',
      idempotencyKey: 'public-create',
    );
    final created = await tool(connection, create);
    final proposal = Proposal.fromWire(created.result);
    expect(proposal.canonical, isFalse);
    expect(
      (await tool(connection, create)).toWire((v) => v).toText(),
      created.toWire((v) => v).toText(),
    );
    ProposalRef reference(Proposal p) => ProposalRef(
      proposalId: p.proposalId,
      version: p.version,
      digest: p.digest,
    );
    final revised = Proposal.fromWire(
      (await tool(
        connection,
        ReviseProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: reference(proposal),
          operations: operations,
          submission: Submission.draft,
          rationale: 'Reviewed unit definition',
          idempotencyKey: 'public-revise',
        ),
      )).result,
    );
    expect(revised.version, proposal.version + BigInt.one);
    final submitted = Proposal.fromWire(
      (await tool(
        connection,
        SubmitProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: reference(revised),
          idempotencyKey: 'public-submit',
        ),
      )).result,
    );
    expect(submitted.submission, Submission.submitted);
    final ref = reference(submitted);
    final validation = await tool(
      connection,
      ProposalValidationRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        proposalReference: ref,
        checkScope: CheckScope.candidate,
      ),
    );
    final checked =
        ValidationV3.fromWire(validation.result) as EvaluatedValidation;
    final impact = await tool(
      connection,
      ProposalImpactRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        proposalReference: ref,
        scope: CheckScope.universe,
        byteBudget: 65536,
      ),
    );
    expect(Impact.fromWire(impact.result).records, contains(f.id(10)));
    final commit = CommitRequest(
      universe: const Selector('World'),
      proposalReference: ref,
      expectedBaseRevision: opened.frame.revision,
      validationRun: checked.execution.runId,
      idempotencyKey: 'public-publish',
    );
    await expectLater(
      tool(connection, commit),
      throwsA(isA<ApprovalRequiredError>()),
    );
    await connection.execute(
      ApproveEngineRequest(
        universe: const Selector('World'),
        proposalReference: ref,
        validationRun: checked.execution.runId,
      ),
    );
    final published = await tool(connection, commit);
    final receipt = CommitReceipt.fromWire(published.result);
    expect(receipt.revision, isNot(opened.frame.revision));
    expect(published.frame!.toWire().toText(), opened.frame.toWire().toText());
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    final recovered = await tool(connection, commit);
    expect(
      recovered.toWire((v) => v).toText(),
      published.toWire((v) => v).toText(),
    );
    final historical = await tool(
      connection,
      GetProposalRequest(
        universe: const Selector('World'),
        proposalId: submitted.proposalId,
        version: submitted.version,
      ),
    );
    expect(historical.frame!.revision, opened.frame.revision);
    expect(
      (ProposalViewResult.fromWire(
        historical.result,
      ) as FrozenProposalView).proposal.digest,
      submitted.digest,
    );
    await expectLater(
      tool(
        connection,
        CommitRequest(
          universe: const Selector('World'),
          proposalReference: ref,
          expectedBaseRevision: opened.frame.revision,
          validationRun: ValidationRunId.generate(),
          idempotencyKey: 'public-publish',
        ),
      ),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
  });

  test('public ordinary checks and withdrawal retain provisional author state without publication', () async {
    final connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    final request = CheckChangesRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
      units: [units.declaration(name: 'league', symbol: 'lg', introduce: true)],
    );
    final response = await tool(connection, request);
    final check = WritingCheck.fromWire(response.result);
    expect(check.candidateHandle, isNotNull);
    expect(response.frame!.revision, opened.frame.revision);
    final retried = await tool(connection, request);
    final rechecked = WritingCheck.fromWire(retried.result);
    expect(rechecked.candidateHandle, check.candidateHandle);
    expect(retried.frame!.toWire().toText(), response.frame!.toWire().toText());
    final originalValidation =
        ValidationV3.fromWire(check.validation!) as EvaluatedValidation;
    final retryValidation =
        ValidationV3.fromWire(rechecked.validation!) as EvaluatedValidation;
    expect(
      retryValidation.execution.inputDigest,
      originalValidation.execution.inputDigest,
    );
    expect(
      retryValidation.execution.runId,
      isNot(originalValidation.execution.runId),
    );
    // Check retains an independent draft; the seeded author draft can be withdrawn.
    final withdrawn = Proposal.fromWire(
      (await tool(
        connection,
        WithdrawProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: draft.reference,
          idempotencyKey: 'public-withdraw',
        ),
      )).result,
    );
    expect(withdrawn.withdrawn, isTrue);
    final head = Description.fromWire(
      (await tool(
        connection,
        DescribeSummaryRequest(universe: const Selector('World')),
      )).result,
    ).continuities.single.revisionId;
    expect(head, opened.frame.revision);
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: null,
        propose: false,
        edit: false,
        protected: false,
      ),
    );
    final writerConnection = runtime.connect(hello(writer.id));
    final writerContext = await readContext(writerConnection);
    await expectLater(
      tool(
        writerConnection,
        CreateProposalRequest(
          universe: const Selector('World'),
          contextId: writerContext.contextId,
          operations: [
            DefineUnitOperation(
              clientRef: f.id(11).value,
              record: units.unit(key: 'other'),
            ),
          ],
          submission: Submission.draft,
          rationale: 'Denied authoring',
          idempotencyKey: 'denied-create',
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      tool(
        writerConnection,
        GetProposalRequest(
          universe: const Selector('World'),
          proposalId: draft.proposal.proposalId,
          version: draft.proposal.version,
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  QueuedProposalValidationRequest queueRequest(
    OpenedContext opened, {
    String key = 'runtime-queue',
  }) => QueuedProposalValidationRequest(
    universe: const Selector('World'),
    contextId: opened.contextId,
    proposalReference: draft.reference,
    checkScope: CheckScope.candidate,
    idempotencyKey: key,
  );

  Future<OperationStatusV3> completedOperation(
    NativeSqliteConnection connection,
    OperationId id,
  ) async {
    final timer = Stopwatch()..start();
    while (true) {
      final response = await tool(
        connection,
        GetOperationIdRequest(
          universe: const Selector('World'),
          operationId: id,
        ),
      );
      final status = OperationStatusV3.fromWire(response.result);
      if ({
        OperationState.succeeded,
        OperationState.failed,
        OperationState.cancelled,
      }.contains(status.state)) {
        return status;
      }
      if (timer.elapsed > const Duration(seconds: 10)) {
        fail('Retained validation did not settle: ${status.state}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('public queued validation completes through native scheduler and survives restart', () async {
    var connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    final request = queueRequest(opened);
    final response = await tool(connection, request);
    final queued = OperationStatusV3.fromWire(response.result);
    expect(queued.state, OperationState.queued);
    expect(response.frame!.revision, opened.frame.revision);
    final finished = await completedOperation(connection, queued.operationId);
    expect(finished.state, OperationState.succeeded);
    final validation = finished.validation as EvaluatedValidation;
    expect(validation.finalBindingDigest, isNotNull);
    expect(validation.execution.coverage, Coverage.complete);
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    final byKey = await tool(
      connection,
      GetOperationKeyRequest(
        universe: const Selector('World'),
        operationKind: OperationKind.validate,
        idempotencyKey: 'runtime-queue',
      ),
    );
    expect(
      OperationStatusV3.fromWire(byKey.result).toWire().toText(),
      finished.toWire().toText(),
    );
    expect(byKey.frame!.revision, opened.frame.revision);
    expect(byKey.delivery.complete, isTrue);
    expect(
      OperationStatusV3.fromWire((await tool(connection, request)).result)
          .operationId,
      queued.operationId,
    );
    await expectLater(
      tool(
        connection,
        QueuedProposalValidationRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: draft.reference,
          checkScope: CheckScope.universe,
          idempotencyKey: 'runtime-queue',
        ),
      ),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
  });

  test(
    'public cancellation retains its marker and denies other profiles',
    () async {
      final connection = runtime.connect(hello(author.id));
      final opened = await readContext(connection);
      final request = queueRequest(opened);
      final queued = OperationStatusV3.fromWire(
        (await tool(connection, request)).result,
      );
      final cancel = CancelOperationRequest(
        universe: const Selector('World'),
        operationId: queued.operationId,
        idempotencyKey: 'runtime-cancel',
      );
      final response = await tool(connection, cancel);
      final cancelled = OperationStatusV3.fromWire(response.result);
      expect(cancelled.state, OperationState.cancelled);
      expect(cancelled.cancellationRequested, isTrue);
      expect(response.frame, isNull);
      final terminal = await completedOperation(connection, queued.operationId);
      expect(terminal.state, OperationState.cancelled);
      authority.grant(
        author,
        GrantSpec(
          profileId: writer.id,
          universeId: f.u,
          worlds: null,
          propose: false,
          edit: false,
          protected: false,
        ),
      );
      final writerConnection = runtime.connect(hello(writer.id));
      await expectLater(
        tool(writerConnection, cancel),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        tool(
          writerConnection,
          GetOperationIdRequest(
            universe: const Selector('World'),
            operationId: queued.operationId,
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await runtime.close();
      runtime = NativeSqliteRuntime(authority: authority);
      final reopened = runtime.connect(hello(author.id));
      expect(
        OperationStatusV3.fromWire((await tool(reopened, cancel)).result).state,
        OperationState.cancelled,
      );
      expect(
        OperationStatusV3.fromWire((await tool(reopened, request)).result)
            .state,
        OperationState.cancelled,
      );
    },
  );

  test(
    'native shutdown preserves interrupted queued work for exact retry',
    () async {
      var connection = runtime.connect(hello(author.id));
      final opened = await readContext(connection);
      final request = queueRequest(opened);
      final queued = OperationStatusV3.fromWire(
        (await tool(connection, request)).result,
      );
      await runtime.close();
      runtime = NativeSqliteRuntime(authority: authority);
      connection = runtime.connect(hello(author.id));
      final recovered = OperationStatusV3.fromWire(
        (await tool(
          connection,
          GetOperationIdRequest(
            universe: const Selector('World'),
            operationId: queued.operationId,
          ),
        )).result,
      );
      expect(recovered.state, OperationState.interrupted);
      expect(
        (recovered.validation as EvaluatedValidation).finalBindingDigest,
        isNull,
      );
      final retry = OperationStatusV3.fromWire(
        (await tool(connection, request)).result,
      );
      expect(retry.operationId, queued.operationId);
      expect(
        (await completedOperation(connection, queued.operationId)).state,
        OperationState.succeeded,
      );
    },
  );

  test('public source assessments retain immutable attachment selection and historical retry', () async {
    seedReadRows([
      f.row(
        1,
        SourceRecord(
          label: 'External source',
          origin: const OriginMetadata(),
          versions: [f.id(2)],
        ),
      ),
      f.row(2, sources.source()),
    ]);
    final sourcePackage = OwnedSqliteDatabase.openExisting(path);
    try {
      sourcePackage.recover();
      WorkflowStorage(
        sourcePackage.database,
      ).compareAppend({}, sources.staging(sources.source()).entries.toList());
    } finally {
      sourcePackage.close();
    }
    var connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    final proposal = Proposal.fromWire(
      (await tool(
        connection,
        CreateProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          operations: [
            CreateEntityOperation(
              clientRef: f.id(20).value,
              record: f.entity(),
            ),
          ],
          submission: Submission.submitted,
          rationale: 'External source review',
          idempotencyKey: 'assessment-proposal',
        ),
      )).result,
    );
    final ref = ProposalRef(
      proposalId: proposal.proposalId,
      version: proposal.version,
      digest: proposal.digest,
    );
    var wire = accounting.replace(assessments.body().toWire(), [
      'proposal',
    ], ref.toWire());
    wire = accounting.replace(wire, ['base_frame'], opened.frame.toWire());
    wire = accounting.replace(wire, [
      'assessor',
      'principal',
    ], CanonicalString(author.id.value.replaceFirst('prf_', 'prn_')));
    final attach = AttachAssessmentRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
      proposalReference: ref,
      expectedSelectionGeneration: BigInt.zero,
      body: SourceAssessmentV1.fromWire(wire),
      idempotencyKey: 'public-attach',
    );
    final response = await tool(connection, attach);
    final selected = AssessmentSelection.fromWire(response.result);
    expect(selected.selected, isNotNull);
    expect(response.frame!.toWire().toText(), opened.frame.toWire().toText());
    final clear = SelectAssessmentRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
      proposalReference: ref,
      expectedSelectionGeneration: selected.generation,
      assessmentReference: null,
      idempotencyKey: 'public-clear',
    );
    final cleared = AssessmentSelection.fromWire(
      (await tool(connection, clear)).result,
    );
    expect(cleared.selected, isNull);
    expect(cleared.generation, selected.generation + BigInt.one);
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    expect(
      (await tool(connection, attach)).toWire((v) => v).toText(),
      response.toWire((v) => v).toText(),
    );
    final historic = await tool(
      connection,
      GetProposalRequest(
        universe: const Selector('World'),
        proposalId: proposal.proposalId,
        version: proposal.version,
        viewGroup: ProposalView.assessment,
        assessmentReference: selected.selected,
      ),
    );
    expect(
      ProposalViewResult.fromWire(historic.result),
      isA<AssessmentProposalView>(),
    );
    expect(historic.frame!.revision, opened.frame.revision);
    final reselected = AssessmentSelection.fromWire(
      (await tool(
        connection,
        SelectAssessmentRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: ref,
          expectedSelectionGeneration: cleared.generation,
          assessmentReference: selected.selected,
          idempotencyKey: 'public-reselect',
        ),
      )).result,
    );
    expect(
      reselected.selected!.toWire().toText(),
      selected.selected!.toWire().toText(),
    );
    await expectLater(
      tool(
        connection,
        SelectAssessmentRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: ref,
          expectedSelectionGeneration: BigInt.zero,
          assessmentReference: null,
          idempotencyKey: 'public-stale-selection',
        ),
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
  });

  Future<CanonicalValue> engine(
    NativeSqliteConnection connection,
    EngineRequest request,
  ) => connection.execute(EngineRequest.decode(request.toWire().toBytes()));

  test('private installation commands expose current catalog and redacted profiles without opening workers', () async {
    final authorConnection = runtime.connect(hello(author.id));
    final writerConnection = runtime.connect(hello(writer.id));
    final blocker = OwnedSqliteDatabase.openExisting(path);
    try {
      WireFields status(CanonicalValue value) => WireFields(value, {
        'service_instance',
        'principal',
        'author',
        'universes',
        'canonical_commit',
        'max_requests_per_principal',
        'universe_queue_capacity',
      });
      final original = status(
        await engine(authorConnection, const StatusEngineRequest()),
      );
      expect(
        original.string('service_instance'),
        authorConnection.welcome.serviceInstance,
      );
      expect(original.string('principal'), author.id.value);
      expect(original.boolean('author'), isTrue);
      expect(original.array('universes').length, 1);
      expect(
        status(await engine(writerConnection, const StatusEngineRequest()))
            .array('universes'),
        isEmpty,
      );
      final enrolled = ProfileId.parse(
        WireFields(
          await engine(authorConnection, const EnrollEngineRequest()),
          {'profile_id'},
        ).string('profile_id'),
      );
      final enrolledConnection = runtime.connect(hello(enrolled));
      final grant = GrantSpec(
        profileId: enrolled,
        universeId: f.u,
        worlds: null,
        propose: true,
        edit: false,
        protected: false,
      );
      expect(
        WireFields(
          await engine(authorConnection, GrantEngineRequest(grant: grant)),
          {'granted'},
        ).boolean('granted'),
        isTrue,
      );
      final profiles = WireFields(
        await engine(authorConnection, const ProfilesEngineRequest()),
        {'profiles', 'grants'},
      );
      expect(
        profiles
            .array('profiles')
            .map(
              (value) => ProfileId.parse(
                WireFields(value, {
                  'profile_id',
                  'author',
                  'revoked',
                }).string('profile_id'),
              ),
            )
            .toSet(),
        {author.id, writer.id, enrolled},
      );
      expect(profiles.array('grants').single.toText(), grant.toWire().toText());
      await engine(
        authorConnection,
        RenameUniverseEngineRequest(universeId: f.u, name: 'Campaign'),
      );
      final catalog = status(
        await engine(enrolledConnection, const StatusEngineRequest()),
      ).array('universes');
      expect(
        WireFields(catalog.single, {'id', 'name'}).string('name'),
        'Campaign',
      );
      await engine(
        authorConnection,
        WithdrawGrantEngineRequest(profileId: enrolled, universeId: f.u),
      );
      expect(
        status(await engine(enrolledConnection, const StatusEngineRequest()))
            .array('universes'),
        isEmpty,
      );
      await expectLater(
        tool(
          enrolledConnection,
          DescribeSummaryRequest(universe: const Selector('World')),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await engine(authorConnection, RevokeEngineRequest(profileId: enrolled));
      await expectLater(
        engine(enrolledConnection, const StatusEngineRequest()),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      final revokedProfiles = WireFields(
        await engine(authorConnection, const ProfilesEngineRequest()),
        {'profiles', 'grants'},
      );
      expect(revokedProfiles.array('grants'), isEmpty);
      expect(
        revokedProfiles
            .array('profiles')
            .map((v) => WireFields(v, {'profile_id', 'author', 'revoked'}))
            .singleWhere((v) => v.string('profile_id') == enrolled.value)
            .boolean('revoked'),
        isTrue,
      );
      for (final request in <EngineRequest>[
        const ProfilesEngineRequest(),
        const EnrollEngineRequest(),
        GrantEngineRequest(grant: grant),
        RevokeEngineRequest(profileId: author.id),
        WithdrawGrantEngineRequest(profileId: author.id, universeId: f.u),
        RenameUniverseEngineRequest(universeId: f.u, name: 'Denied'),
        const ShutdownEngineRequest(),
      ]) {
        await expectLater(
          engine(writerConnection, request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      }
      expect(
        status(await engine(authorConnection, const StatusEngineRequest()))
            .array('universes'),
        hasLength(1),
      );
    } finally {
      blocker.close();
    }
    final opened = await readContext(authorConnection);
    expect(opened.frame.universe, f.u);
  });

  test('private shutdown acknowledges and drains queued evaluation without deadlocking its own request', () async {
    final connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    final queued = OperationStatusV3.fromWire(
      (await tool(connection, queueRequest(opened))).result,
    );
    final shutdown = WireFields(
      await engine(connection, const ShutdownEngineRequest()),
      {'shutdown'},
    );
    expect(shutdown.string('shutdown'), 'requested');
    expect(() => runtime.connect(hello(author.id)), throwsStateError);
    expect(
      () => engine(connection, const StatusEngineRequest()),
      throwsStateError,
    );
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      final retained = WorkflowStorage(package.database)
          .get('operation:${queued.operationId.value}');
      expect(retained, isNotNull);
      expect(
        SqliteKernel(
          package.database,
          f.u,
        ).journal.head(opened.frame.continuity),
        opened.frame.revision,
      );
    } finally {
      package.close();
    }
  });

  test('native creation retains explicit fictional and Gregorian clocks with owned durable packages', () async {
    final connection = runtime.connect(hello(author.id));
    final starts = <UniverseStart>[
      FictionalUniverseStart(
        calendarName: 'Aurora',
        initialTick: '9007199254740993',
        tickLabel: 'days',
        ticksPerMonth: 36,
      ),
      const GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
    ];
    final created =
        <
          ({
            UniverseId id,
            ContinuityId continuity,
            RecordId context,
            RevisionId revision,
            String path,
            CanonicalValue records,
          })
        >[];
    for (var i = 0; i < starts.length; i++) {
      final name = 'Authored $i';
      final response = WireFields(
        await engine(
          connection,
          CreateUniverseEngineRequest(name: name, start: starts[i]),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final id = UniverseId.parse(response.string('universe_id'));
      final continuity = ContinuityId.parse(response.string('continuity_id'));
      final context = RecordId.parse(response.string('context_id'));
      final revision = RevisionId.parse(response.string('revision'));
      final entry = authority
          .catalog(author)
          .singleWhere((entry) => entry.universeId == id);
      expect(entry.name, name);
      expect(
        () => OwnedSqliteDatabase.openExisting(entry.path),
        throwsA(isA<FileSystemException>()),
      );
      final opened = OpenedContext.fromWire(
        (await tool(
          connection,
          OpenContextRequest(
            universe: Selector(name),
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(context),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
        )).result,
      );
      expect(opened.frame.revision, revision);
      final read = await tool(
        connection,
        GetRequest(
          universe: Selector(name),
          contextId: opened.contextId,
          recordIds: [context],
          fieldGroups: [FieldGroup.payload],
        ),
      );
      final objective =
          Records.fromWire(read.result).records.single.payload
              as RepresentedContextRecord;
      expect(objective.kind, isA<ObjectiveContext>());
      final clock = objective.chronology!;
      expect(
        clock.toWire().toText(),
        starts[i].build(clock.calendar).$1.toWire().toText(),
      );
      final calendar =
          Records.fromWire(
                (await tool(
                  connection,
                  GetRequest(
                    universe: Selector(name),
                    contextId: opened.contextId,
                    recordIds: [clock.calendar.toRecordId()],
                    fieldGroups: [FieldGroup.payload],
                  ),
                )).result,
              ).records.single.payload
              as CalendarRecord;
      expect(
        calendar.toWire().toText(),
        starts[i].build(clock.calendar).$2.toWire().toText(),
      );
      created.add((
        id: id,
        continuity: continuity,
        context: context,
        revision: revision,
        path: entry.path,
        records: read.result,
      ));
    }
    await runtime.close();
    for (final fixture in created) {
      final package = OwnedSqliteDatabase.openExisting(fixture.path);
      try {
        package.recover();
        final kernel = SqliteKernel(package.database, fixture.id);
        expect(kernel.journal.head(fixture.continuity), fixture.revision);
        expect(
          kernel.journal.snapshot(fixture.continuity, fixture.revision),
          hasLength(2),
        );
        final version = kernel.journal.snapshot(
          fixture.continuity,
          fixture.revision,
        )[fixture.context]!;
        final stored = RecordVersion.fromWire(
          kernel.journal.load(version).toCanonical(),
        );
        expect(
          Records.fromWire(fixture.records).records.single.toWire().toText(),
          stored.toWire().toText(),
        );
      } finally {
        package.close();
      }
    }
    runtime = NativeSqliteRuntime(authority: authority);
    final reopened = runtime.connect(hello(author.id));
    expect(
      WireFields(await engine(reopened, const StatusEngineRequest()), {
        'service_instance',
        'principal',
        'author',
        'universes',
        'canonical_commit',
        'max_requests_per_principal',
        'universe_queue_capacity',
      }).array('universes'),
      hasLength(3),
    );
  });

  test('native creation rejects writer authority and invalid authored inputs before creating files', () async {
    final authorConnection = runtime.connect(hello(author.id));
    final writerConnection = runtime.connect(hello(writer.id));
    Set<String> files() =>
        Directory('${root.path}/packages')
            .listSync()
            .map((file) => file.path)
            .toSet();
    final before = files();
    final start = const GregorianUniverseStart('2040-03-15T12:30:00+02:00');
    await expectLater(
      engine(
        writerConnection,
        CreateUniverseEngineRequest(name: 'Denied', start: start),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      engine(
        authorConnection,
        CreateUniverseEngineRequest(name: '  ', start: start),
      ),
      throwsFormatException,
    );
    await expectLater(
      engine(
        authorConnection,
        CreateUniverseEngineRequest(
          name: 'Invalid clock',
          start: const GregorianUniverseStart('not a date'),
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      engine(
        authorConnection,
        CreateUniverseEngineRequest(
          name: 'Invalid month',
          start: FictionalUniverseStart(
            calendarName: 'Aurora',
            initialTick: '10',
            tickLabel: 'days',
            ticksPerMonth: 0,
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(files(), before);
    expect(authority.catalog(author), hasLength(1));
  });

  test('native registration retains recovered external identity and retries after catalog conflict', () async {
    final foreign = UniverseId.generate();
    final continuity = ContinuityId.generate();
    final path = '${root.path}/external/imported.sqlite';
    final external = OwnedSqliteDatabase.create(path);
    late RevisionId genesis;
    try {
      external.database.execute('BEGIN IMMEDIATE');
      genesis = SqliteKernel(
        external.database,
        foreign,
      ).journal.initialize('External', continuity, PrincipalId.generate());
      external.database.execute('COMMIT');
    } finally {
      external.close();
    }
    final connection = runtime.connect(hello(author.id));
    final writerConnection = runtime.connect(hello(writer.id));
    await expectLater(
      engine(
        writerConnection,
        RegisterUniverseEngineRequest(path: path, name: 'External'),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      engine(
        connection,
        RegisterUniverseEngineRequest(path: path, name: 'World'),
      ),
      throwsA(isA<Exception>()),
    );
    expect(authority.catalog(author), hasLength(1));
    final retryable = OwnedSqliteDatabase.openExisting(path);
    try {
      retryable.recover();
      expect(retryable.universeId, foreign);
    } finally {
      retryable.close();
    }
    final response = WireFields(
      await engine(
        connection,
        RegisterUniverseEngineRequest(path: path, name: 'Imported'),
      ),
      {'universe_id', 'name'},
    );
    expect(response.string('universe_id'), foreign.value);
    final entry = authority
        .catalog(author)
        .singleWhere((entry) => entry.universeId == foreign);
    expect(entry.path, File(path).resolveSymbolicLinksSync());
    expect(
      () => OwnedSqliteDatabase.openExisting(path),
      throwsA(isA<FileSystemException>()),
    );
    final summary = Description.fromWire(
      (await tool(
        connection,
        DescribeSummaryRequest(universe: const Selector('Imported')),
      )).result,
    );
    // Registration does not manufacture a represented context for an empty
    // existing package. Its genesis is verified directly after reopening.
    expect(summary.continuities, isEmpty);
    await runtime.close();
    final recovered = OwnedSqliteDatabase.openExisting(path);
    try {
      recovered.recover();
      expect(recovered.universeId, foreign);
      expect(
        SqliteKernel(recovered.database, foreign).journal.head(continuity),
        genesis,
      );
    } finally {
      recovered.close();
    }
  });

  Future<WireFields> library(NativeSqliteConnection connection) async =>
      WireFields(
        await engine(
          connection,
          const LibraryEngineRequest(universe: Selector('World')),
        ),
        {'storage', 'worlds', 'contexts', 'continuities', 'writing'},
      );

  test('private library retains all continuity heads worlds and contexts without writer disclosure', () async {
    seedReadRows([
      f.row(50, WorldRecord(selector: 'Campaign', aliases: ['Play'])),
    ]);
    final branch = ContinuityId.generate();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      final kernel = SqliteKernel(package.database, f.u);
      package.database.execute('BEGIN IMMEDIATE');
      kernel.journal.branch(
        branch,
        draft.proposal.baseFrame.continuity,
        kernel.journal.head(draft.proposal.baseFrame.continuity),
        PrincipalId.generate(),
      );
      package.database.execute('COMMIT');
      WorkflowStorage(package.database).compareAppend({}, [
        MapEntry(
          'continuity-name:${branch.value}',
          CanonicalString('Alternate continuity'),
        ),
      ]);
    } finally {
      package.close();
    }
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: null,
        propose: true,
        edit: true,
        protected: true,
      ),
    );
    final writerConnection = runtime.connect(hello(writer.id));
    final blocker = OwnedSqliteDatabase.openExisting(path);
    try {
      await expectLater(
        library(writerConnection),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    } finally {
      blocker.close();
    }
    final authorConnection = runtime.connect(hello(author.id));
    final response = await library(authorConnection);
    final storage = WireFields(response.require('storage'), {
      'universe',
      'sqlite_version',
      'journal_mode',
      'synchronous',
      'foreign_keys',
      'heads',
    });
    expect(storage.string('universe'), f.u.value);
    expect(storage.string('sqlite_version'), isNotEmpty);
    expect(storage.string('journal_mode'), 'wal');
    expect(storage.u64('synchronous'), BigInt.two);
    expect(storage.boolean('foreign_keys'), isTrue);
    expect(storage.array('heads'), hasLength(2));
    expect(response.array('worlds'), hasLength(2));
    expect(
      response
          .array('worlds')
          .map(
            (v) => WireFields(v, {'id', 'name', 'continuity_id'}).string('id'),
          )
          .toSet(),
      {permissions.world(50).value},
    );
    expect(response.array('contexts').map(wireString), [
      f.id(99).value,
      f.id(99).value,
    ]);
    expect(
      response
          .array('continuities')
          .map((v) => WireFields(v, {'id', 'revision', 'name'}).string('name'))
          .toSet(),
      {'Original continuity', 'Alternate continuity'},
    );
    final writing = WireFields(response.require('writing'), {
      'proposals',
      'approved',
    });
    expect(writing.array('proposals'), hasLength(1));
    final entry = WireFields(writing.array('proposals').single, {
      'candidate',
      'label',
      'submission',
      'base_revision',
      'continuity',
    });
    expect(entry.string('label'), draft.proposal.rationale);
    expect(
      ProposalRef.fromWire(entry.require('candidate')).toWire().toText(),
      draft.reference.toWire().toText(),
    );
    await expectLater(
      engine(
        authorConnection,
        const LibraryEngineRequest(universe: Selector('Missing')),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('private library displays latest named proposal and suppresses its withdrawn revision', () async {
    final connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    EntityRecord person(String name) => EntityRecord(
      names: [
        ContextualName(text: name, validity: const UnspecifiedValidity()),
      ],
      classificationResolution: ClassificationResolution.unclassified,
      worldAssociations: [],
      labels: {'en': 'Display label'},
      metadata: {},
    );
    final created = Proposal.fromWire(
      (await tool(
        connection,
        CreateProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          operations: [
            CreateEntityOperation(
              clientRef: f.id(20).value,
              record: person('Mara'),
            ),
          ],
          submission: Submission.draft,
          rationale: 'Authored identity',
          idempotencyKey: 'library-create',
        ),
      )).result,
    );
    ProposalRef reference(Proposal p) => ProposalRef(
      proposalId: p.proposalId,
      version: p.version,
      digest: p.digest,
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
    final original = pending(await library(connection)).singleWhere(
      (v) =>
          ProposalRef.fromWire(v.require('candidate')).proposalId ==
          created.proposalId,
    );
    expect(original.string('label'), 'Mara');
    final revised = Proposal.fromWire(
      (await tool(
        connection,
        ReviseProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: reference(created),
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
      )).result,
    );
    final latest = pending(await library(connection))
        .where(
          (v) =>
              ProposalRef.fromWire(v.require('candidate')).proposalId ==
              created.proposalId,
        )
        .toList();
    expect(latest, hasLength(1));
    expect(latest.single.string('label'), 'Mara corrected');
    expect(
      ProposalRef.fromWire(latest.single.require('candidate')).version,
      revised.version,
    );
    await tool(
      connection,
      WithdrawProposalRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
        proposalReference: reference(revised),
        idempotencyKey: 'library-withdraw',
      ),
    );
    expect(
      pending(await library(connection))
          .map((v) => ProposalRef.fromWire(v.require('candidate')).proposalId),
      isNot(contains(created.proposalId)),
    );
  });

  test('private library keeps approval history and hides publication only after durable receipt across restart', () async {
    var connection = runtime.connect(hello(author.id));
    final prepared = WireFields(
      await engine(
        connection,
        AuthorWritingEngineRequest(
          universe: const Selector('World'),
          action: PrepareContractsWritingAction(
            candidate: draft.proposal.proposalId,
            label: 'Unit definition',
            text: 'Metres measure length.',
          ),
        ),
      ),
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
    final reference = ProposalRef.fromWire(prepared.require('candidate'));
    final validation = ValidationV3.fromWire(
      prepared.require('validation'),
    ) as EvaluatedValidation;
    final before = WireFields((await library(connection)).require('writing'), {
      'proposals',
      'approved',
    });
    expect(before.array('proposals'), hasLength(1));
    expect(
      WireFields(before.array('proposals').single, {
        'candidate',
        'label',
        'submission',
        'base_revision',
        'continuity',
      }).string('label'),
      'Unit definition',
    );
    expect(before.array('approved'), isEmpty);
    await engine(
      connection,
      ApproveEngineRequest(
        universe: const Selector('World'),
        proposalReference: reference,
        validationRun: validation.execution.runId,
      ),
    );
    final approved = WireFields(
      (await library(connection)).require('writing'),
      {'proposals', 'approved'},
    );
    expect(approved.array('proposals'), hasLength(1));
    final card = WireFields(approved.array('approved').single, {
      'candidate',
      'validation_run',
      'label',
    });
    expect(card.string('validation_run'), validation.execution.runId.value);
    expect(card.string('label'), 'Unit definition');
    expect(
      ProposalRef.fromWire(card.require('candidate')).digest,
      reference.digest,
    );
    await engine(
      connection,
      AuthorWritingEngineRequest(
        universe: const Selector('World'),
        action: PublishWritingAction(
          candidate: reference,
          validationRun: validation.execution.runId,
          idempotencyKey: 'library-publish',
        ),
      ),
    );
    final published = await engine(
      connection,
      const LibraryEngineRequest(universe: Selector('World')),
    );
    final completed = WireFields(
      WireFields(published, {
        'storage',
        'worlds',
        'contexts',
        'continuities',
        'writing',
      }).require('writing'),
      {'proposals', 'approved'},
    );
    expect(completed.array('proposals'), isEmpty);
    expect(completed.array('approved'), hasLength(1));
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    expect(
      (await engine(
        connection,
        const LibraryEngineRequest(universe: Selector('World')),
      )).toText(),
      published.toText(),
    );
  });

  test('private images retain originals without publication and preview only a pinned canonical asset', () async {
    final bytes = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
    );
    final source = File('${root.path}/Portrait é.png')..writeAsBytesSync(bytes);
    final connection = runtime.connect(hello(author.id));
    final oldContext = await readContext(connection);
    final imported = WireFields(
      await engine(
        connection,
        StageImageEngineRequest(
          universe: const Selector('World'),
          source: source.path,
        ),
      ),
      {'canonical', 'asset_id', 'preview', 'metadata', 'operations'},
    );
    expect(imported.boolean('canonical'), isFalse);
    expect(imported.string('preview'), startsWith('data:image/jpeg;base64,'));
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
    ImagePreviewEngineRequest preview(ContextId context) =>
        ImagePreviewEngineRequest(
          universe: const Selector('World'),
          contextId: context,
          asset: id,
        );
    await expectLater(
      engine(connection, preview(oldContext.contextId)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      final kernel = SqliteKernel(package.database, f.u);
      expect(kernel.imageBytes(asset), orderedEquals(bytes));
      expect(
        kernel.journal.head(draft.proposal.baseFrame.continuity),
        draft.proposal.baseFrame.revision,
      );
      expect(kernel.identityExists(id), isFalse);
    } finally {
      package.close();
    }
    seedReadRows([
      RecordVersion.build(
        recordVersionId: RecordVersionId.generate(),
        identity: RecordIdentity(
          universeId: f.u,
          recordId: id,
          recordKind: RecordKind.imageAsset,
        ),
        payload: asset,
      ),
    ]);
    runtime = NativeSqliteRuntime(authority: authority);
    final restarted = runtime.connect(hello(author.id));
    await expectLater(
      engine(restarted, preview(oldContext.contextId)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final current = await readContext(restarted);
    await expectLater(
      engine(
        restarted,
        ImagePreviewEngineRequest(
          universe: const Selector('World'),
          contextId: current.contextId,
          asset: f.id(99),
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final result = await engine(restarted, preview(current.contextId));
    expect(
      WireFields(result, {'asset_id', 'metadata', 'preview'}).string('preview'),
      imported.string('preview'),
    );
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    expect(
      (await engine(
        runtime.connect(hello(author.id)),
        preview(current.contextId),
      )).toText(),
      result.toText(),
    );
  });

  test('private image import refuses writers symlinks nonregular files and invalid bounded content', () async {
    final connection = runtime.connect(hello(author.id));
    final source = File('${root.path}/invalid.png')
      ..writeAsStringSync('not an image');
    final link = Link('${root.path}/linked.png')..createSync(source.path);
    final fifo = '${root.path}/pipe.png';
    expect((await Process.run('mkfifo', [fifo])).exitCode, 0);
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: null,
        propose: true,
        edit: true,
        protected: true,
      ),
    );
    StageImageEngineRequest request(String path) => StageImageEngineRequest(
      universe: const Selector('World'),
      source: path,
    );
    await expectLater(
      engine(
        runtime.connect(hello(writer.id)),
        request('/unreadable/never-opened'),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      engine(connection, request(link.path)),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      engine(connection, request(root.path)),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      engine(connection, request(fifo)),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      engine(connection, request(source.path)),
      throwsA(isA<FormatException>()),
    );
    source.writeAsBytesSync(List.filled(maxImageBytes + 1, 0));
    await expectLater(
      engine(connection, request(source.path)),
      throwsA(isA<FormatException>()),
    );
    source.writeAsBytesSync([]);
    await expectLater(
      engine(connection, request(source.path)),
      throwsA(isA<FormatException>()),
    );
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      expect(WorkflowStorage(package.database).keys('image-asset:'), isEmpty);
    } finally {
      package.close();
    }
  });

  DraftContent editorContent(
    String rationale, {
    List<DomainOperation> operations = const [],
    RecordId? context,
  }) => DraftContent(
    baseRevision: draft.proposal.baseFrame.revision,
    representedContext: context ?? f.id(99),
    operations: operations,
    rationale: rationale,
    proposal: draft.reference,
  );
  SaveDraftEngineRequest saveEditor(DraftContent content, BigInt expected) =>
      SaveDraftEngineRequest(
        universe: const Selector('World'),
        continuityId: draft.proposal.baseFrame.continuity,
        expectedVersion: expected,
        content: content,
      );
  LoadDraftEngineRequest loadEditor() => LoadDraftEngineRequest(
    universe: const Selector('World'),
    continuityId: draft.proposal.baseFrame.continuity,
  );

  test('private drafts retain immutable edits and recover lost saves without overwriting another window', () async {
    var first = runtime.connect(hello(author.id));
    final second = runtime.connect(hello(author.id));
    expect(await engine(first, loadEditor()), isA<CanonicalNull>());
    final content = editorContent(
      'Unfinished author text é😀',
      operations: [
        DefineUnitOperation(clientRef: 'unfinished-unit', record: units.unit()),
      ],
    );
    final request = saveEditor(content, BigInt.zero);
    final saved = await engine(first, request);
    expect(SavedDraft.fromWire(saved).version, BigInt.one);
    expect(
      SavedDraft.fromWire(saved).content.toWire().toText(),
      content.toWire().toText(),
    );
    expect((await engine(second, request)).toText(), saved.toText());
    await expectLater(
      engine(second, saveEditor(editorContent('Competing text'), BigInt.zero)),
      throwsA(
        isA<BaseRevisionConflictError>()
            .having((e) => e.expected, 'expected', 'draft:0')
            .having((e) => e.actual, 'actual', 'draft:1'),
      ),
    );
    expect((await engine(second, loadEditor())).toText(), saved.toText());
    final writerConnection = runtime.connect(hello(writer.id));
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: null,
        propose: true,
        edit: true,
        protected: true,
      ),
    );
    await expectLater(
      engine(writerConnection, loadEditor()),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      engine(writerConnection, request),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    first = runtime.connect(hello(author.id));
    expect((await engine(first, request)).toText(), saved.toText());
    final changed = editorContent('Second immutable edit');
    final revised = SavedDraft.fromWire(
      await engine(first, saveEditor(changed, BigInt.one)),
    );
    expect(revised.version, BigInt.two);
    final summary = await library(first);
    expect(
      WireFields(summary.require('writing'), {
        'proposals',
        'approved',
      }).array('proposals'),
      hasLength(1),
    );
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      final workflow = WorkflowStorage(package.database);
      final keys = workflow.keys(
        'draft:${author.id.value}:${draft.proposal.baseFrame.continuity.value}:',
      );
      expect(keys, hasLength(2));
      expect(workflow.get(keys.first)!.toText(), saved.toText());
      expect(workflow.get(keys.last)!.toText(), revised.toWire().toText());
      expect(
        SqliteKernel(
          package.database,
          f.u,
        ).journal.head(draft.proposal.baseFrame.continuity),
        draft.proposal.baseFrame.revision,
      );
      expect(workflow.keys('approval:'), isEmpty);
    } finally {
      package.close();
    }
  });

  test('private drafts enforce UTF-8 budgets and represented context before retaining a revision', () async {
    final connection = runtime.connect(hello(author.id));
    await expectLater(
      engine(connection, saveEditor(editorContent('😀' * 4001), BigInt.zero)),
      throwsA(
        isA<InvalidArgumentError>().having((e) => e.field, 'field', 'draft'),
      ),
    );
    final oversized = editorContent(
      'Oversized operations',
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
    expect(
      saveEditor(oversized, BigInt.zero).toWire().toBytes().length,
      lessThan(maxFrameBytes),
    );
    await expectLater(
      engine(connection, saveEditor(oversized, BigInt.zero)),
      throwsA(isA<InvalidArgumentError>()),
    );
    await expectLater(
      engine(
        connection,
        saveEditor(
          editorContent('Unknown represented context', context: f.id(20)),
          BigInt.zero,
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(await engine(connection, loadEditor()), isA<CanonicalNull>());
    final boundary = editorContent('😀' * 4000);
    final saved = SavedDraft.fromWire(
      await engine(connection, saveEditor(boundary, BigInt.zero)),
    );
    expect(saved.content.rationale, boundary.rationale);
    expect(saved.version, BigInt.one);
  });

  test('private drafts preserve an old base after canon advances without refreshing or publishing intent', () async {
    var connection = runtime.connect(hello(author.id));
    final content = editorContent('Draft at the original base');
    final saved = await engine(connection, saveEditor(content, BigInt.zero));
    await runtime.close();
    seedReadRows([f.row(20, f.entity())]);
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    expect((await engine(connection, loadEditor())).toText(), saved.toText());
    final revised = SavedDraft.fromWire(
      await engine(
        connection,
        saveEditor(
          editorContent('Edited against the same old base'),
          BigInt.one,
        ),
      ),
    );
    expect(revised.content.baseRevision, content.baseRevision);
    final libraryResponse = await library(connection);
    final heads = WireFields(libraryResponse.require('storage'), {
      'universe',
      'sqlite_version',
      'journal_mode',
      'synchronous',
      'foreign_keys',
      'heads',
    }).array('heads');
    expect(
      wireString((heads.single as CanonicalArray).items.last),
      isNot(content.baseRevision.value),
    );
  });

  test('private draft version limit allows recovery of the final save and prevents further append', () async {
    final content = editorContent('Last retained editor revision');
    final last = SavedDraft(version: BigInt.from(10000), content: content);
    final prefix =
        'draft:${author.id.value}:${draft.proposal.baseFrame.continuity.value}:';
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      WorkflowStorage(package.database).compareAppend({}, [
        MapEntry('${prefix}00000000000000010000', last.toWire()),
      ]);
    } finally {
      package.close();
    }
    final connection = runtime.connect(hello(author.id));
    expect(
      (await engine(connection, loadEditor())).toText(),
      last.toWire().toText(),
    );
    expect(
      (await engine(
        connection,
        saveEditor(content, BigInt.from(9999)),
      )).toText(),
      last.toWire().toText(),
    );
    await expectLater(
      engine(
        connection,
        saveEditor(editorContent('Further edit'), BigInt.from(10000)),
      ),
      throwsA(isA<EvaluationLimitReachedError>()),
    );
    expect(
      (await engine(connection, loadEditor())).toText(),
      last.toWire().toText(),
    );
  });

  test('connections share one recovered writer and retain publication receipt across runtime restart', () async {
    final first = runtime.connect(hello(author.id));
    final second = runtime.connect(hello(author.id));
    expect(first.welcome.serviceInstance, second.welcome.serviceInstance);
    expect(first.welcome.maxFrameBytes, BigInt.from(maxFrameBytes));
    expect(first.welcome.author, isTrue);
    await Future.wait([
      first.executeWriting(stage),
      second.executeWriting(stage),
    ]);
    final prepared = await first.executeWriting(
      AuthorWritingEngineRequest(
        universe: const Selector('World'),
        action: PrepareContractsWritingAction(
          candidate: draft.proposal.proposalId,
          label: 'Unit definition',
          text: 'Metres measure length.',
        ),
      ),
    );
    final fields = WireFields(prepared, {
      'acceptance_options',
      'summary',
      'candidate',
      'validation',
      'impact',
      'publishable',
      'review',
    });
    final ref = ProposalRef.fromWire(fields.require('candidate'));
    final review = await second.executeWriting(
      AuthorWritingEngineRequest(
        universe: const Selector('World'),
        action: InspectWritingAction(candidate: ref),
      ),
    );
    final validation = ValidationV3.fromWire(
      WireFields(review, {
        'acceptance_options',
        'summary',
        'candidate',
        'validation',
        'impact',
        'publishable',
        'review',
      }).require('validation'),
    );
    final publish = AuthorWritingEngineRequest(
      universe: const Selector('World'),
      action: PublishWritingAction(
        candidate: ref,
        validationRun: validation.execution!.runId,
        idempotencyKey: 'runtime-publication',
      ),
    );
    final response = await first.executeWriting(publish);
    final receipt = Envelope<CommitReceipt>.fromWire(
      response,
      CommitReceipt.fromWire,
    ).result;
    final oldInstance = first.welcome.serviceInstance;
    await runtime.close();
    expect(() => second.executeWriting(stage), throwsStateError);
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      expect(
        SqliteKernel(
          package.database,
          f.u,
        ).journal.head(frames.frame().continuity),
        receipt.revision,
      );
      expect(WorkflowStorage(package.database).keys('approval:'), hasLength(1));
    } finally {
      package.close();
    }
    runtime = NativeSqliteRuntime(authority: authority);
    final restarted = runtime.connect(hello(author.id));
    expect(restarted.welcome.serviceInstance, isNot(oldInstance));
    expect(
      (await restarted.executeWriting(publish)).toText(),
      response.toText(),
    );
  });

  test(
    'runtime shutdown drains admitted work before releasing package ownership',
    () async {
      final connection = runtime.connect(hello(author.id));
      final entered = Completer<void>(), release = Completer<void>();
      final held = authority.coordinate(author, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final pending = connection.executeWriting(stage);
      var closed = false;
      final shutdown = runtime.close().then((_) {
        closed = true;
      });
      await Future<void>.value();
      expect(closed, isFalse);
      expect(() => runtime.connect(hello(author.id)), throwsStateError);
      expect(() => connection.executeWriting(stage), throwsStateError);
      release.complete();
      await held;
      await pending;
      await shutdown;
      final package = OwnedSqliteDatabase.openExisting(path);
      try {
        package.recover();
        expect(
          WorkflowStorage(package.database).keys('source-version:'),
          hasLength(1),
        );
      } finally {
        package.close();
      }
    },
  );

  test(
    'failed worker open can retry without retaining a failed ownership slot',
    () async {
      final blocker = OwnedSqliteDatabase.openExisting(path);
      final connection = runtime.connect(hello(author.id));
      try {
        await expectLater(
          connection.executeWriting(stage),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        blocker.close();
      }
      final staged = WireFields(await connection.executeWriting(stage), {
        'canonical',
        'operations',
      });
      expect(staged.boolean('canonical'), isFalse);
    },
  );

  test(
    'handshake and current rights are checked before opening private workers',
    () async {
      expect(
        () => runtime.connect(hello(author.id, version: 'wrong')),
        throwsFormatException,
      );
      final connection = runtime.connect(hello(writer.id));
      await expectLater(
        connection.executeWriting(stage),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      authority.revoke(author, writer.id);
      await expectLater(
        connection.executeWriting(stage),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      final package = OwnedSqliteDatabase.openExisting(path);
      try {
        expect(WorkflowStorage(package.database).keys('source:'), isEmpty);
      } finally {
        package.close();
      }
      connection.close();
    },
  );
}
