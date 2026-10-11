part of 'request.dart';

enum ProposalView {
  summary,
  payload,
  evidence,
  history,
  assessment;

  static ProposalView fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown proposal view'),
  );
}

/// Proposal, validation, exact publication and operation-recovery contracts.
sealed class WorkflowRequest extends Request {
  const WorkflowRequest();
  static WorkflowRequest _parse(String tool, CanonicalValue args) {
    final tag = switch (tool) {
      'universe_validate' || 'universe_get_impact' => 'mode',
      'universe_propose' => 'action',
      'universe_get_operation' => 'lookup',
      _ => null,
    };
    String? variant;
    if (tag != null) {
      if (args is! CanonicalObject) {
        throw const FormatException('Expected request object');
      }
      variant = wireString(
        {for (final e in args.fields) e.key: e.value}[tag] ??
            (throw FormatException('Missing field: $tag')),
      );
    }
    return switch ((tool, variant)) {
      ('universe_validate', 'queued_proposal') =>
        QueuedProposalValidationRequest.fromArgs(args),
      ('universe_validate', 'inline') => InlineValidationRequest.fromArgs(args),
      ('universe_validate', 'proposal') => ProposalValidationRequest.fromArgs(
        args,
      ),
      ('universe_propose', 'attach_assessment') =>
        AttachAssessmentRequest.fromArgs(args),
      ('universe_propose', 'select_assessment') =>
        SelectAssessmentRequest.fromArgs(args),
      ('universe_propose', 'create') => CreateProposalRequest.fromArgs(args),
      ('universe_propose', 'revise') => ReviseProposalRequest.fromArgs(args),
      ('universe_propose', 'submit') => SubmitProposalRequest.fromArgs(args),
      ('universe_propose', 'withdraw') => WithdrawProposalRequest.fromArgs(
        args,
      ),
      ('universe_get_proposal', null) => GetProposalRequest.fromArgs(args),
      ('universe_get_impact', 'inline') => InlineImpactRequest.fromArgs(args),
      ('universe_get_impact', 'proposal') => ProposalImpactRequest.fromArgs(
        args,
      ),
      ('universe_commit', null) => CommitRequest.fromArgs(args),
      ('universe_get_operation', 'id') => GetOperationIdRequest.fromArgs(args),
      ('universe_get_operation', 'key') => GetOperationKeyRequest.fromArgs(
        args,
      ),
      ('universe_cancel_operation', null) => CancelOperationRequest.fromArgs(
        args,
      ),
      _ => throw const FormatException('Unknown workflow request'),
    };
  }
}

final class QueuedProposalValidationRequest extends WorkflowRequest {
  QueuedProposalValidationRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required this.checkScope,
    required this.idempotencyKey,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final CheckScope checkScope;
  final String idempotencyKey;
  factory QueuedProposalValidationRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'check_scope',
      'idempotency_key',
      'mode',
    });
    if (f.string('mode') != 'queued_proposal') {
      throw const FormatException('Wrong request variant');
    }
    return QueuedProposalValidationRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      checkScope: CheckScope.fromName(wireString(f.require('check_scope'))),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_validate';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('queued_proposal')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('check_scope', CanonicalString(checkScope.wireName)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class InlineValidationRequest extends WorkflowRequest {
  InlineValidationRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required Iterable<DomainOperation> operations,
    required this.checkScope,
  }) : operations = List.unmodifiable(operations);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final List<DomainOperation> operations;
  final CheckScope checkScope;
  factory InlineValidationRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'operations',
      'check_scope',
      'mode',
    });
    if (f.string('mode') != 'inline') {
      throw const FormatException('Wrong request variant');
    }
    return InlineValidationRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      operations: f.array('operations').map((v) => DomainOperation.fromWire(v)),
      checkScope: CheckScope.fromName(wireString(f.require('check_scope'))),
    );
  }
  @override
  String get toolName => 'universe_validate';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('inline')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry('operations', CanonicalArray(operations.map((v) => v.toWire()))),
    MapEntry('check_scope', CanonicalString(checkScope.wireName)),
  ]);
}

