@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/operation_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/sqlite_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  test('operation reading retains every paged finding and the original validation binding', () async {
    final universe = UniverseId.generate(), operation = OperationId.generate();
    final proposal = Proposal(
      baseFrame: Frame(
        universe: universe,
        continuity: ContinuityId.generate(),
        revision: RevisionId.generate(),
        context: RecordRef(record: RecordId.generate()),
        time: const TimelessFrameTime(),
        perspective: const AuthorPerspective(),
      ),
      proposalId: ProposalId.generate(),
      version: BigInt.one,
      digest: 'a' * 64,
      submission: Submission.submitted,
      operations: [],
      rationale: 'Transport fixture',
      canonical: false,
      operationId: OperationId.generate(),
      withdrawn: false,
    );
    final reference = ProposalRef(
      proposalId: proposal.proposalId,
      version: proposal.version,
      digest: proposal.digest,
    );
    final run = ValidationRunId.generate();
    final findings = List.generate(
      203,
      (index) => Finding(
        fingerprint: FindingFingerprint(
          index.toRadixString(16).padLeft(64, '0'),
        ),
        ruleId: RecordId.generate(),
        outcome: EvidenceOutcome.notEstablished,
        evidence: [],
        coverage: Coverage.complete,
        message: 'Finding $index 記憶 😀',
      ),
    );
    var pages = 0;
    final recovery = OperationRecovery(
      universe: const Selector('Paged'),
      universeId: universe,
      call: (request) async {
        final lookup =
            (request as ToolEngineRequest).request as GetOperationIdRequest;
        expect(lookup.operationId, operation);
        expect(lookup.cursor, pages == 0 ? null : 'page-$pages');
        final start = pages * 100;
        final end = (start + 100).clamp(0, findings.length);
        pages++;
        return Envelope<OperationStatusV3>(
          contractVersion: protocolVersion,
          requestId: BigInt.from(pages),
          universeId: universe,
          universe: const Selector('Paged'),
          aliasMatched: false,
          frame: proposal.baseFrame,
          authorizationScope: 'fixture',
          delivery: Delivery(
            complete: end == findings.length,
            cursor: end == findings.length ? null : 'page-$pages',
          ),
          result: OperationStatusV3(
            operationId: operation,
            kind: OperationKind.validate,
            state: OperationState.succeeded,
            proposal: proposal,
            cancellationRequested: false,
            validation: EvaluatedValidation(
              execution: Validation(
                operationId: operation,
                runId: run,
                coverage: Coverage.complete,
                findings: findings.sublist(start, end),
                unsupportedCapabilities: ['fixture-capability'],
                inputDigest: 'c' * 64,
                evaluatorVersion: 'fixture',
              ),
              submittedInput: RecordCandidateInput(
                proposal: reference,
                includesSources: false,
              ),
              assessment: const AbsentAssessment(),
              finalBindingDigest: Sha256Hex('b' * 64),
            ),
          ),
        ).toWire((status) => status.toWire());
      },
    );
    final status = await recovery.read(operation);
    final report = status.validation as EvaluatedValidation;
    expect(pages, 3);
    expect(
      report.execution.findings.map((finding) => finding.toWire().toText()),
      findings.map((finding) => finding.toWire().toText()),
    );
    expect(report.execution.runId, run);
    expect(report.execution.unsupportedCapabilities, ['fixture-capability']);
    expect(report.finalBindingDigest!.value, 'b' * 64);
    expect(
      report.submittedInput.toWire().toText(),
      RecordCandidateInput(
        proposal: reference,
        includesSources: false,
      ).toWire().toText(),
    );
  });

  test('operation recovery cancels pending checks, survives restart and never reverses completed publication', () async {
    final root = Directory('/tmp').createTempSync('ub-operation-recovery-');
    var store = SqliteInstallationStore.create(root.path);
    var authority = InstallationAuthority(store);
    final author = authority.initializeAuthor();
    EngineHello hello(ProfileId profile) => EngineHello(
      protocolVersion: protocolVersion,
      profileId: profile,
      credential: Credential(
        ProfileCredentialStore.read(root: root.path, profile: profile),
      ),
      clientName: 'Disposable operation recovery',
    );
    var runtime = NativeSqliteRuntime(authority: authority);
    var connection = runtime.connect(hello(author));
    try {
      final created = WireFields(
        await connection.execute(
          const CreateUniverseEngineRequest(
            name: 'Operations',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final universe = UniverseId.parse(created.string('universe_id'));
      final continuity = ContinuityId.parse(created.string('continuity_id'));
      final opened = Envelope<OpenedContext>.fromWire(
        await connection.execute(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: const Selector('Operations'),
              universeId: universe,
              continuityId: continuity,
              revision: const HeadRevisionSelector(),
              representedContext: ContextIdSelector(
                RecordId.parse(created.string('context_id')),
              ),
              temporalQuery: const TimelessFrameTime(),
              temporalSystems: [],
              perspective: const AuthorPerspective(),
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      final proposal = Envelope<Proposal>.fromWire(
        await connection.execute(
          ToolEngineRequest(
            request: CreateProposalRequest(
              universe: const Selector('Operations'),
              universeId: universe,
              contextId: opened.contextId,
              operations: [
                CreateWorldOperation(
                  clientRef: RecordId.generate().value,
                  record: WorldRecord(selector: 'Retained world'),
                ),
              ],
              submission: Submission.submitted,
              rationale: 'An exact author proposal.',
              idempotencyKey: 'proposal',
            ),
          ),
        ),
        Proposal.fromWire,
      ).result;
      final reference = ProposalRef(
        proposalId: proposal.proposalId,
        version: proposal.version,
        digest: proposal.digest,
      );
      final queued = Envelope<OperationStatusV3>.fromWire(
        await connection.execute(
          ToolEngineRequest(
            request: QueuedProposalValidationRequest(
              universe: const Selector('Operations'),
              universeId: universe,
              contextId: opened.contextId,
              proposalReference: reference,
              checkScope: CheckScope.universe,
              idempotencyKey: 'pending-check',
            ),
          ),
        ),
        OperationStatusV3.fromWire,
      ).result;
      OperationRecovery recovery({String name = 'Operations'}) =>
          OperationRecovery(
            call: connection.execute,
            universe: Selector(name),
            universeId: universe,
          );
      expect(canCancelOperation(queued), isTrue);
      final cancelled = await recovery().cancel(queued.operationId);
      expect(cancelled.state, OperationState.cancelled);
      expect(cancelled.cancellationRequested, isTrue);
      expect(canCancelOperation(cancelled), isFalse);
      await connection.execute(
        RenameUniverseEngineRequest(
          universeId: universe,
          name: 'Renamed operations',
        ),
      );
      final retried = await recovery(name: 'Renamed operations')
          .cancel(queued.operationId);
      expect(retried.operationId, queued.operationId);
      expect(retried.state, OperationState.cancelled);
      final validation =
          Envelope<ValidationV3>.fromWire(
                await connection.execute(
                  ToolEngineRequest(
                    request: ProposalValidationRequest(
                      universe: const Selector('Operations'),
                      universeId: universe,
                      contextId: opened.contextId,
                      proposalReference: reference,
                      checkScope: CheckScope.universe,
                    ),
                  ),
                ),
                ValidationV3.fromWire,
              ).result
              as EvaluatedValidation;
      await connection.execute(
        ApproveEngineRequest(
          universe: const Selector('Operations'),
          proposalReference: reference,
          validationRun: validation.execution.runId,
        ),
      );
      final receipt = Envelope<CommitReceipt>.fromWire(
        await connection.execute(
          ToolEngineRequest(
            request: CommitRequest(
              universe: const Selector('Operations'),
              universeId: universe,
              proposalReference: reference,
              expectedBaseRevision: proposal.baseFrame.revision,
              validationRun: validation.execution.runId,
              idempotencyKey: 'publish',
            ),
          ),
        ),
        CommitReceipt.fromWire,
      ).result;
      final completed = await recovery().cancel(receipt.operationId);
      expect(completed.state, OperationState.succeeded);
      expect(completed.cancellationRequested, isFalse);
      expect(completed.receipt!.revision, receipt.revision);
      expect(canCancelOperation(completed), isFalse);
      final enrolled = WireFields(
        await connection.execute(const EnrollEngineRequest()),
        {'profile_id'},
      );
      final reader = ProfileId.parse(enrolled.string('profile_id'));
      await connection.execute(
        GrantEngineRequest(
          grant: GrantSpec(
            profileId: reader,
            universeId: universe,
            propose: false,
            edit: false,
            protected: false,
          ),
        ),
      );
      final other = runtime.connect(hello(reader));
      final denied = OperationRecovery(
        call: other.execute,
        universe: const Selector('Operations'),
        universeId: universe,
      );
      await expectLater(
        denied.read(queued.operationId),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        denied.cancel(queued.operationId),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      other.close();
      await runtime.close();
      store.close();
      store = SqliteInstallationStore.openExisting(root.path);
      authority = InstallationAuthority(store);
      runtime = NativeSqliteRuntime(authority: authority);
      connection = runtime.connect(hello(author));
      expect(
        (await recovery().read(queued.operationId)).state,
        OperationState.cancelled,
      );
      expect(
        (await recovery().read(receipt.operationId)).receipt!.revision,
        receipt.revision,
      );
    } finally {
      await runtime.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
