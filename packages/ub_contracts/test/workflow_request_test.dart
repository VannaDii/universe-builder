import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'assessment_integrity_test.dart' show base;

const universe = Selector('é🌲 cycle');
final contextId = ContextId.parse('ctx_000000000000000000000001');
final recordId = RecordId.parse('rec_000000000000000000000001');
final max = BigInt.parse('18446744073709551615');
final proposal = ProposalRef(
  proposalId: ProposalId.parse('prp_000000000000000000000001'),
  version: max,
  digest: 'supplied proposal digest',
);
final assessment = AssessmentRef(
  assessmentId: AssessmentId('asm_000000000000000000000001'),
  digest: Sha256Hex('a' * 64),
);
final operation = DomainOperation.fromWire(
  CanonicalValue.parseJson(
    '''{"kind":"create_entity","client_ref":"new","record":{"names":[],"classification":null,"classificationResolution":"unclassified","worldAssociations":[],"labels":{"en":"House"},"metadata":{}}}''',
  ),
);
CanonicalObject fields(
  CanonicalObject value,
  Map<String, CanonicalValue> next,
) => CanonicalObject(
  {
    ...{for (final e in value.fields) e.key: e.value},
    ...next,
  }.entries,
);
final invalid = throwsA(isA<InvalidArgumentError>());

