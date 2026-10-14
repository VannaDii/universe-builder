import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
TombstoneRecordOperation recordRemovalOperation(
  UnfinishedRecordRemovalForm form,
) {
  if (form.rationale.trim().isEmpty) {
    throw const FormatException(
      'Explain why this record is being removed from current canon.',
    );
  }
  return TombstoneRecordOperation(
    record: _ref(form.target),
    expectedVersion: form.expectedRecordVersion,
    rationale: form.rationale,
  );
}

UnfinishedRecordRemovalForm recordRemovalFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  return UnfinishedRecordRemovalForm(
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

UnfinishedRecordRemovalForm recordRemovalFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is! TombstoneRecordOperation) {
    throw const FormatException('Choose an record removal from Changes.');
  }
  return UnfinishedRecordRemovalForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.record.record.value,
    target: _input(op.record),
    expectedRecordVersion: op.expectedVersion,
    rationale: op.rationale,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest recordRemovalDraftRequest({
  required SavedDraft draft,
  required UnfinishedRecordRemovalForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this record removal.',
    );
  }
  final operation = recordRemovalOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = recordRemovalFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.target.toWire().toText() != before.target.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current record-removal fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (existing is TombstoneRecordOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This record already has a removal. Edit it in Changes.',
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
            'This record removal is already in Changes. Edit it there.',
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
