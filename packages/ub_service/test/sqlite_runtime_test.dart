@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show sqlite3, OpenMode;
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
import 'writing_event_edits_test.dart' as event_edits;
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

  Future<WireFields> purgePreview(NativeSqliteConnection connection) async =>
      WireFields(
        await engine(
          connection,
          const PreviewPurgeEngineRequest(universe: Selector('World')),
        ),
        {'digest', 'impact'},
      );

  test('native purge preview binds exact retained impact and rejects stale workflow or confirmation', () async {
    final connection = runtime.connect(hello(author.id));
    final preview = await purgePreview(connection);
    final impact = WireFields(preview.require('impact'), {
      'universe_id',
      'heads',
      'revisions',
      'record_versions',
      'workflow_entries',
      'commit_receipts',
      'scope',
      'retained',
      'erasure',
    });
    expect(
      preview.string('digest'),
      canonicalDigest(preview.require('impact')),
    );
    expect(impact.string('universe_id'), f.u.value);
    expect(impact.require('revisions').toText(), '2');
    expect(impact.require('record_versions').toText(), '1');
    expect(impact.require('commit_receipts').toText(), '1');
    expect(impact.array('heads'), hasLength(1));
    expect(
      (await purgePreview(connection)).require('impact').toText(),
      preview.require('impact').toText(),
    );
    await expectLater(
      engine(
        connection,
        PurgeEngineRequest(
          universe: const Selector('World'),
          digest: preview.string('digest'),
          confirmation: 'PURGE world',
        ),
      ),
      throwsFormatException,
    );
    await engine(connection, stage);
    final changed = await purgePreview(connection);
    expect(changed.string('digest'), isNot(preview.string('digest')));
    await expectLater(
      engine(
        connection,
        PurgeEngineRequest(
          universe: const Selector('World'),
          digest: preview.string('digest'),
          confirmation: 'PURGE World',
        ),
      ),
      throwsFormatException,
    );
    expect(File(path).existsSync(), isTrue);
    expect(authority.catalog(author), hasLength(1));
    expect(
      installation.audit(author.id).where((entry) => entry.action == 'purge'),
      isEmpty,
    );
  });

  test('native purge rolls back installation retirement when its audit write fails', () async {
    final connection = runtime.connect(hello(author.id));
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
    final preview = await purgePreview(connection);
    final db = sqlite3.open(
      '${root.path}/installation.sqlite',
      mode: OpenMode.readWrite,
    );
    try {
      db.execute(
        "CREATE TRIGGER reject_purge BEFORE INSERT ON audit WHEN NEW.action='purge' BEGIN SELECT RAISE(ABORT, 'Disposable purge failure'); END",
      );
    } finally {
      db.close();
    }
    final request = PurgeEngineRequest(
      universe: const Selector('World'),
      digest: preview.string('digest'),
      confirmation: 'PURGE World',
    );
    await expectLater(
      engine(connection, request),
      throwsA(isA<InstallationException>()),
    );
    expect(authority.catalog(author), hasLength(1));
    expect(authority.grants(author), hasLength(1));
    expect(File(path).existsSync(), isTrue);
    await engine(
      connection,
      const LibraryEngineRequest(universe: Selector('World')),
    );
    final repaired = sqlite3.open(
      '${root.path}/installation.sqlite',
      mode: OpenMode.readWrite,
    );
    try {
      expect(
        repaired.select('SELECT count(*) AS n FROM purge_pending').single['n'],
        0,
      );
      repaired.execute('DROP TRIGGER reject_purge');
    } finally {
      repaired.close();
    }
    await engine(connection, request);
    expect(authority.catalog(author), isEmpty);
    expect(File(path).existsSync(), isFalse);
  });

  test(
    'native purge denies fully granted writers before opening a worker',
    () async {
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
      final blocker = OwnedSqliteDatabase.openExisting(path);
      try {
        final connection = runtime.connect(hello(writer.id));
        for (final request in <EngineRequest>[
          const PreviewPurgeEngineRequest(universe: Selector('World')),
          const PurgeEngineRequest(
            universe: Selector('World'),
            digest: 'denied',
            confirmation: 'PURGE World',
          ),
        ]) {
          await expectLater(
            engine(connection, request),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
        }
      } finally {
        blocker.close();
      }
      expect(File(path).existsSync(), isTrue);
      expect(authority.catalog(author), hasLength(1));
    },
  );

  test('native confirmed purge removes all local package access while retaining external backup and installation identity', () async {
    final connection = runtime.connect(hello(author.id));
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: [WorldId.generate()],
        propose: true,
        edit: true,
        protected: true,
        limits: GrantLimits(
          entities: [RecordId.generate()],
          predicates: [RecordId.generate()],
          continuities: [frames.frame().continuity],
        ),
      ),
    );
    final backup = '${root.path}/external-backup.sqlite';
    await engine(
      connection,
      BackupEngineRequest(
        universe: const Selector('World'),
        destination: backup,
      ),
    );
    final original = File(backup).readAsBytesSync();
    await engine(
      connection,
      RenameUniverseEngineRequest(universeId: f.u, name: 'Campaign'),
    );
    final preview = await purgePreview(connection);
    await expectLater(
      engine(
        connection,
        PurgeEngineRequest(
          universe: const Selector('World'),
          digest: preview.string('digest'),
          confirmation: 'PURGE World',
        ),
      ),
      throwsFormatException,
    );
    final result = WireFields(
      await engine(
        connection,
        PurgeEngineRequest(
          universe: const Selector('World'),
          digest: preview.string('digest'),
          confirmation: 'PURGE Campaign',
        ),
      ),
      {'purged', 'external_copies_removed'},
    );
    expect(result.string('purged'), f.u.value);
    expect(result.boolean('external_copies_removed'), isFalse);
    for (final suffix in ['', '-wal', '-shm']) {
      expect(File('$path$suffix').existsSync(), isFalse);
    }
    expect(File(backup).readAsBytesSync(), orderedEquals(original));
    expect(authority.catalog(author), isEmpty);
    expect(authority.grants(author), isEmpty);
    expect(installation.audit(author.id).last.action, 'purge');
    expect(installation.audit(author.id).last.target, f.u.value);
    for (final name in ['World', 'Campaign']) {
      await expectLater(
        engine(connection, LibraryEngineRequest(universe: Selector(name))),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    }
    final db = sqlite3.open(
      '${root.path}/installation.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      for (final table in [
        'catalog',
        'aliases',
        'grants',
        'grant_worlds',
        'grant_entities',
        'grant_predicates',
        'grant_continuities',
        'purge_pending',
      ]) {
        expect(db.select('SELECT count(*) AS n FROM $table').single['n'], 0);
      }
      expect(db.select('SELECT count(*) AS n FROM profiles').single['n'], 2);
    } finally {
      db.close();
    }
    await runtime.close();
    installation.close();
    installation = SqliteInstallationStore.openExisting(root.path);
    authority = InstallationAuthority(installation);
    author = authority.authenticateHello(hello(author.id));
    runtime = NativeSqliteRuntime(authority: authority);
    expect(authority.catalog(author), isEmpty);
    final restored = WireFields(
      await engine(
        runtime.connect(hello(author.id)),
        RestoreEngineRequest(source: backup, name: 'World'),
      ),
      {'universe_id', 'name', 'restored'},
    );
    expect(restored.string('universe_id'), f.u.value);
    expect(restored.boolean('restored'), isTrue);
    expect(authority.catalog(author), hasLength(1));
  });

  ({UniverseId id, String source, ContinuityId continuity, RevisionId revision})
  restoreSource() {
    final id = UniverseId.generate();
    final continuity = ContinuityId.generate();
    final source = '${root.path}/restore-source-${id.value}.sqlite';
    final package = OwnedSqliteDatabase.create(
      '${root.path}/source-${id.value}/package.sqlite',
    );
    try {
      final journal = SqliteJournal(package.database, id);
      package.database.execute('BEGIN IMMEDIATE');
      journal.initialize('Restore fixture', continuity, PrincipalId.generate());
      package.database.execute('COMMIT');
      final revision = journal.head(continuity);
      package.backup(source);
      return (
        id: id,
        source: source,
        continuity: continuity,
        revision: revision,
      );
    } finally {
      package.close();
    }
  }

  void expectNoRestoreStages() {
    expect(
      Directory('${root.path}/packages').listSync().where(
        (entry) => entry.uri.pathSegments.any(
          (part) =>
              part.startsWith('.restore-') ||
              part.startsWith('.universe-backup-'),
        ),
      ),
      isEmpty,
    );
  }

  test(
    'native restore publishes recovered identity and catalog across restart',
    () async {
      final fixture = restoreSource();
      final original = File(fixture.source).readAsBytesSync();
      final result = WireFields(
        await engine(
          runtime.connect(hello(author.id)),
          RestoreEngineRequest(source: fixture.source, name: 'Restored'),
        ),
        {'universe_id', 'name', 'restored'},
      );
      expect(result.string('universe_id'), fixture.id.value);
      expect(result.string('name'), 'Restored');
      expect(result.boolean('restored'), isTrue);
      expect(
        authority.catalog(author).map((entry) => entry.universeId),
        contains(fixture.id),
      );
      expectNoRestoreStages();
      expect(File(fixture.source).readAsBytesSync(), orderedEquals(original));
      await runtime.close();
      final restored = OwnedSqliteDatabase.openExisting(
        '${root.path}/packages/${fixture.id.value}.sqlite',
      );
      try {
        restored.recover();
        expect(restored.universeId, fixture.id);
        expect(
          SqliteJournal(restored.database, fixture.id).head(fixture.continuity),
          fixture.revision,
        );
      } finally {
        restored.close();
      }
      runtime = NativeSqliteRuntime(authority: authority);
      final catalog = WireFields(
        await engine(
          runtime.connect(hello(author.id)),
          const StatusEngineRequest(),
        ),
        {
          'service_instance',
          'principal',
          'author',
          'universes',
          'canonical_commit',
          'max_requests_per_principal',
          'universe_queue_capacity',
        },
      );
      expect(
        CanonicalArray(catalog.array('universes')).toText(),
        contains(fixture.id.value),
      );
      await engine(
        runtime.connect(hello(author.id)),
        const LibraryEngineRequest(universe: Selector('Restored')),
      );
    },
  );

  test('native restore rejects identity and historical name reservations without changing originals', () async {
    final connection = runtime.connect(hello(author.id));
    final backup = '${root.path}/registered-backup.sqlite';
    await engine(
      connection,
      BackupEngineRequest(
        universe: const Selector('World'),
        destination: backup,
      ),
    );
    final bytes = File(backup).readAsBytesSync();
    await expectLater(
      engine(
        connection,
        RestoreEngineRequest(source: backup, name: 'New name'),
      ),
      throwsA(isA<NameUnavailableError>()),
    );
    final fixture = restoreSource();
    final sourceBytes = File(fixture.source).readAsBytesSync();
    await engine(
      connection,
      RenameUniverseEngineRequest(universeId: f.u, name: 'Campaign'),
    );
    for (final name in ['World', 'Campaign']) {
      await expectLater(
        engine(
          connection,
          RestoreEngineRequest(source: fixture.source, name: name),
        ),
        throwsA(isA<NameUnavailableError>()),
      );
    }
    expect(authority.catalog(author), hasLength(1));
    expect(
      File('${root.path}/packages/${fixture.id.value}.sqlite').existsSync(),
      isFalse,
    );
    expect(File(backup).readAsBytesSync(), orderedEquals(bytes));
    expect(File(fixture.source).readAsBytesSync(), orderedEquals(sourceBytes));
    expectNoRestoreStages();
  });

  test('native restore denies writers before source IO and refuses destination overwrite', () async {
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
      engine(
        runtime.connect(hello(writer.id)),
        RestoreEngineRequest(
          source: '${root.path}/absent/source.sqlite',
          name: 'Denied',
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final fixture = restoreSource();
    final destination = File('${root.path}/packages/${fixture.id.value}.sqlite')
      ..writeAsStringSync('Unregistered original');
    final connection = runtime.connect(hello(author.id));
    await expectLater(
      engine(
        connection,
        RestoreEngineRequest(source: fixture.source, name: 'Blocked'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(destination.readAsStringSync(), 'Unregistered original');
    expect(authority.catalog(author), hasLength(1));
    expectNoRestoreStages();
    destination.deleteSync();
    final target = File('${root.path}/link-target')
      ..writeAsStringSync('Link original');
    final link = Link(destination.path)..createSync(target.path);
    await expectLater(
      engine(
        connection,
        RestoreEngineRequest(source: fixture.source, name: 'Blocked'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(link.targetSync(), target.path);
    expect(target.readAsStringSync(), 'Link original');
    expect(authority.catalog(author), hasLength(1));
    expectNoRestoreStages();
  });

  test('native restore removes only its newly published copy after registration failure and can retry', () async {
    final fixture = restoreSource();
    final original = File(fixture.source).readAsBytesSync();
    final catalogPath = '${root.path}/installation.sqlite';
    final database = sqlite3.open(catalogPath, mode: OpenMode.readWrite);
    try {
      database.execute(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON catalog BEGIN SELECT RAISE(ABORT, 'Disposable registration failure'); END",
      );
    } finally {
      database.close();
    }
    final request = RestoreEngineRequest(source: fixture.source, name: 'Retry');
    final connection = runtime.connect(hello(author.id));
    await expectLater(
      engine(connection, request),
      throwsA(
        isA<InstallationException>().having(
          (error) => error.failure,
          'failure',
          InstallationFailure.unavailable,
        ),
      ),
    );
    for (final suffix in [
      '.sqlite',
      '.sqlite-wal',
      '.sqlite-shm',
      '.writer.lock',
    ]) {
      expect(
        File('${root.path}/packages/${fixture.id.value}$suffix').existsSync(),
        isFalse,
      );
    }
    expect(authority.catalog(author), hasLength(1));
    expect(File(fixture.source).readAsBytesSync(), orderedEquals(original));
    expectNoRestoreStages();
    final repaired = sqlite3.open(catalogPath, mode: OpenMode.readWrite);
    try {
      repaired.execute('DROP TRIGGER reject_restore');
    } finally {
      repaired.close();
    }
    await engine(connection, request);
    expect(authority.catalog(author), hasLength(2));
    await engine(
      connection,
      const LibraryEngineRequest(universe: Selector('Retry')),
    );
  });

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

  test('native continuity forks pin history and prepare explicit adoption through exact approval and receipt recovery', () async {
    final original = f.row(20, permissions.entity(labels: {'en': 'Original'}));
    final removed = f.row(21, f.entity());
    seedReadRows([original, removed]);
    var connection = runtime.connect(hello(author.id));
    final base = (await readContext(connection)).frame.revision;
    final branch = ContinuityId.generate();
    final parent = draft.proposal.baseFrame.continuity;
    final fork = ForkContinuityEngineRequest(
      universe: const Selector('World'),
      name: 'Alternate campaign',
      continuityId: branch,
      source: parent,
      revision: base,
    );
    final forkResponse = await engine(connection, fork);
    final forkRevision = RevisionId.parse(
      WireFields(forkResponse, {
        'continuity_id',
        'revision',
      }).string('revision'),
    );
    expect((await engine(connection, fork)).toText(), forkResponse.toText());
    await runtime.close();
    final changed = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: original.identity,
      payload: permissions.entity(labels: {'en': 'Changed'}),
    );
    final added = f.row(22, f.entity());
    final package = OwnedSqliteDatabase.openExisting(path);
    late RevisionId advanced;
    try {
      package.recover();
      final kernel = SqliteKernel(package.database, f.u);
      advanced = kernel.commit(
        CommitInput(
          universe: f.u,
          continuity: parent,
          expectedHead: base,
          principal: PrincipalId.generate(),
          decision: 'Admitted fixture',
          reason: 'Alternate branch edits',
          idempotencyKey: 'continuity-edits',
          changes: [
            Assignment(
              recordId: original.identity.recordId,
              expected: original.recordVersionId,
              next: StoredVersion.build(
                changed.recordVersionId,
                changed.identity,
                changed.payload.toWire(),
              ),
            ),
            Assignment(
              recordId: removed.identity.recordId,
              expected: removed.recordVersionId,
            ),
            Assignment(
              recordId: added.identity.recordId,
              next: StoredVersion.build(
                added.recordVersionId,
                added.identity,
                added.payload.toWire(),
              ),
            ),
          ],
        ),
      );
      expect(kernel.journal.head(branch), forkRevision);
    } finally {
      package.close();
    }
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    expect((await engine(connection, fork)).toText(), forkResponse.toText());
    await expectLater(
      engine(
        connection,
        ForkContinuityEngineRequest(
          universe: const Selector('World'),
          name: fork.name,
          continuityId: branch,
          source: parent,
          revision: advanced,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    final comparison = CompareContinuitiesEngineRequest(
      universe: const Selector('World'),
      target: branch,
      targetRevision: forkRevision,
      source: parent,
      sourceRevision: advanced,
    );
    final compared = await engine(connection, comparison);
    final differences = WireFields(compared, {
      'differences',
      'target_revision',
      'source_revision',
    }).array('differences');
    expect(
      differences.map(
        (d) => WireFields(d, {
          'record_id',
          'kind',
          'target_version',
          'source_version',
        }).string('record_id'),
      ),
      [f.id(20).value, f.id(21).value, f.id(22).value],
    );
    final selection = PrepareAdoptionEngineRequest(
      universe: const Selector('World'),
      target: branch,
      targetRevision: forkRevision,
      source: parent,
      sourceRevision: advanced,
      recordIds: [f.id(22), f.id(20), f.id(21), f.id(99)],
    );
    final prepared = await engine(connection, selection);
    final operations = WireFields(prepared, {
      'operations',
      'target_revision',
      'source_revision',
    }).array('operations').map(DomainOperation.fromWire).toList();
    expect(operations, hasLength(3));
    expect(
      (operations[0] as AdoptRecordVersionOperation).expectedVersion,
      isNull,
    );
    expect(
      (operations[1] as AdoptRecordVersionOperation).source.recordVersionId,
      changed.recordVersionId,
    );
    expect(
      (operations[1] as AdoptRecordVersionOperation).expectedVersion,
      original.recordVersionId,
    );
    expect(
      (operations[2] as TombstoneRecordOperation).expectedVersion,
      removed.recordVersionId,
    );
    final opened = OpenedContext.fromWire(
      (await tool(
        connection,
        OpenContextRequest(
          universe: const Selector('World'),
          continuityId: branch,
          revision: const HeadRevisionSelector(),
          representedContext: ContextIdSelector(f.id(99)),
          temporalQuery: const TimelessFrameTime(),
          temporalSystems: [],
          perspective: const AuthorPerspective(),
        ),
      )).result,
    );
    expect(opened.frame.revision, forkRevision);
    final proposal = Proposal.fromWire(
      (await tool(
        connection,
        CreateProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          operations: operations,
          submission: Submission.submitted,
          rationale: 'Explicitly selected campaign changes',
          idempotencyKey: 'adoption-create',
        ),
      )).result,
    );
    final ref = ProposalRef(
      proposalId: proposal.proposalId,
      version: proposal.version,
      digest: proposal.digest,
    );
    final checked = ValidationV3.fromWire(
      (await tool(
        connection,
        ProposalValidationRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: ref,
          checkScope: CheckScope.candidate,
        ),
      )).result,
    ) as EvaluatedValidation;
    final publish = CommitRequest(
      universe: const Selector('World'),
      proposalReference: ref,
      expectedBaseRevision: forkRevision,
      validationRun: checked.execution.runId,
      idempotencyKey: 'adoption-publish',
    );
    await expectLater(
      tool(connection, publish),
      throwsA(isA<ApprovalRequiredError>()),
    );
    await engine(
      connection,
      ApproveEngineRequest(
        universe: const Selector('World'),
        proposalReference: ref,
        validationRun: checked.execution.runId,
      ),
    );
    final receipt = await tool(connection, publish);
    final publishedRevision = CommitReceipt.fromWire(receipt.result).revision;
    final equal = await engine(
      connection,
      CompareContinuitiesEngineRequest(
        universe: const Selector('World'),
        target: branch,
        targetRevision: publishedRevision,
        source: parent,
        sourceRevision: advanced,
      ),
    );
    expect(
      WireFields(equal, {
        'differences',
        'target_revision',
        'source_revision',
      }).array('differences'),
      isEmpty,
    );
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    expect(
      (await tool(connection, publish)).toWire((v) => v).toText(),
      receipt.toWire((v) => v).toText(),
    );
    expect((await engine(connection, fork)).toText(), forkResponse.toText());
    expect((await engine(connection, comparison)).toText(), compared.toText());
    expect((await engine(connection, selection)).toText(), prepared.toText());
  });

  test('native continuity routes enforce author authority names pinned revisions and selection limits', () async {
    final parent = draft.proposal.baseFrame.continuity;
    final base = draft.proposal.baseFrame.revision;
    final branch = ContinuityId.generate();
    ForkContinuityEngineRequest fork(String name, {RevisionId? revision}) =>
        ForkContinuityEngineRequest(
          universe: const Selector('World'),
          name: name,
          continuityId: branch,
          source: parent,
          revision: revision ?? base,
        );
    CompareContinuitiesEngineRequest compare() =>
        CompareContinuitiesEngineRequest(
          universe: const Selector('World'),
          target: parent,
          targetRevision: base,
          source: parent,
          sourceRevision: base,
        );
    PrepareAdoptionEngineRequest prepare(List<RecordId> ids) =>
        PrepareAdoptionEngineRequest(
          universe: const Selector('World'),
          target: parent,
          targetRevision: base,
          source: parent,
          sourceRevision: base,
          recordIds: ids,
        );
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
      for (final request in [
        fork('Denied'),
        compare(),
        prepare([f.id(99)]),
      ]) {
        await expectLater(
          engine(writerConnection, request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      }
    } finally {
      blocker.close();
    }
    final connection = runtime.connect(hello(author.id));
    for (final name in ['   ', '😀' * 33]) {
      await expectLater(
        engine(connection, fork(name)),
        throwsA(
          isA<InvalidArgumentError>().having((e) => e.field, 'field', 'name'),
        ),
      );
    }
    await expectLater(
      engine(
        connection,
        fork('Missing source', revision: RevisionId.generate()),
      ),
      throwsA(isA<FormatException>()),
    );
    final saved = await engine(connection, fork('😀' * 32));
    expect(
      (await engine(connection, fork('😀' * 32))).toText(),
      saved.toText(),
    );
    for (final ids in [<RecordId>[], List.filled(101, f.id(99))]) {
      await expectLater(
        engine(connection, prepare(ids)),
        throwsA(
          isA<InvalidArgumentError>().having(
            (e) => e.field,
            'field',
            'record_ids',
          ),
        ),
      );
    }
    await expectLater(
      engine(connection, prepare([RecordId.generate()])),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final unchanged = await engine(
      connection,
      prepare(List.filled(100, f.id(99))),
    );
    expect(
      WireFields(unchanged, {
        'operations',
        'target_revision',
        'source_revision',
      }).array('operations'),
      isEmpty,
    );
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      expect(SqliteKernel(package.database, f.u).journal.head(parent), base);
      expect(WorkflowStorage(package.database).keys('proposal:'), hasLength(1));
      expect(WorkflowStorage(package.database).keys('approval:'), isEmpty);
    } finally {
      package.close();
    }
  });

  test('native continuity comparison omits generated assertions while preserving explicit selection order', () async {
    final rows = event_edits.base();
    seedReadRows(rows);
    final connection = runtime.connect(hello(author.id));
    final parent = draft.proposal.baseFrame.continuity;
    final base = (await readContext(connection)).frame.revision;
    final branch = ContinuityId.generate();
    final saved = await engine(
      connection,
      ForkContinuityEngineRequest(
        universe: const Selector('World'),
        name: 'Before event',
        continuityId: branch,
        source: parent,
        revision: base,
      ),
    );
    final revision = RevisionId.parse(
      WireFields(saved, {'continuity_id', 'revision'}).string('revision'),
    );
    await runtime.close();
    final candidate = event_edits.occurred(rows);
    final added = candidate
        .where(
          (r) =>
              !rows.any((old) => old.identity.recordId == r.identity.recordId),
        )
        .toList();
    final generated = added
        .where(
          (r) =>
              r.payload is AssertionRecord &&
              (r.payload as AssertionRecord).establishedBy != null,
        )
        .single;
    seedReadRows(added);
    runtime = NativeSqliteRuntime(authority: authority);
    final restarted = runtime.connect(hello(author.id));
    final head = (await readContext(restarted)).frame.revision;
    final result = await engine(
      restarted,
      CompareContinuitiesEngineRequest(
        universe: const Selector('World'),
        target: branch,
        targetRevision: revision,
        source: parent,
        sourceRevision: head,
      ),
    );
    final differences = WireFields(result, {
      'differences',
      'target_revision',
      'source_revision',
    }).array('differences');
    final changedIds = differences
        .map(
          (d) => WireFields(d, {
            'record_id',
            'kind',
            'target_version',
            'source_version',
          }).string('record_id'),
        )
        .toList();
    expect(changedIds, isNot(contains(generated.identity.recordId.value)));
    expect(
      changedIds,
      containsAll(
        added
            .where((r) => r.payload is! AssertionRecord)
            .map((r) => r.identity.recordId.value),
      ),
    );
    final selected = added.firstWhere((r) => r.payload is EventRecord);
    final prepared = await engine(
      restarted,
      PrepareAdoptionEngineRequest(
        universe: const Selector('World'),
        target: branch,
        targetRevision: revision,
        source: parent,
        sourceRevision: head,
        recordIds: [selected.identity.recordId, selected.identity.recordId],
      ),
    );
    final operations = WireFields(prepared, {
      'operations',
      'target_revision',
      'source_revision',
    }).array('operations');
    expect(operations, hasLength(2));
    expect(operations.first.toText(), operations.last.toText());
  });

  test('native continuity comparison accepts one thousand differences and refuses larger results', () async {
    final parent = draft.proposal.baseFrame.continuity;
    final originalBase = draft.proposal.baseFrame.revision;
    final rows = [for (var n = 200; n <= 1200; n++) f.row(n, f.entity())];
    final setup = OwnedSqliteDatabase.openExisting(path);
    try {
      setup.recover();
      final kernel = SqliteKernel(setup.database, f.u);
      for (var offset = 0; offset < rows.length; offset += 100) {
        kernel.commit(
          CommitInput(
            universe: f.u,
            continuity: parent,
            expectedHead: kernel.journal.head(parent),
            principal: PrincipalId.generate(),
            decision: 'Admitted fixture',
            reason: 'Comparison boundary records',
            idempotencyKey: 'comparison-fixture-$offset',
            changes: [
              for (final row in rows.skip(offset).take(100))
                Assignment(
                  recordId: row.identity.recordId,
                  next: StoredVersion.build(
                    row.recordVersionId,
                    row.identity,
                    row.payload.toWire(),
                  ),
                ),
            ],
          ),
        );
      }
    } finally {
      setup.close();
    }
    final connection = runtime.connect(hello(author.id));
    final head = (await readContext(connection)).frame.revision;
    final branch = ContinuityId.generate();
    final forked = await engine(
      connection,
      ForkContinuityEngineRequest(
        universe: const Selector('World'),
        name: 'Comparison target',
        continuityId: branch,
        source: parent,
        revision: originalBase,
      ),
    );
    final initial = RevisionId.parse(
      WireFields(forked, {'continuity_id', 'revision'}).string('revision'),
    );
    CompareContinuitiesEngineRequest compare(RevisionId target) =>
        CompareContinuitiesEngineRequest(
          universe: const Selector('World'),
          target: branch,
          targetRevision: target,
          source: parent,
          sourceRevision: head,
        );
    await expectLater(
      engine(connection, compare(initial)),
      throwsA(isA<EvaluationLimitReachedError>()),
    );
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    late RevisionId target;
    try {
      package.recover();
      final row = rows.first;
      target = SqliteKernel(package.database, f.u).commit(
        CommitInput(
          universe: f.u,
          continuity: branch,
          expectedHead: initial,
          principal: PrincipalId.generate(),
          decision: 'Admitted fixture',
          reason: 'One common record',
          idempotencyKey: 'comparison-boundary',
          changes: [
            Assignment(
              recordId: row.identity.recordId,
              next: StoredVersion.build(
                RecordVersionId.generate(),
                row.identity,
                row.payload.toWire(),
              ),
            ),
          ],
        ),
      );
    } finally {
      package.close();
    }
    runtime = NativeSqliteRuntime(authority: authority);
    final result = await engine(
      runtime.connect(hello(author.id)),
      compare(target),
    );
    expect(
      WireFields(result, {
        'differences',
        'target_revision',
        'source_revision',
      }).array('differences'),
      hasLength(1000),
    );
  });

  Future<WireFields> library(NativeSqliteConnection connection) async =>
      WireFields(
        await engine(
          connection,
          const LibraryEngineRequest(universe: Selector('World')),
        ),
        {'storage', 'worlds', 'contexts', 'continuities', 'writing'},
      );

  Future<WireFields> doctor(NativeSqliteConnection connection) async =>
      WireFields(await engine(connection, const DoctorEngineRequest()), {
        'service_instance',
        'packages',
        'profile_storage',
        'recovery',
        'admission',
      });

  test('native package health retains author-only redacted status and recovers a locked package on retry', () async {
    final other = UniverseId.generate();
    final continuity = ContinuityId.generate();
    final otherPath = '${root.path}/packages/healthy.sqlite';
    final setup = OwnedSqliteDatabase.create(otherPath);
    try {
      setup.database.execute('BEGIN IMMEDIATE');
      SqliteJournal(
        setup.database,
        other,
      ).initialize('Healthy fixture', continuity, PrincipalId.generate());
      setup.database.execute('COMMIT');
    } finally {
      setup.close();
    }
    authority.registerUniverse(author, name: 'Healthy', path: otherPath);
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
    final blocked = OwnedSqliteDatabase.openExisting(path);
    final connection = runtime.connect(hello(author.id));
    late WireFields first;
    try {
      await expectLater(
        doctor(runtime.connect(hello(writer.id))),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      first = await doctor(connection);
      expect(first.string('service_instance'), runtime.instance.value);
      expect(
        first.string('profile_storage'),
        'installation-only protected files',
      );
      expect(
        first.string('recovery'),
        'immutable history replay; atomic projection rebuild',
      );
      expect(
        first.require('admission').toText(),
        '{"connections":32,"queue_per_universe":16,"requests_per_principal":8}',
      );
      final entries = first.array('packages');
      expect(entries, hasLength(2));
      final failed = entries.singleWhere(
        (v) =>
            WireFields(v, {'id', 'storage', 'error'}).string('id') == f.u.value,
      );
      expect(
        WireFields(failed, {'id', 'error'}).string('error'),
        'package unavailable: check file ownership, writer lock, schema version, and integrity',
      );
      final healthy = WireFields(
        entries.singleWhere(
          (v) =>
              WireFields(v, {'id', 'storage', 'error'}).string('id') ==
              other.value,
        ),
        {'id', 'storage'},
      );
      expect(
        WireFields(healthy.require('storage'), {
          'universe',
          'sqlite_version',
          'journal_mode',
          'synchronous',
          'foreign_keys',
          'heads',
        }).string('universe'),
        other.value,
      );
      expect(
        CanonicalObject([
          for (final f in ['packages', 'admission'])
            MapEntry(f, first.require(f)),
        ]).toText(),
        isNot(contains(root.path)),
      );
    } finally {
      blocked.close();
    }
    final recovered = await doctor(connection);
    expect(recovered.array('packages'), hasLength(2));
    final entry = WireFields(
      recovered
          .array('packages')
          .singleWhere(
            (v) => WireFields(v, {'id', 'storage'}).string('id') == f.u.value,
          ),
      {'id', 'storage'},
    );
    expect(
      entry.require('storage').toText(),
      (await library(connection)).require('storage').toText(),
    );
    expect(
      (await doctor(connection)).require('packages').toText(),
      recovered.require('packages').toText(),
    );
    await runtime.close();
    final available = OwnedSqliteDatabase.openExisting(path);
    try {
      available.recover();
      expect(
        SqliteJournal(
          available.database,
          f.u,
        ).head(draft.proposal.baseFrame.continuity),
        draft.proposal.baseFrame.revision,
      );
    } finally {
      available.close();
    }
    final priorInstance = recovered.string('service_instance');
    runtime = NativeSqliteRuntime(authority: authority);
    final restarted = await doctor(runtime.connect(hello(author.id)));
    expect(restarted.string('service_instance'), isNot(priorInstance));
    expect(
      restarted.require('packages').toText(),
      recovered.require('packages').toText(),
    );
  });

  test('native package health fails closed on missing or corrupt packages without retaining a failed worker', () async {
    final connection = runtime.connect(hello(author.id));
    final moved = File(path).renameSync('$path.saved');
    final missing = await doctor(connection);
    final missingEntry = WireFields(missing.array('packages').single, {
      'id',
      'error',
    });
    expect(missingEntry.string('id'), f.u.value);
    expect(File(path).existsSync(), isFalse);
    moved.renameSync(path);
    final setup = OwnedSqliteDatabase.openExisting(path);
    late String digest;
    late int generation;
    try {
      setup.recover();
      digest =
          setup.database.select(
                'SELECT digest FROM workflow_entries WHERE key=?',
                [draft.key],
              ).single['digest']
              as String;
      generation =
          setup.database
                  .select('SELECT generation FROM projection_state')
                  .single['generation']
              as int;
      setup.database.execute('DROP TRIGGER workflow_entries_no_update');
      setup.database.execute(
        'UPDATE workflow_entries SET digest=? WHERE key=?',
        ['0' * 64, draft.key],
      );
    } finally {
      setup.close();
    }
    final corrupt = await doctor(connection);
    expect(
      corrupt.require('packages').toText(),
      missing.require('packages').toText(),
    );
    final repair = OwnedSqliteDatabase.openExisting(path);
    try {
      expect(
        repair.database
            .select('SELECT generation FROM projection_state')
            .single['generation'],
        generation,
      );
      repair.database.execute(
        'UPDATE workflow_entries SET digest=? WHERE key=?',
        [digest, draft.key],
      );
    } finally {
      repair.close();
    }
    final healthy = await doctor(connection);
    final entry = WireFields(healthy.array('packages').single, {
      'id',
      'storage',
    });
    expect(entry.string('id'), f.u.value);
    expect(
      entry.require('storage').toText(),
      (await library(connection)).require('storage').toText(),
    );
  });

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

  test('native maintenance collects only snapshot caches and retains drafts sources approvals history and publication receipts', () async {
    final imageBytes = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
    );
    late ImageAssetRecord image;
    final setup = OwnedSqliteDatabase.openExisting(path);
    try {
      setup.recover();
      image = SqliteKernel(
        setup.database,
        f.u,
      ).stageImageBytes(imageBytes, 'Retained.png').asset;
      final journal = SqliteJournal(setup.database, f.u);
      final base = draft.proposal.baseFrame;
      final members = journal.snapshot(base.continuity, base.revision);
      setup.database.execute('BEGIN IMMEDIATE');
      setup.database.execute('INSERT INTO snapshot_membership VALUES(?,?,?)', [
        f.u.value,
        base.revision.value,
        canonicalDigest(
          CanonicalObject([
            for (final e in members.entries)
              MapEntry(e.key.value, CanonicalString(e.value.value)),
          ]),
        ),
      ]);
      for (final e in members.entries) {
        setup.database.execute('INSERT INTO snapshot_member VALUES(?,?,?,?)', [
          f.u.value,
          base.revision.value,
          e.key.value,
          e.value.value,
        ]);
      }
      setup.database.execute('COMMIT');
    } finally {
      setup.close();
    }
    var connection = runtime.connect(hello(author.id));
    final opened = await readContext(connection);
    final submitted = Proposal.fromWire(
      (await tool(
        connection,
        SubmitProposalRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: draft.reference,
          idempotencyKey: 'maintenance-submit',
        ),
      )).result,
    );
    final reference = ProposalRef(
      proposalId: submitted.proposalId,
      version: submitted.version,
      digest: submitted.digest,
    );
    final checked = ValidationV3.fromWire(
      (await tool(
        connection,
        ProposalValidationRequest(
          universe: const Selector('World'),
          contextId: opened.contextId,
          proposalReference: reference,
          checkScope: CheckScope.candidate,
        ),
      )).result,
    ) as EvaluatedValidation;
    await engine(
      connection,
      ApproveEngineRequest(
        universe: const Selector('World'),
        proposalReference: reference,
        validationRun: checked.execution.runId,
      ),
    );
    final publish = CommitRequest(
      universe: const Selector('World'),
      proposalReference: reference,
      expectedBaseRevision: opened.frame.revision,
      validationRun: checked.execution.runId,
      idempotencyKey: 'maintenance-publish',
    );
    final published = await tool(connection, publish);
    final savedDraft = await engine(
      connection,
      saveEditor(editorContent('Retained unfinished text'), BigInt.zero),
    );
    final stagedSource = await engine(connection, stage);
    const fields = {
      'retention_policy',
      'retained_record_versions',
      'retained_revisions',
      'retained_commit_receipts',
      'retained_workflow_entries',
      'retained_source_assets',
      'eligible_snapshot_caches',
      'collected_snapshot_caches',
      'source_assets_collected',
      'backup_pins',
      'canonical',
    };
    Future<WireFields> maintenance(bool collect) async => WireFields(
      await engine(
        connection,
        MaintainEngineRequest(
          universe: const Selector('World'),
          collect: collect,
        ),
      ),
      fields,
    );
    final beforeLibrary = await library(connection);
    final backupPath = '${root.path}/complete-backup.sqlite';
    final backupResult = WireFields(
      await engine(
        connection,
        BackupEngineRequest(
          universe: const Selector('World'),
          destination: backupPath,
        ),
      ),
      {'backup', 'universe_id', 'verified'},
    );
    expect(backupResult.string('backup'), backupPath);
    expect(backupResult.string('universe_id'), f.u.value);
    expect(backupResult.boolean('verified'), isTrue);
    final backup = OwnedSqliteDatabase.openExisting(backupPath);
    try {
      backup.recover();
      expect(
        SqliteJournal(backup.database, f.u).head(opened.frame.continuity),
        CommitReceipt.fromWire(published.result).revision,
      );
      final retained = WorkflowStorage(backup.database);
      expect(
        retained.get(retained.keys('draft:').single)!.toText(),
        savedDraft.toText(),
      );
      expect(retained.keys('approval:'), hasLength(1));
      expect(
        backup.database
            .select('SELECT count(*) AS n FROM operation_receipts')
            .single['n'],
        2,
      );
      expect(
        backup.database
            .select('SELECT utf8_content FROM source_content')
            .single['utf8_content'],
        orderedEquals(utf8.encode(stage.text)),
      );
      expect(
        SqliteKernel(backup.database, f.u).imageBytes(image),
        orderedEquals(imageBytes),
      );
      expect(
        SqliteJournal(
          backup.database,
          f.u,
        ).snapshot(opened.frame.continuity, opened.frame.revision),
        hasLength(1),
      );
    } finally {
      backup.close();
    }
    final restored = OwnedSqliteDatabase.stageRestore(
      backupPath,
      '${root.path}/packages',
    );
    final stagedPath = restored.package.path;
    try {
      final copy = restored.package;
      final workflow = WorkflowStorage(copy.database);
      expect(copy.universeId, f.u);
      expect(
        SqliteJournal(copy.database, f.u).head(opened.frame.continuity),
        CommitReceipt.fromWire(published.result).revision,
      );
      expect(
        workflow.get(workflow.keys('draft:').single)!.toText(),
        savedDraft.toText(),
      );
      expect(workflow.keys('approval:'), isEmpty);
      expect(workflow.keys('context:'), isEmpty);
      final historical =
          copy.database
                  .select(
                    "SELECT h.key FROM historical_workflow h JOIN workflow_entries w ON w.key=h.key WHERE w.family='ApprovalEvidence'",
                  )
                  .single['key']
              as String;
      expect(workflow.evidence(historical), isNotNull);
      expect(workflow.get(historical), isNull);
      expect(
        copy.database
            .select('SELECT count(*) AS n FROM operation_receipts')
            .single['n'],
        2,
      );
      expect(
        copy.database
            .select('SELECT count(*) AS n FROM historical_receipt')
            .single['n'],
        2,
      );
      expect(
        copy.database
            .select(
              'SELECT count(*) AS n FROM operation_receipts r WHERE NOT EXISTS(SELECT 1 FROM historical_receipt h WHERE h.universe_id=r.universe_id AND h.principal=r.principal AND h.operation_kind=r.operation_kind AND h.idempotency_key=r.idempotency_key)',
            )
            .single['n'],
        0,
      );
      expect(
        copy.database
            .select('SELECT utf8_content FROM source_content')
            .single['utf8_content'],
        orderedEquals(utf8.encode(stage.text)),
      );
      expect(
        SqliteKernel(copy.database, f.u).imageBytes(image),
        orderedEquals(imageBytes),
      );
    } finally {
      restored.close();
    }
    restored.close();
    expect(File(stagedPath).existsSync(), isFalse);
    expect(File(backupPath).existsSync(), isTrue);
    final otherRoot = Directory('${root.path}/restored-installation');
    final otherInstallation = SqliteInstallationStore.create(otherRoot.path);
    final otherAuthority = InstallationAuthority(otherInstallation);
    final otherAuthor = otherAuthority.initializeAuthor();
    final otherHello = EngineHello(
      protocolVersion: protocolVersion,
      profileId: otherAuthor,
      credential: Credential(
        ProfileCredentialStore.read(root: otherRoot.path, profile: otherAuthor),
      ),
      clientName: 'Disposable restore client',
    );
    var otherRuntime = NativeSqliteRuntime(authority: otherAuthority);
    try {
      await engine(
        otherRuntime.connect(otherHello),
        RestoreEngineRequest(source: backupPath, name: 'World'),
      );
      final importedLibrary = await library(otherRuntime.connect(otherHello));
      for (final field in ['worlds', 'contexts', 'continuities']) {
        expect(
          importedLibrary.require(field).toText(),
          beforeLibrary.require(field).toText(),
        );
      }
      final importedWriting = WireFields(importedLibrary.require('writing'), {
        'approved',
        'proposals',
      });
      expect(importedWriting.array('approved'), isEmpty);
      expect(importedWriting.array('proposals'), hasLength(1));
      await otherRuntime.close();
      final imported = OwnedSqliteDatabase.openExisting(
        '${otherRoot.path}/packages/${f.u.value}.sqlite',
      );
      try {
        imported.recover();
        final retained = WorkflowStorage(imported.database);
        expect(retained.keys('approval:'), isEmpty);
        expect(retained.keys('context:'), isEmpty);
        expect(
          imported.database
              .select('SELECT count(*) AS n FROM historical_receipt')
              .single['n'],
          2,
        );
        expect(
          retained.get(retained.keys('draft:').single)!.toText(),
          savedDraft.toText(),
        );
        expect(
          imported.database
              .select('SELECT utf8_content FROM source_content')
              .single['utf8_content'],
          orderedEquals(utf8.encode(stage.text)),
        );
        expect(
          SqliteKernel(imported.database, f.u).imageBytes(image),
          orderedEquals(imageBytes),
        );
        expect(
          SqliteJournal(imported.database, f.u).head(opened.frame.continuity),
          CommitReceipt.fromWire(published.result).revision,
        );
      } finally {
        imported.close();
      }
      otherRuntime = NativeSqliteRuntime(authority: otherAuthority);
      final restartedLibrary = await library(otherRuntime.connect(otherHello));
      expect(
        restartedLibrary.require('continuities').toText(),
        importedLibrary.require('continuities').toText(),
      );
    } finally {
      await otherRuntime.close();
      otherInstallation.close();
    }
    final dry = await maintenance(false);
    expect(dry.string('retention_policy'), 'retain-all-history-v1');
    expect(dry.boolean('canonical'), isFalse);
    expect(dry.require('eligible_snapshot_caches').toText(), '1');
    expect(dry.require('collected_snapshot_caches').toText(), '0');
    expect(dry.require('retained_source_assets').toText(), '1');
    final collected = await maintenance(true);
    expect(collected.require('collected_snapshot_caches').toText(), '1');
    expect(collected.require('source_assets_collected').toText(), '0');
    for (final field in fields.where((f) => f != 'collected_snapshot_caches')) {
      expect(collected.require(field).toText(), dry.require(field).toText());
    }
    final afterLibrary = await library(connection);
    for (final field in [
      'storage',
      'worlds',
      'contexts',
      'continuities',
      'writing',
    ]) {
      expect(
        afterLibrary.require(field).toText(),
        beforeLibrary.require(field).toText(),
      );
    }
    expect(
      (await engine(connection, loadEditor())).toText(),
      savedDraft.toText(),
    );
    await runtime.close();
    runtime = NativeSqliteRuntime(authority: authority);
    connection = runtime.connect(hello(author.id));
    expect(
      (await tool(connection, publish)).toWire((v) => v).toText(),
      published.toWire((v) => v).toText(),
    );
    expect(
      (await engine(connection, loadEditor())).toText(),
      savedDraft.toText(),
    );
    final repeated = await maintenance(true);
    expect(repeated.require('eligible_snapshot_caches').toText(), '0');
    expect(repeated.require('collected_snapshot_caches').toText(), '0');
    await runtime.close();
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      expect(
        package.database.select('SELECT * FROM snapshot_membership'),
        isEmpty,
      );
      expect(package.database.select('SELECT * FROM snapshot_member'), isEmpty);
      expect(
        package.database
            .select('SELECT utf8_content FROM source_content')
            .single['utf8_content'],
        orderedEquals(utf8.encode(stage.text)),
      );
      final workflow = WorkflowStorage(package.database);
      final sourceVersion = workflow.keys('source-version:').single;
      final retained = workflow.get(sourceVersion)!;
      final stagedVersion =
          WireFields(stagedSource, {'canonical', 'operations'})
              .array('operations')
              .map(DomainOperation.fromWire)
              .whereType<RecordNarrativeReferenceOperation>()
              .singleWhere((op) => op.record == RecordKind.sourceVersion);
      expect(retained.toText(), stagedVersion.payload.toWire().toText());
      expect(stagedSource.toText(), contains(stage.label));
      expect(workflow.keys('approval:'), hasLength(1));
      expect(
        SqliteKernel(package.database, f.u).imageBytes(image),
        orderedEquals(imageBytes),
      );
      expect(
        SqliteJournal(
          package.database,
          f.u,
        ).snapshot(opened.frame.continuity, opened.frame.revision),
        hasLength(1),
      );
    } finally {
      package.close();
    }
  });

  test('native backup refuses writers and preserves existing destinations without leaving staging files', () async {
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
    final destination = File('${root.path}/existing-backup.sqlite')
      ..writeAsStringSync('Original file');
    final request = BackupEngineRequest(
      universe: const Selector('World'),
      destination: destination.path,
    );
    final blocker = OwnedSqliteDatabase.openExisting(path);
    try {
      await expectLater(
        engine(runtime.connect(hello(writer.id)), request),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    } finally {
      blocker.close();
    }
    final connection = runtime.connect(hello(author.id));
    await expectLater(
      engine(connection, request),
      throwsA(isA<FileSystemException>()),
    );
    expect(destination.readAsStringSync(), 'Original file');
    final link = Link('${root.path}/linked-backup.sqlite')
      ..createSync(destination.path);
    await expectLater(
      engine(
        connection,
        BackupEngineRequest(
          universe: const Selector('World'),
          destination: link.path,
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(link.targetSync(), destination.path);
    expect(destination.readAsStringSync(), 'Original file');
    expect(
      root.listSync().where(
        (f) => f.uri.pathSegments.any((p) => p.startsWith('.universe-backup-')),
      ),
      isEmpty,
    );
    expect(
      (await library(connection)).require('writing').toText(),
      contains(draft.proposal.proposalId.value),
    );
  });

  test(
    'native maintenance requires author rights before worker acquisition',
    () async {
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
      final connection = runtime.connect(hello(writer.id));
      final owner = OwnedSqliteDatabase.openExisting(path);
      try {
        for (final collect in [false, true]) {
          await expectLater(
            engine(
              connection,
              MaintainEngineRequest(
                universe: const Selector('World'),
                collect: collect,
              ),
            ),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
        }
      } finally {
        owner.close();
      }
    },
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
