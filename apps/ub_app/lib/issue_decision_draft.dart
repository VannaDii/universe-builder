import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

RecordIssueDecisionOperation issueDecisionOperation(
  UnfinishedIssueDecisionForm form, {
  required PrincipalId principal,
}) {
  if (form.principal != principal) {
    throw const FormatException(
      'Reopen this decision with its author profile.',
    );
  }
  return RecordIssueDecisionOperation(
    clientRef: form.clientRef,
    record: IssueDecisionRecord(
      fingerprints: form.fingerprints.map(FindingFingerprint.new),
      mode: IssueDecisionMode.fromName(form.mode),
      scope: form.scope,
      rationale: form.rationale,
      principal: principal,
    ),
  );
}

UnfinishedIssueDecisionForm issueDecisionFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! RecordIssueDecisionOperation) {
    throw const FormatException('Choose an issue decision from Changes.');
  }
  final record = operation.record;
  return UnfinishedIssueDecisionForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    principal: record.principal,
    mode: record.mode.name,
    fingerprints: record.fingerprints.map((f) => f.value),
    scope: record.scope,
    rationale: record.rationale,
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest issueDecisionDraftRequest({
  required SavedDraft draft,
  required UnfinishedIssueDecisionForm form,
  required Selector universe,
  required ContinuityId continuity,
  required PrincipalId principal,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this issue decision declaration.',
    );
  }
  final operation = issueDecisionOperation(form, principal: principal);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = issueDecisionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current issue decision fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This issue decision declaration is already in Changes. Edit it there.',
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
