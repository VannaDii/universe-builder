import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

UnfinishedSourceForm sourceAnchorFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! AddSourceAnchorOperation) {
    throw const FormatException('Choose a source anchor from Changes.');
  }
  return UnfinishedSourceForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    text: operation.record.excerpt,
    anchorSource: operation.record.sourceVersion,
    staged: [operation],
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest sourceDraftRequest({
  required SavedDraft draft,
  required UnfinishedSourceForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException('Review Changes before adding this source.');
  }
  final anchor = form.anchorSource != null;
  if (anchor
      ? (form.staged.length != 1 ||
            form.staged.single is! AddSourceAnchorOperation)
      : (form.staged.length != 2 ||
            form.staged.any(
              (op) =>
                  op is! RecordNarrativeReferenceOperation ||
                  (op.payload is! SourceRecord &&
                      op.payload is! SourceVersionRecord),
            ))) {
    throw const FormatException(
      'Retain the source before adding it to Changes.',
    );
  }
  final operations = [...draft.content.operations];
  if (index != null) {
    final original = sourceAnchorFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != original.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current source anchor.',
      );
    }
    final updated = form.staged.single;
    if (updated is! AddSourceAnchorOperation ||
        updated.clientRef != original.clientRef) {
      throw const FormatException('Keep this source anchor’s identity.');
    }
    operations[index] = updated;
    return SaveDraftEngineRequest(
      universe: universe,
      continuityId: continuity,
      expectedVersion: draft.version,
      content: DraftContent(
        baseRevision: draft.content.baseRevision,
        representedContext: draft.content.representedContext,
        operations: operations,
        rationale: draft.content.rationale,
      ),
    );
  }
  for (final op in form.staged) {
    final ref = Map.fromEntries(op.toWire().fields)['client_ref'];
    final matching = operations.where(
      (existing) =>
          Map.fromEntries(existing.toWire().fields)['client_ref']?.toText() ==
          ref?.toText(),
    );
    if (matching.isNotEmpty) {
      if (matching.length != 1 ||
          matching.single.toWire().toText() != op.toWire().toText()) {
        throw const FormatException(
          'This source differs from Changes. Review it there.',
        );
      }
    } else {
      operations.add(op);
    }
  }
  final unchanged = operations.length == draft.content.operations.length;
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: unchanged
        ? draft.content
        : DraftContent(
            baseRevision: draft.content.baseRevision,
            representedContext: draft.content.representedContext,
            operations: operations,
            rationale: [
              if (draft.content.rationale.isNotEmpty) draft.content.rationale,
              if (form.rationale.isNotEmpty) form.rationale,
            ].join('\n\n'),
          ),
  );
}
