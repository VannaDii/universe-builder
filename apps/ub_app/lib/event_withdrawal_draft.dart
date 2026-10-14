import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

bool isWithdrawableEvent(RecordPayload payload) =>
    payload is EventRecord &&
    payload.occurrence is SimpleOccurrence &&
    (payload.occurrence as SimpleOccurrence).kind == OccurrenceKind.occurred;

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
WithdrawEventOperation eventWithdrawalOperation(
  UnfinishedEventWithdrawalForm form,
) {
  if (form.rationale.trim().isEmpty) {
    throw const FormatException(
      'Explain why this occurrence is being withdrawn.',
    );
  }
  return WithdrawEventOperation(
    record: _ref(form.target),
    expectedVersion: form.expectedRecordVersion,
    rationale: form.rationale,
  );
}

UnfinishedEventWithdrawalForm eventWithdrawalFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  final payload = record.payload;
  if (!isWithdrawableEvent(payload)) {
    throw const FormatException('Choose a published event marked as occurred.');
  }
  return UnfinishedEventWithdrawalForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    target: _input(
      RecordRef(
        universe: record.identity.universeId,
        record: record.identity.recordId,
      ),
    ),
    expectedRecordVersion: record.recordVersionId,
  );
}

UnfinishedEventWithdrawalForm eventWithdrawalFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is! WithdrawEventOperation) {
    throw const FormatException(
      'Choose an occurrence withdrawal from Changes.',
    );
  }
  return UnfinishedEventWithdrawalForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.record.record.value,
    target: _input(op.record),
    expectedRecordVersion: op.expectedVersion,
    rationale: op.rationale,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest eventWithdrawalDraftRequest({
  required SavedDraft draft,
  required UnfinishedEventWithdrawalForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this occurrence withdrawal.',
    );
  }
  final operation = eventWithdrawalOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = eventWithdrawalFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.target.toWire().toText() != before.target.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current event-withdrawal fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (existing is WithdrawEventOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This event already has a withdrawal. Edit it in Changes.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This occurrence withdrawal is already in Changes. Edit it there.',
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