final class ProposalValidationRequest extends WorkflowRequest {
  ProposalValidationRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required this.checkScope,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final CheckScope checkScope;
  factory ProposalValidationRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'check_scope',
      'mode',
    });
    if (f.string('mode') != 'proposal') {
      throw const FormatException('Wrong request variant');
    }
    return ProposalValidationRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      checkScope: CheckScope.fromName(wireString(f.require('check_scope'))),
    );
  }
  @override
  String get toolName => 'universe_validate';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('proposal')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('check_scope', CanonicalString(checkScope.wireName)),
  ]);
}

final class AttachAssessmentRequest extends WorkflowRequest {
  AttachAssessmentRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required BigInt expectedSelectionGeneration,
    required this.body,
    required this.idempotencyKey,
  }) : expectedSelectionGeneration = checkedU64(expectedSelectionGeneration);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final BigInt expectedSelectionGeneration;
  final SourceAssessmentV1 body;
  final String idempotencyKey;
  factory AttachAssessmentRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'expected_selection_generation',
      'body',
      'idempotency_key',
      'action',
    });
    if (f.string('action') != 'attach_assessment') {
      throw const FormatException('Wrong request variant');
    }
    return AttachAssessmentRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      expectedSelectionGeneration: f.u64('expected_selection_generation'),
      body: SourceAssessmentV1.fromWire(f.require('body')),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('action', CanonicalString('attach_assessment')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry(
      'expected_selection_generation',
      CanonicalNumber(expectedSelectionGeneration.toString()),
    ),
    MapEntry('body', body.toWire()),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class SelectAssessmentRequest extends WorkflowRequest {
  SelectAssessmentRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required BigInt expectedSelectionGeneration,
    required this.assessmentReference,
    required this.idempotencyKey,
  }) : expectedSelectionGeneration = checkedU64(expectedSelectionGeneration);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final BigInt expectedSelectionGeneration;
  final AssessmentRef? assessmentReference;
  final String idempotencyKey;
  factory SelectAssessmentRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'expected_selection_generation',
      'assessment_reference',
      'idempotency_key',
      'action',
    });
    if (f.string('action') != 'select_assessment') {
      throw const FormatException('Wrong request variant');
    }
    f.require('assessment_reference');
    return SelectAssessmentRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      expectedSelectionGeneration: f.u64('expected_selection_generation'),
      assessmentReference: f.optional(
        'assessment_reference',
        (v) => AssessmentRef.fromWire(v),
      ),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('action', CanonicalString('select_assessment')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry(
      'expected_selection_generation',
      CanonicalNumber(expectedSelectionGeneration.toString()),
    ),
    MapEntry(
      'assessment_reference',
      assessmentReference == null
          ? const CanonicalNull()
          : assessmentReference!.toWire(),
    ),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class CreateProposalRequest extends WorkflowRequest {
  CreateProposalRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required Iterable<DomainOperation> operations,
    required this.submission,
    required this.rationale,
    required this.idempotencyKey,
  }) : operations = List.unmodifiable(operations);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final List<DomainOperation> operations;
  final Submission submission;
  final String rationale;
  final String idempotencyKey;
  factory CreateProposalRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'operations',
      'submission',
      'rationale',
      'idempotency_key',
      'action',
    });
    if (f.string('action') != 'create') {
      throw const FormatException('Wrong request variant');
    }
    return CreateProposalRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      operations: f.array('operations').map((v) => DomainOperation.fromWire(v)),
      submission: Submission.fromName(wireString(f.require('submission'))),
      rationale: wireString(f.require('rationale')),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('action', CanonicalString('create')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry('operations', CanonicalArray(operations.map((v) => v.toWire()))),
    MapEntry('submission', CanonicalString(submission.wireName)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class ReviseProposalRequest extends WorkflowRequest {
  ReviseProposalRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required this.proposalReference,
    required Iterable<DomainOperation> operations,
    required this.submission,
    required this.rationale,
    required this.idempotencyKey,
  }) : operations = List.unmodifiable(operations);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final ProposalRef proposalReference;
  final List<DomainOperation> operations;
  final Submission submission;
  final String rationale;
  final String idempotencyKey;
  factory ReviseProposalRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'proposal_reference',
      'operations',
      'submission',
      'rationale',
      'idempotency_key',
      'action',
    });
    if (f.string('action') != 'revise') {
      throw const FormatException('Wrong request variant');
    }
    return ReviseProposalRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      operations: f.array('operations').map((v) => DomainOperation.fromWire(v)),
      submission: Submission.fromName(wireString(f.require('submission'))),
      rationale: wireString(f.require('rationale')),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('action', CanonicalString('revise')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('operations', CanonicalArray(operations.map((v) => v.toWire()))),
    MapEntry('submission', CanonicalString(submission.wireName)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class SubmitProposalRequest extends WorkflowRequest {
  SubmitProposalRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required this.idempotencyKey,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final String idempotencyKey;
  factory SubmitProposalRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'idempotency_key',
      'action',
    });
    if (f.string('action') != 'submit') {
      throw const FormatException('Wrong request variant');
    }
    return SubmitProposalRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('action', CanonicalString('submit')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class WithdrawProposalRequest extends WorkflowRequest {
  WithdrawProposalRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required this.idempotencyKey,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final String idempotencyKey;
  factory WithdrawProposalRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'idempotency_key',
      'action',
    });
    if (f.string('action') != 'withdraw') {
      throw const FormatException('Wrong request variant');
    }
    return WithdrawProposalRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_propose';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('action', CanonicalString('withdraw')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class GetProposalRequest extends WorkflowRequest {
  GetProposalRequest({
    required this.universe,
    this.universeId,
    required this.proposalId,
    required BigInt version,
    this.cursor,
    this.viewGroup,
    this.assessmentReference,
  }) : version = checkedU64(version);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ProposalId proposalId;
  final BigInt version;
  final String? cursor;
  final ProposalView? viewGroup;
  final AssessmentRef? assessmentReference;
  factory GetProposalRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'proposal_id',
      'version',
      'cursor',
      'view_group',
      'assessment_reference',
    });
    return GetProposalRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      proposalId: ProposalId.parse(wireString(f.require('proposal_id'))),
      version: f.u64('version'),
      cursor: _requestOptional(f, 'cursor', (v) => wireString(v)),
      viewGroup: _requestOptional(
        f,
        'view_group',
        (v) => ProposalView.fromName(wireString(v)),
      ),
      assessmentReference: _requestOptional(
        f,
        'assessment_reference',
        (v) => AssessmentRef.fromWire(v),
      ),
    );
  }
  @override
  String get toolName => 'universe_get_proposal';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('proposal_id', CanonicalString(proposalId.value)),
    MapEntry('version', CanonicalNumber(version.toString())),
    if (cursor != null) MapEntry('cursor', CanonicalString(cursor!)),
    if (viewGroup != null)
      MapEntry('view_group', CanonicalString(viewGroup!.name)),
    if (assessmentReference != null)
      MapEntry('assessment_reference', assessmentReference!.toWire()),
  ]);
}

