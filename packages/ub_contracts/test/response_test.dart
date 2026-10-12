import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final frame = Frame(
  universe: UniverseId.parse('unv_000000000000000000000001'),
  continuity: ContinuityId.parse('cont_000000000000000000000001'),
  revision: RevisionId.parse('rev_000000000000000000000001'),
  context: RecordRef(record: RecordId.parse('rec_000000000000000000000001')),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);
final proposal = Proposal(
  baseFrame: frame,
  proposalId: ProposalId.parse('prp_000000000000000000000001'),
  version: BigInt.parse('18446744073709551615'),
  digest: 'supplied digest',
  submission: Submission.submitted,
  operations: [],
  rationale: 'authored',
  canonical: false,
  operationId: OperationId.parse('op_000000000000000000000001'),
  withdrawn: false,
);
Envelope<T> envelope<T>(T result) => Envelope(
  contractVersion: '3',
  requestId: BigInt.parse('18446744073709551615'),
  universeId: frame.universe,
  universe: const Selector('Cycle'),
  aliasMatched: false,
  frame: frame,
  authorizationScope: 'visible',
  delivery: Delivery(complete: true),
  result: result,
);
CanonicalValue wire(String raw) => CanonicalValue.parseWireJson(raw);
void main() {
  test('semantic and assessment outcomes preserve frozen proposal and independent generation', () {
    final selected = AssessmentSelection(
      proposal: ProposalRef(
        proposalId: proposal.proposalId,
        version: proposal.version,
        digest: proposal.digest,
      ),
      generation: BigInt.parse('9007199254740993'),
      selected: null,
    );
    final semantic = Response.decode(
      ProposeResponse(
        envelope<ProposalOutcome>(SemanticProposalOutcome(proposal)),
      ).toWire().toBytes(),
    ) as ProposeResponse;
    final assessment = Response.decode(
      ProposeResponse(
        envelope<ProposalOutcome>(SelectedAssessmentOutcome(selected)),
      ).toWire().toBytes(),
    ) as ProposeResponse;
    expect(
      (semantic.body.result as SemanticProposalOutcome).proposal.version,
      proposal.version,
    );
    expect(
      (assessment.body.result as SelectedAssessmentOutcome)
          .selection
          .generation,
      selected.generation,
    );
    expect(proposal.digest, 'supplied digest');
    expect(proposal.operations, isEmpty);
    expect(assessment.bodyJson().toText(), isNot(contains('operations')));
    expect(assessment.body.result.toWire().toText(), isNot(contains('kind')));
  });
  test(
    'proposal review and assessment review remain separate untagged variants',
    () {
      final selected = AssessmentSelection(
        proposal: ProposalRef(
          proposalId: proposal.proposalId,
          version: proposal.version,
          digest: proposal.digest,
        ),
        generation: BigInt.zero,
        selected: null,
      );
      final page = AssessmentReviewPage(
        selection: selected,
        state: AbsentAssessment(),
        envelope: null,
        fragment: null,
      );
      expect(
        ProposalViewResult.fromWire(proposal.toWire()),
        isA<FrozenProposalView>(),
      );
      final back =
          ProposalViewResult.fromWire(page.toWire()) as AssessmentProposalView;
      expect(back.assessment.state, isA<AbsentAssessment>());
      expect(back.assessment.fragment, isNull);
      expect(back.toWire().toText(), page.toWire().toText());
      expect(
        () => ProposalOutcome.fromWire(wire('{"kind":"proposal"}')),
        throwsFormatException,
      );
      expect(
        () => ProposalViewResult.fromWire(wire('{"selection":null}')),
        throwsFormatException,
      );
    },
  );
  test('read facts preserves historical IPC tag and public tool name independently', () {
    final result = ReadFactsResponse(
      envelope(wire('{"amount":9007199254740993.00,"other":1E3}')),
    );
    expect(result.toolName, 'universe_read_facts');
    expect(result.wireTag, 'ReadFacts');
    final decoded =
        Response.decode(result.toWire().toBytes()) as ReadFactsResponse;
    expect(
      decoded.body.result.toText(),
      '{"amount":9007199254740993.00,"other":1E3}',
    );
    expect(
      Response.fromTool('universe_read_facts', result.bodyJson()),
      isA<ReadFactsResponse>(),
    );
    expect(
      () => Response.fromWire(
        CanonicalObject([
          MapEntry('tool', CanonicalString('universe_read_facts')),
          MapEntry('body', result.bodyJson()),
        ]),
      ),
      throwsFormatException,
    );
  });
  test(
    'body serialization retains envelope but strips only dispatch wrapper',
    () {
      final response = CommitResponse(
        envelope(
          CommitReceipt(
            operationId: proposal.operationId,
            proposalId: proposal.proposalId,
            revision: frame.revision,
          ),
        ),
      );
      expect(response.bodyJson().toText(), isNot(contains('"tool":')));
      expect(
        response.bodyJson().toText(),
        contains('"request_id":18446744073709551615'),
      );
      expect(response.bodyJson().toText(), contains('"delivery":'));
      final decoded = Response.fromTool(
        'universe_commit',
        response.bodyJson(),
      ) as CommitResponse;
      expect(decoded.body.result.revision, frame.revision);
      expect(decoded.body.result.operationId, proposal.operationId);
    },
  );
  test('restricted validation and cancellation are carried without upgrading evidence or success', () {
    final op = OperationStatusV3(
      operationId: proposal.operationId,
      kind: OperationKind.cancel,
      state: OperationState.interrupted,
      validation: ValidationV3.restricted(),
      cancellationRequested: true,
    );
    final response = CancelOperationResponse(envelope(op));
    final back =
        Response.decode(response.toWire().toBytes()) as CancelOperationResponse;
    expect(back.body.result.state, OperationState.interrupted);
    expect(back.body.result.validation!.execution, isNull);
    expect(back.body.result.receipt, isNull);
    expect(back.body.result.cancellationRequested, isTrue);
  });
  test('strict response decode rejects duplicate keys encoding overflow unknown and extra fields', () {
    for (final raw in [
      '{"tool":"universe_commit","tool":"universe_search","body":{}}',
      '{"tool":"unknown","body":{}}',
      '{"tool":"universe_search","body":{},"approved":true}',
    ]) {
      expect(
        () => Response.decode(Uint8List.fromList(utf8.encode(raw))),
        throwsFormatException,
      );
    }
    expect(
      () => Response.decode(Uint8List.fromList([0xff])),
      throwsFormatException,
    );
    expect(
      () => Response.decode(Uint8List(1024 * 1024 + 1)),
      throwsFormatException,
    );
    final response = ReadContractsResponse(envelope(wire('{"items":[]}')));
    final duplicated = response.toWire().toText().replaceFirst(
      '"items":[]',
      '"items":[],"items":[]',
    );
    expect(
      () => Response.decode(Uint8List.fromList(utf8.encode(duplicated))),
      throwsFormatException,
    );
    final body = response.bodyJson();
    final malformed = CanonicalObject([
      ...body.fields.where((e) => e.key != 'result'),
      MapEntry('result', wire('{"items":[]}')),
    ]);
    expect(
      () => Response.fromTool('universe_describe', malformed),
      throwsFormatException,
    );
  });
}
