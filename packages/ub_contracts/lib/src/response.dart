import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'assessment.dart';
import 'envelope.dart';
import 'read_response.dart';
import 'request.dart';
import 'state_response.dart';
import 'validation_scope.dart';
import 'workflow.dart';
import 'wire.dart';

/// Semantic proposals and independently versioned assessment selections retain
/// their existing untagged wire shapes. Decoding grants no publication authority.
sealed class ProposalOutcome {
  const ProposalOutcome();
  CanonicalObject toWire();
  static ProposalOutcome fromWire(CanonicalValue value) {
    try {
      return SemanticProposalOutcome(Proposal.fromWire(value));
    } on FormatException {
      return SelectedAssessmentOutcome(AssessmentSelection.fromWire(value));
    }
  }
}

final class SemanticProposalOutcome extends ProposalOutcome {
  const SemanticProposalOutcome(this.proposal);
  final Proposal proposal;
  @override
  CanonicalObject toWire() => proposal.toWire();
}

final class SelectedAssessmentOutcome extends ProposalOutcome {
  const SelectedAssessmentOutcome(this.selection);
  final AssessmentSelection selection;
  @override
  CanonicalObject toWire() => selection.toWire();
}

sealed class ProposalViewResult {
  const ProposalViewResult();
  CanonicalObject toWire();
  static ProposalViewResult fromWire(CanonicalValue value) {
    try {
      return FrozenProposalView(Proposal.fromWire(value));
    } on FormatException {
      return AssessmentProposalView(AssessmentReviewPage.fromWire(value));
    }
  }
}

final class FrozenProposalView extends ProposalViewResult {
  const FrozenProposalView(this.proposal);
  final Proposal proposal;
  @override
  CanonicalObject toWire() => proposal.toWire();
}

final class AssessmentProposalView extends ProposalViewResult {
  const AssessmentProposalView(this.assessment);
  final AssessmentReviewPage assessment;
  @override
  CanonicalObject toWire() => assessment.toWire();
}

/// Closed service response dispatch, independent of transport and presentation.
sealed class Response {
  const Response();
  String get toolName;
  String get wireTag => toolName;
  CanonicalObject bodyJson();
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('tool', CanonicalString(wireTag)),
    MapEntry('body', bodyJson()),
  ]);
  static Response decode(Uint8List bytes) {
    return fromWire(decodeWireFrame(bytes));
  }

  static Response fromWire(CanonicalValue value) {
    final f = WireFields(value, {'tool', 'body'});
    final tag = f.string('tool');
    // Historical serde leaves this variant unrenamed. Preserve the IPC tag;
    // public MCP dispatch uses the ordinary universe_read_facts tool name.
    if (tag == 'universe_read_facts') {
      throw const FormatException('Expected historical ReadFacts response tag');
    }
    return fromTool(
      tag == 'ReadFacts' ? 'universe_read_facts' : tag,
      f.require('body'),
    );
  }

  static Response fromTool(String name, CanonicalValue body) => switch (name) {
    'universe_check_changes' => CheckChangesResponse(
      Envelope<WritingCheck>.fromWire(body, WritingCheck.fromWire),
    ),
    'universe_read_facts' => ReadFactsResponse(
      Envelope<CanonicalValue>.fromWire(body, (v) => v),
    ),
    'universe_read_contracts' => ReadContractsResponse(
      Envelope<CanonicalValue>.fromWire(body, (v) => v),
    ),
    'universe_describe' => DescribeResponse(
      Envelope<Description>.fromWire(body, Description.fromWire),
    ),
    'universe_open_context' => OpenContextResponse(
      Envelope<OpenedContext>.fromWire(body, OpenedContext.fromWire),
    ),
    'universe_search' => SearchResponse(
      Envelope<SearchResults>.fromWire(body, SearchResults.fromWire),
    ),
    'universe_get' => GetResponse(
      Envelope<Records>.fromWire(body, Records.fromWire),
    ),
    'universe_get_state' => GetStateResponse(
      Envelope<State>.fromWire(body, State.fromWire),
    ),
    'universe_get_context' => GetContextResponse(
      Envelope<ContextBrief>.fromWire(body, ContextBrief.fromWire),
    ),
    'universe_validate' => ValidateResponse(
      Envelope<ValidationV3>.fromWire(body, ValidationV3.fromWire),
    ),
    'universe_propose' => ProposeResponse(
      Envelope<ProposalOutcome>.fromWire(body, ProposalOutcome.fromWire),
    ),
    'universe_get_proposal' => GetProposalResponse(
      Envelope<ProposalViewResult>.fromWire(body, ProposalViewResult.fromWire),
    ),
    'universe_get_impact' => GetImpactResponse(
      Envelope<Impact>.fromWire(body, Impact.fromWire),
    ),
    'universe_commit' => CommitResponse(
      Envelope<CommitReceipt>.fromWire(body, CommitReceipt.fromWire),
    ),
    'universe_get_operation' => GetOperationResponse(
      Envelope<OperationStatusV3>.fromWire(body, OperationStatusV3.fromWire),
    ),
    'universe_cancel_operation' => CancelOperationResponse(
      Envelope<OperationStatusV3>.fromWire(body, OperationStatusV3.fromWire),
    ),
    _ => throw const FormatException('Unknown response tool'),
  };
}