void main() {
  final requests = <WorkflowRequest>[
    QueuedProposalValidationRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      checkScope: CheckScope.candidate,
      idempotencyKey: 'queued',
    ),
    InlineValidationRequest(
      universe: universe,
      contextId: contextId,
      operations: [operation],
      checkScope: CheckScope.universe,
    ),
    ProposalValidationRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      checkScope: CheckScope.dependencies,
    ),
    AttachAssessmentRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      expectedSelectionGeneration: max,
      body: SourceAssessmentV1.fromWire(base()),
      idempotencyKey: 'attach',
    ),
    SelectAssessmentRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      expectedSelectionGeneration: max,
      assessmentReference: null,
      idempotencyKey: 'clear',
    ),
    CreateProposalRequest(
      universe: universe,
      contextId: contextId,
      operations: [operation],
      submission: Submission.draft,
      rationale: 'change',
      idempotencyKey: 'create',
    ),
    ReviseProposalRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      operations: [operation],
      submission: Submission.submitted,
      rationale: 'revision',
      idempotencyKey: 'revise',
    ),
    SubmitProposalRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      idempotencyKey: 'submit',
    ),
    WithdrawProposalRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      idempotencyKey: 'withdraw',
    ),
    GetProposalRequest(
      universe: universe,
      proposalId: proposal.proposalId,
      version: max,
      viewGroup: ProposalView.assessment,
      assessmentReference: assessment,
      cursor: 'opaque',
    ),
    InlineImpactRequest(
      universe: universe,
      contextId: contextId,
      changedRecords: [recordId],
      scope: CheckScope.dependencies,
      byteBudget: 256,
    ),
    ProposalImpactRequest(
      universe: universe,
      contextId: contextId,
      proposalReference: proposal,
      scope: CheckScope.universe,
      byteBudget: 65536,
    ),
    CommitRequest(
      universe: universe,
      proposalReference: proposal,
      expectedBaseRevision: RevisionId.parse('rev_000000000000000000000001'),
      validationRun: ValidationRunId.parse('val_000000000000000000000001'),
      idempotencyKey: 'publish',
    ),
    GetOperationIdRequest(
      universe: universe,
      operationId: OperationId.parse('op_000000000000000000000001'),
      cursor: 'opaque',
    ),
    GetOperationKeyRequest(
      universe: universe,
      operationKind: OperationKind.commit,
      idempotencyKey: 'publish',
    ),
    CancelOperationRequest(
      universe: universe,
      operationId: OperationId.parse('op_000000000000000000000001'),
      idempotencyKey: 'cancel',
    ),
  ];
  for (final request in requests) {
    test('closed workflow wire ${request.runtimeType}', () {
      request.validate();
      final back = Request.fromTool(request.toolName, request.toArgs());
      expect(back.toWire().toText(), request.toWire().toText());
      expect(
        Request.decode(request.toWire().toBytes()).toWire().toText(),
        request.toWire().toText(),
      );
      expect(
        () => Request.fromTool(
          request.toolName,
          fields(request.toArgs(), {'approval': CanonicalBool(true)}),
        ),
        invalid,
      );
      expect(
        () => Request.fromTool(
          request.toolName,
          fields(request.toArgs(), {'universe_id': const CanonicalNull()}),
        ),
        invalid,
      );
    });
  }
  test(
    'selection distinguishes exact selected identity and explicit removal',
    () {
      final clear = requests.whereType<SelectAssessmentRequest>().single;
      final removed = CanonicalObject(
        clear.toArgs().fields.where((e) => e.key != 'assessment_reference'),
      );
      expect(() => Request.fromTool(clear.toolName, removed), invalid);
      final selected = Request.fromTool(
        clear.toolName,
        fields(clear.toArgs(), {'assessment_reference': assessment.toWire()}),
      ) as SelectAssessmentRequest;
      expect(selected.expectedSelectionGeneration, max);
      expect(selected.assessmentReference!.digest, assessment.digest);
      expect(
        (Request.fromWire(
          clear.toWire(),
        ) as SelectAssessmentRequest).assessmentReference,
        isNull,
      );
      for (final digits in ['-1', '18446744073709551616', '1.0']) {
        expect(
          () => Request.fromTool(
            clear.toolName,
            fields(clear.toArgs(), {
              'expected_selection_generation': CanonicalNumber(digits),
            }),
          ),
          invalid,
        );
      }
    },
  );
  test(
    'proposal and generation retain exact u64 beyond browser number precision',
    () {
      final attach = Request.fromWire(
        requests.whereType<AttachAssessmentRequest>().single.toWire(),
      ) as AttachAssessmentRequest;
      expect(attach.expectedSelectionGeneration, max);
      expect(attach.proposalReference.version, max);
      final get = Request.fromWire(
        requests.whereType<GetProposalRequest>().single.toWire(),
      ) as GetProposalRequest;
      expect(get.version, max);
      // Request contracts retain unqualified opaque digests; service checks the binding.
      expect(get.proposalId, proposal.proposalId);
      final zero = Request.fromTool(
        get.toolName,
        fields(get.toArgs(), {'version': const CanonicalNumber('0')}),
      ) as GetProposalRequest;
      expect(zero.version, BigInt.zero);
    },
  );
  test(
    'assessment reference may only be requested through assessment view',
    () {
      final get = requests.whereType<GetProposalRequest>().single;
      for (final view in ['summary', 'payload', 'evidence', 'history']) {
        expect(
          () => Request.fromTool(
            get.toolName,
            fields(get.toArgs(), {'view_group': CanonicalString(view)}),
          ),
          invalid,
        );
      }
      final missing = CanonicalObject(
        get.toArgs().fields.where((e) => e.key != 'view_group'),
      );
      expect(() => Request.fromTool(get.toolName, missing), invalid);
      expect(
        () => Request.fromTool(
          get.toolName,
          fields(get.toArgs(), {'assessment_reference': const CanonicalNull()}),
        ),
        invalid,
      );
    },
  );
  test(
    'retry keys rationale operation counts and budgets follow existing limits',
    () {
      final create = requests.whereType<CreateProposalRequest>().single;
      for (final key in ['idempotency_key', 'rationale']) {
        for (final text in ['', ' \u0085\u3000', 'é' * 2049]) {
          expect(
            () => Request.fromTool(
              create.toolName,
              fields(create.toArgs(), {key: CanonicalString(text)}),
            ),
            invalid,
          );
        }
      }
      for (final count in [0, 101]) {
        expect(
          () => Request.fromTool(
            create.toolName,
            fields(create.toArgs(), {
              'operations': CanonicalArray(
                List.filled(count, operation.toWire()),
              ),
            }),
          ),
          invalid,
        );
      }
      final impact = requests.whereType<InlineImpactRequest>().single;
      for (final number in [255, 65537]) {
        expect(
          () => Request.fromTool(
            impact.toolName,
            fields(impact.toArgs(), {
              'byte_budget': CanonicalNumber(number.toString()),
            }),
          ),
          invalid,
        );
      }
      expect(
        () => Request.fromTool(
          impact.toolName,
          fields(impact.toArgs(), {'changed_records': CanonicalArray([])}),
        ),
        invalid,
      );
    },
  );
  test('structural attachment decoding does not imply admission or assessor authenticity', () {
    final attach = requests.whereType<AttachAssessmentRequest>().single;
    final body = fields(attach.body.toWire(), {
      'conclusion': CanonicalString('unresolved'),
    });
    final decoded = Request.fromTool(
      attach.toolName,
      fields(attach.toArgs(), {'body': body}),
    ) as AttachAssessmentRequest;
    expect(decoded.body.validate, throwsFormatException);
    expect(
      () => decoded.body.bindFrozenProposal(
        decoded.proposalReference,
        decoded.body.baseFrame,
      ),
      throwsFormatException,
    );
  });
  test('request input refuses duplicate fields invalid encoding and oversized frames', () {
    final request = requests.whereType<CommitRequest>().single;
    final wire = request.toWire().toText();
    final repeated = wire.replaceFirst(
      '"tool":',
      '"tool":"universe_commit","tool":',
    );
    expect(
      () => Request.decode(Uint8List.fromList(utf8.encode(repeated))),
      throwsFormatException,
    );
    expect(
      () => Request.decode(Uint8List.fromList([0xff])),
      throwsFormatException,
    );
    expect(
      () => Request.decode(Uint8List(1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('caller-owned operation lists cannot mutate a frozen request', () {
    final ops = [operation];
    final request = InlineValidationRequest(
      universe: universe,
      contextId: contextId,
      operations: ops,
      checkScope: CheckScope.candidate,
    );
    ops.clear();
    expect(request.operations, hasLength(1));
    expect(request.operations.clear, throwsUnsupportedError);
  });
}
