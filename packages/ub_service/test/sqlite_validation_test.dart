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