final class CheckChangesResponse extends Response {
  const CheckChangesResponse(this.body);
  final Envelope<WritingCheck> body;
  @override
  String get toolName => 'universe_check_changes';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class ReadFactsResponse extends Response {
  const ReadFactsResponse(this.body);
  final Envelope<CanonicalValue> body;
  @override
  String get toolName => 'universe_read_facts';
  @override
  String get wireTag => 'ReadFacts';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v);
}

final class ReadContractsResponse extends Response {
  const ReadContractsResponse(this.body);
  final Envelope<CanonicalValue> body;
  @override
  String get toolName => 'universe_read_contracts';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v);
}

final class DescribeResponse extends Response {
  const DescribeResponse(this.body);
  final Envelope<Description> body;
  @override
  String get toolName => 'universe_describe';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class OpenContextResponse extends Response {
  const OpenContextResponse(this.body);
  final Envelope<OpenedContext> body;
  @override
  String get toolName => 'universe_open_context';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class SearchResponse extends Response {
  const SearchResponse(this.body);
  final Envelope<SearchResults> body;
  @override
  String get toolName => 'universe_search';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class GetResponse extends Response {
  const GetResponse(this.body);
  final Envelope<Records> body;
  @override
  String get toolName => 'universe_get';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class GetStateResponse extends Response {
  const GetStateResponse(this.body);
  final Envelope<State> body;
  @override
  String get toolName => 'universe_get_state';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class GetContextResponse extends Response {
  const GetContextResponse(this.body);
  final Envelope<ContextBrief> body;
  @override
  String get toolName => 'universe_get_context';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class ValidateResponse extends Response {
  const ValidateResponse(this.body);
  final Envelope<ValidationV3> body;
  @override
  String get toolName => 'universe_validate';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class ProposeResponse extends Response {
  const ProposeResponse(this.body);
  final Envelope<ProposalOutcome> body;
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class GetProposalResponse extends Response {
  const GetProposalResponse(this.body);
  final Envelope<ProposalViewResult> body;
  @override
  String get toolName => 'universe_get_proposal';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class GetImpactResponse extends Response {
  const GetImpactResponse(this.body);
  final Envelope<Impact> body;
  @override
  String get toolName => 'universe_get_impact';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class CommitResponse extends Response {
  const CommitResponse(this.body);
  final Envelope<CommitReceipt> body;
  @override
  String get toolName => 'universe_commit';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class GetOperationResponse extends Response {
  const GetOperationResponse(this.body);
  final Envelope<OperationStatusV3> body;
  @override
  String get toolName => 'universe_get_operation';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}

final class CancelOperationResponse extends Response {
  const CancelOperationResponse(this.body);
  final Envelope<OperationStatusV3> body;
  @override
  String get toolName => 'universe_cancel_operation';
  @override
  CanonicalObject bodyJson() => body.toWire((v) => v.toWire());
}
