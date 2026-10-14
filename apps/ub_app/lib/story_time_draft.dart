import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

SetStoryTimeOperation storyTimeOperation(UnfinishedStoryTimeForm form) {
  if (form.target.universe.isEmpty) {
    throw const FormatException('Choose a context in this universe.');
  }
  final mode = switch (form.mode) {
    'elapsed' => TimeChangeKind.elapsed,
    'time_travel' => TimeChangeKind.timeTravel,
    _ => throw const FormatException('Choose elapsed time or time travel.'),
  };
  form.original.change(form.value, mode, form.reason);
  return SetStoryTimeOperation(
    record: RecordRef(
      record: RecordId.parse(form.target.record),
      universe: UniverseId.parse(form.target.universe),
    ),
    expectedVersion: form.expectedRecordVersion,
    value: form.value,
    mode: mode,
    reason: form.reason,
  );
}

UnfinishedStoryTimeForm storyTimeFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  final payload = record.payload;
  if (payload is! RepresentedContextRecord || payload.chronology == null) {
    throw const FormatException('This context has no authored starting clock.');
  }
  return UnfinishedStoryTimeForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    target: ExpressionReferenceInput(
      record: record.identity.recordId.value,
      universe: record.identity.universeId.value,
    ),
    expectedRecordVersion: record.recordVersionId,
    original: payload.chronology!,
  );
}

UnfinishedStoryTimeForm storyTimeFormFromDraft(
  SavedDraft draft,
  int index,
  RecordVersion source,
) {
  if (index < 0 || index >= draft.content.operations.length) {
    throw const FormatException('Choose a story-time change from Changes.');
  }
  final op = draft.content.operations[index];
  final original = storyTimeFormFromRecord(
    record: source,
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
  );
  if (op is! SetStoryTimeOperation ||
      op.record.record.value != original.target.record ||
      op.record.universe?.value != original.target.universe ||
      op.expectedVersion != source.recordVersionId) {
    throw const FormatException(
      'The pinned story clock does not match these changes.',
    );
  }
  return UnfinishedStoryTimeForm(
    baseRevision: original.baseRevision,
    representedContext: original.representedContext,
    target: original.target,
    expectedRecordVersion: original.expectedRecordVersion,
    original: original.original,
    value: op.value,
    mode: op.mode.wireName,
    reason: op.reason,
    rationale: draft.content.rationale,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest storyTimeDraftRequest({
  required SavedDraft draft,
  required UnfinishedStoryTimeForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this time transition.',
    );
  }
  final operation = storyTimeOperation(form),
      operations = [...draft.content.operations];
  if (index != null) {
    if (index < 0 ||
        index >= operations.length ||
        form.draftVersion != draft.version) {
      throw const FormatException(
        'The draft changed. Reopen its current time transition.',
      );
    }
    final before = operations[index];
    if (before is! SetStoryTimeOperation ||
        before.record != operation.record ||
        before.expectedVersion != operation.expectedVersion) {
      throw const FormatException('Choose the same pinned story clock.');
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (existing is SetStoryTimeOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This clock already has a transition. Edit it in Changes.',
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
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
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
