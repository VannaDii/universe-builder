import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;
import 'expression_draft.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
RecordPlanOperation planOperation(UnfinishedPlanForm form) =>
    RecordPlanOperation(
      clientRef: form.clientRef,
      record: GoalRecord(
        actor: _reference(form.actor),
        desired: form.desiredEnabled ? _reference(form.desired) : null,
        prerequisites: form.prerequisites.map(buildExpression),
        steps: form.steps.map(_reference),
        status: PlanStatus.fromName(form.status),
        validity: buildActionValidity(form.validity, form.original?.validity),
      ),
    );
UnfinishedPlanForm planFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! RecordPlanOperation) {
    throw const FormatException('Choose a plan from Changes.');
  }
  final record = operation.record;
  return UnfinishedPlanForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    actor: _input(record.actor),
    desiredEnabled: record.desired != null,
    desired: _input(record.desired),
    prerequisites: record.prerequisites.map(expressionInput),
    steps: record.steps.map(_input),
    status: record.status.name,
    validity: actionValidityInput(record.validity),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest planDraftRequest({
  required SavedDraft draft,
  required UnfinishedPlanForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this plan declaration.',
    );
  }
  final operation = planOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = planFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current plan fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This plan declaration is already in Changes. Edit it there.',
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
