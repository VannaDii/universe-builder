@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/proposal_validation.dart';
import 'package:ub_service/sqlite_validation.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/kernel.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
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
    final clear = await service.selectAssessment(
      proposal.reference,
      expectedGeneration: BigInt.one,
      selected: null,
      idempotencyKey: 'clear',
    );
    expect(clear.generation, BigInt.two);
    expect(clear.selected, isNull);
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
    package.close();
    package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/world.sqlite',
    );
    package.recover();
    final retained = CheckedValidation.fromWire(
      WorkflowStorage(package.database).get(key())!,
    );
    expect(retained.toWire().toText(), checked.toWire().toText());
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