final class InlineImpactRequest extends WorkflowRequest {
  InlineImpactRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required Iterable<RecordId> changedRecords,
    required this.scope,
    required int byteBudget,
  }) : changedRecords = List.unmodifiable(changedRecords),
       byteBudget = _checkedRequestU32(byteBudget);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final List<RecordId> changedRecords;
  final CheckScope scope;
  final int byteBudget;
  factory InlineImpactRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'changed_records',
      'scope',
      'byte_budget',
      'mode',
    });
    if (f.string('mode') != 'inline') {
      throw const FormatException('Wrong request variant');
    }
    return InlineImpactRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      changedRecords: f
          .array('changed_records')
          .map((v) => RecordId.parse(wireString(v))),
      scope: CheckScope.fromName(wireString(f.require('scope'))),
      byteBudget: _requestU32(f.require('byte_budget')),
    );
  }
  @override
  String get toolName => 'universe_get_impact';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('inline')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry(
      'changed_records',
      CanonicalArray(changedRecords.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('scope', CanonicalString(scope.wireName)),
    MapEntry('byte_budget', CanonicalNumber(byteBudget.toString())),
  ]);
}

final class ProposalImpactRequest extends WorkflowRequest {
  ProposalImpactRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    required this.proposalReference,
    required this.scope,
    required int byteBudget,
  }) : byteBudget = _checkedRequestU32(byteBudget);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final ProposalRef proposalReference;
  final CheckScope scope;
  final int byteBudget;
  factory ProposalImpactRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'proposal_reference',
      'scope',
      'byte_budget',
      'mode',
    });
    if (f.string('mode') != 'proposal') {
      throw const FormatException('Wrong request variant');
    }
    return ProposalImpactRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      scope: CheckScope.fromName(wireString(f.require('scope'))),
      byteBudget: _requestU32(f.require('byte_budget')),
    );
  }
  @override
  String get toolName => 'universe_get_impact';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('proposal')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('scope', CanonicalString(scope.wireName)),
    MapEntry('byte_budget', CanonicalNumber(byteBudget.toString())),
  ]);
}

