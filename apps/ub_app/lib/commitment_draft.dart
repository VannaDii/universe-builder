import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'expression_draft.dart';
import 'temporal_validity_draft.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
RecordCommitmentOperation commitmentOperation(UnfinishedCommitmentForm form) {
  TemporalExpression? deadline;
  if (form.deadlineEnabled) {
    final time = buildTemporalValidity(
      form.deadline,
      form.original?.deadline == null
          ? null
          : InstantValidity(form.original!.deadline!),
    );
    if (time is! InstantValidity) {
      throw const FormatException('Choose a deadline time expression.');
    }
    deadline = time.at;
  }
  return RecordCommitmentOperation(
    clientRef: form.clientRef,
    record: CommitmentRecord(
      parties: form.parties.map(
        (p) => CommitmentParty(
          _reference(
            ExpressionReferenceInput(record: p.record, universe: p.universe),
          ),
          p.role,
        ),
      ),
      obligated: _reference(form.obligated),
      conditions: form.conditions.map(buildExpression),
      deadline: deadline,
      status: CommitmentStatus.fromName(form.status),
    ),
  );
}

UnfinishedCommitmentForm commitmentFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! RecordCommitmentOperation) {
    throw const FormatException('Choose a commitment from Changes.');
  }
  final record = operation.record;
  return UnfinishedCommitmentForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    parties: record.parties.map(
      (p) => CommitmentPartyInput(
        record: p.record.record.value,
        universe: p.record.universe?.value ?? '',
        role: p.role,
      ),
    ),
    obligated: _input(record.obligated),
    conditions: record.conditions.map(expressionInput),
    deadlineEnabled: record.deadline != null,
    deadline: record.deadline == null
        ? const TemporalValidityInput(kind: 'instant_unspecified')
        : temporalValidityInput(InstantValidity(record.deadline!)),
    status: record.status.name,
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest commitmentDraftRequest({
  required SavedDraft draft,
  required UnfinishedCommitmentForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this commitment declaration.',
    );
  }
  final operation = commitmentOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = commitmentFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current commitment fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This commitment declaration is already in Changes. Edit it there.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }
    }
    operations.add(operation);
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: DraftContent(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      operations: operations,
      rationale: index == null
          ? [
              if (draft.content.rationale.isNotEmpty) draft.content.rationale,
              if (form.rationale.isNotEmpty) form.rationale,
            ].join('\n\n')
          : draft.content.rationale,
    ),
  );
}
