import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/operation_state.dart';
import 'package:ub_service/proposal_authorization.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as p;
import 'validation_binding_test.dart' as bindings;

final proposal = p.prepare();
final id = OperationId.parse('op_${f.suffix(1)}');
final input = CommitInput(
  universe: f.u,
  continuity: proposal.proposal.baseFrame.continuity,
  expectedHead: proposal.proposal.baseFrame.revision,
  principal: PrincipalId.parse(p.actor.value.replaceFirst('prf_', 'prn_')),
  decision: proposal.proposal.digest,
  reason: 'Checked proposal',
  idempotencyKey: 'commit',
  changes: proposal.changes,
);
StoredOperation operation({
  OperationKind kind = OperationKind.validate,
  OperationState state = OperationState.running,
  CommitInput? commit,
  ProfileId? owner,
  WriteFootprint? footprint,
}) => StoredOperation(
  owner: owner ?? p.actor,
  digest: 'a' * 64,
  input: commit,
  footprint: footprint ?? proposal.footprint,
  validationCapture: bindings.capture(),
  status: OperationStatus(
    validation: bindings.execution(),
    operationId: id,
    kind: kind,
    state: state,
    proposal: proposal.proposal,
    cancellationRequested: false,
  ),
);
Future<StoredOperation> resolve(
  Map<String, CanonicalValue> entries, {
  String? key,
  ProfileId? principal,
  Set<WorldId>? scope,
  RevisionId? revision,
  bool active = false,
  void Function()? receiptRead,
}) => loadStoredOperation(
  key: key ?? 'operation:${id.value}',
  principal: principal ?? p.actor,
  worldScope: scope,
  readWorkflow: (key) => entries[key],
  readReceipt: (stored) {
    receiptRead?.call();
    expect(stored.toCanonical().toText(), input.toCanonical().toText());
    return revision;
  },
  isValidationActive: (value) {
    expect(value, id);
    return active;
  },
);
Map<String, CanonicalValue> stored(StoredOperation op) => {
  'operation:${id.value}': op.toWire(),
};

void main() {
  test(
    'operation findings page exact execution without altering retained status',
    () {
      final original = operation();
      final v = original.status.validation!;
      final execution = Validation(
        operationId: id,
        runId: v.runId,
        coverage: v.coverage,
        findings: [
          for (var n = 0; n < 205; n++)
            Finding(
              message: 'Finding $n',
              fingerprint: FindingFingerprint('a' * 64),
              ruleId: f.id(99),
              outcome: EvidenceOutcome.supported,
              evidence: [],
              coverage: Coverage.complete,
            ),
        ],
        opposingEvidence: v.opposingEvidence,
        unsupportedCapabilities: ['bounded fixture'],
        inputDigest: v.inputDigest,
        evaluatorVersion: v.evaluatorVersion,
      );
      final status = OperationStatus(
        operationId: id,
        kind: original.status.kind,
        state: original.status.state,
        proposal: original.status.proposal,
        validation: execution,
        cancellationRequested: false,
      );
      final before = status.toWire().toText();
      final pages = [
        for (final offset in [0, 100, 200])
          pageOperationFindings(status, offset),
      ];
      expect(pages.map((p) => p.status.validation!.findings.length), [
        100,
        100,
        5,
      ]);
      expect(pages.map((p) => p.complete), [false, false, true]);
      expect(
        pages
            .expand((p) => p.status.validation!.findings)
            .map((f) => f.toWire().toText()),
        execution.findings.map((f) => f.toWire().toText()),
      );
      for (final page in pages) {
        expect(page.status.proposal, status.proposal);
        expect(page.status.validation!.inputDigest, execution.inputDigest);
        expect(
          page.status.validation!.unsupportedCapabilities,
          execution.unsupportedCapabilities,
        );
      }
      expect(status.toWire().toText(), before);
      expect(
        pageOperationFindings(status, 205).status.validation!.findings,
        isEmpty,
      );
      for (final offset in [-1, 206]) {
        expect(
          () => pageOperationFindings(status, offset),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      }
    },
  );

  test('typed operation retains exact commit input and capture and nullable capture', () {
    final original = operation(kind: OperationKind.commit, commit: input);
    final decoded = StoredOperation.fromWire(original.toWire());
    expect(decoded.toWire().toText(), original.toWire().toText());
    expect(decoded.input!.toCanonical().toText(), input.toCanonical().toText());
  });

  test('request aliases resolve terminal before running without rewriting immutable queue state', () async {
    final entries = stored(operation(state: OperationState.queued));
    const request = 'request:validation';
    entries[request] = entries.values.first;
    entries['job:${id.value}:running'] = operation().toWire();
    entries['job:${id.value}:terminal'] = operation(
      state: OperationState.succeeded,
    ).toWire();
    expect(
      (await resolve(entries, key: request)).status.state,
      OperationState.succeeded,
    );
    entries.remove('job:${id.value}:terminal');
    expect(
      (await resolve(entries, key: request)).status.state,
      OperationState.interrupted,
    );
    expect(
      StoredOperation.fromWire(entries['operation:${id.value}']!).status.state,
      OperationState.queued,
    );
  });

  test('running requires live scheduler activity; queued and terminal states remain intact', () async {
    expect(
      (await resolve(stored(operation()), active: true)).status.state,
      OperationState.running,
    );
    expect(
      (await resolve(stored(operation()))).status.state,
      OperationState.interrupted,
    );
    for (final state in [
      OperationState.queued,
      OperationState.failed,
      OperationState.succeeded,
    ]) {
      expect(
        (await resolve(stored(operation(state: state)))).status.state,
        state,
      );
    }
    final entries = stored(operation())
      ..['cancel:${id.value}'] = const CanonicalBool(true);
    final result = await resolve(entries, active: true);
    expect(result.status.state, OperationState.cancelled);
    expect(result.status.cancellationRequested, isTrue);
  });

  test(
    'durable commit receipt wins over cancellation and lost running state',
    () async {
      final entries = stored(
        operation(kind: OperationKind.commit, commit: input),
      );
      entries['cancel:${id.value}'] = const CanonicalBool(true);
      final revision = RevisionId.parse('rev_${f.suffix(80)}');
      final result = await resolve(entries, revision: revision);
      expect(result.status.state, OperationState.succeeded);
      expect(result.status.receipt!.revision, revision);
      expect(result.status.receipt!.proposalId, proposal.reference.proposalId);
      expect((await resolve(entries)).status.state, OperationState.cancelled);
      entries.remove('cancel:${id.value}');
      expect((await resolve(entries)).status.state, OperationState.interrupted);
    },
  );

  test(
    'owner and complete footprint admission precede receipt disclosure',
    () async {
      final entries = stored(
        operation(kind: OperationKind.commit, commit: input),
      );
      for (final denied in [
        resolve(
          entries,
          principal: p.other,
          receiptRead: () => fail('Hidden receipt read'),
        ),
        resolve(
          entries,
          scope: {},
          receiptRead: () => fail('Hidden shared receipt read'),
        ),
      ]) {
        await expectLater(denied, throwsA(isA<NotFoundOrNotAccessibleError>()));
      }
      final world = WorldId.parse('wld_${f.suffix(1)}');
      final scoped = stored(
        operation(footprint: WriteFootprint(worlds: [world])),
      );
      await expectLater(
        resolve(scoped, scope: {}),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect((await resolve(scoped, scope: {world})).owner, p.actor);
    },
  );
}