final class CommitRequest extends WorkflowRequest {
  CommitRequest({
    required this.universe,
    this.universeId,
    required this.proposalReference,
    required this.expectedBaseRevision,
    required this.validationRun,
    required this.idempotencyKey,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ProposalRef proposalReference;
  final RevisionId expectedBaseRevision;
  final ValidationRunId validationRun;
  final String idempotencyKey;
  factory CommitRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'proposal_reference',
      'expected_base_revision',
      'validation_run',
      'idempotency_key',
    });
    return CommitRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      expectedBaseRevision: RevisionId.parse(
        wireString(f.require('expected_base_revision')),
      ),
      validationRun: ValidationRunId.parse(
        wireString(f.require('validation_run')),
      ),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_commit';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry(
      'expected_base_revision',
      CanonicalString(expectedBaseRevision.value),
    ),
    MapEntry('validation_run', CanonicalString(validationRun.value)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class GetOperationIdRequest extends WorkflowRequest {
  GetOperationIdRequest({
    required this.universe,
    this.universeId,
    required this.operationId,
    this.cursor,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final OperationId operationId;
  final String? cursor;
  factory GetOperationIdRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'operation_id',
      'cursor',
      'lookup',
    });
    if (f.string('lookup') != 'id') {
      throw const FormatException('Wrong request variant');
    }
    return GetOperationIdRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      operationId: OperationId.parse(wireString(f.require('operation_id'))),
      cursor: _requestOptional(f, 'cursor', (v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_get_operation';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('lookup', CanonicalString('id')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('operation_id', CanonicalString(operationId.value)),
    if (cursor != null) MapEntry('cursor', CanonicalString(cursor!)),
  ]);
}

final class GetOperationKeyRequest extends WorkflowRequest {
  GetOperationKeyRequest({
    required this.universe,
    this.universeId,
    required this.operationKind,
    required this.idempotencyKey,
    this.cursor,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final OperationKind operationKind;
  final String idempotencyKey;
  final String? cursor;
  factory GetOperationKeyRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'operation_kind',
      'idempotency_key',
      'cursor',
      'lookup',
    });
    if (f.string('lookup') != 'key') {
      throw const FormatException('Wrong request variant');
    }
    return GetOperationKeyRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      operationKind: OperationKind.fromName(
        wireString(f.require('operation_kind')),
      ),
      idempotencyKey: wireString(f.require('idempotency_key')),
      cursor: _requestOptional(f, 'cursor', (v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_get_operation';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('lookup', CanonicalString('key')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('operation_kind', CanonicalString(operationKind.wireName)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
    if (cursor != null) MapEntry('cursor', CanonicalString(cursor!)),
  ]);
}

final class CancelOperationRequest extends WorkflowRequest {
  CancelOperationRequest({
    required this.universe,
    this.universeId,
    required this.operationId,
    required this.idempotencyKey,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final OperationId operationId;
  final String idempotencyKey;
  factory CancelOperationRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'operation_id',
      'idempotency_key',
    });
    return CancelOperationRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      operationId: OperationId.parse(wireString(f.require('operation_id'))),
      idempotencyKey: wireString(f.require('idempotency_key')),
    );
  }
  @override
  String get toolName => 'universe_cancel_operation';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('operation_id', CanonicalString(operationId.value)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}
