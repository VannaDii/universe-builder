import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;
import 'scope_draft.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
AddExceptionOperation exceptionOperation(UnfinishedExceptionForm form) =>
    AddExceptionOperation(
      clientRef: form.clientRef,
      record: ExceptionRecord(
        rule: _reference(form.rule),
        ruleVersion: form.ruleVersionEnabled
            ? RecordVersionId.parse(form.ruleVersion)
            : null,
        authorizingDecision: _reference(form.decision),
        scope: buildScope(form.scope),
        validity: buildActionValidity(form.validity, form.original?.validity),
        rationale: form.rationale,
      ),
    );
UnfinishedExceptionForm exceptionFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! AddExceptionOperation) {
    throw const FormatException('Choose an exception from Changes.');
  }
  final record = operation.record;
  return UnfinishedExceptionForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    rule: _input(record.rule),
    ruleVersionEnabled: record.ruleVersion != null,
    ruleVersion: record.ruleVersion?.value ?? '',
    decision: _input(record.authorizingDecision),
    scope: scopeInput(record.scope),
    validity: actionValidityInput(record.validity),
    rationale: record.rationale,
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest exceptionDraftRequest({
  required SavedDraft draft,
  required UnfinishedExceptionForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this exception declaration.',
    );
  }
  final operation = exceptionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = exceptionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current exception fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This exception declaration is already in Changes. Edit it there.',
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
