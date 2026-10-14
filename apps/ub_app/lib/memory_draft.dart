import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
RecordMemoryOperation memoryOperation(UnfinishedMemoryForm form) {
  if (form.altered == null) {
    throw const FormatException('Choose whether this memory was altered.');
  }
  return RecordMemoryOperation(
    clientRef: form.clientRef,
    record: MemoryRecord(
      holder: _reference(form.holder),
      content: _reference(form.content),
      altered: form.altered!,
      accessibility: form.accessibility,
      alleged: form.allegedEnabled ? _reference(form.alleged) : null,
      validity: buildActionValidity(form.validity, form.original?.validity),
    ),
  );
}

UnfinishedMemoryForm memoryFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! RecordMemoryOperation) {
    throw const FormatException('Choose a memory from Changes.');
  }
  final record = operation.record;
  return UnfinishedMemoryForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    holder: _input(record.holder),
    content: _input(record.content),
    altered: record.altered,
    allegedEnabled: record.alleged != null,
    alleged: _input(record.alleged),
    accessibility: record.accessibility,
    validity: actionValidityInput(record.validity),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest memoryDraftRequest({
  required SavedDraft draft,
  required UnfinishedMemoryForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this memory declaration.',
    );
  }
  final operation = memoryOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = memoryFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current memory fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This memory declaration is already in Changes. Edit it there.',
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
