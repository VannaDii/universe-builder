import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

RecordNarrativeReferenceOperation passageOperation(
  UnfinishedPassageForm form,
) => RecordNarrativeReferenceOperation(
  clientRef: form.clientRef,
  record: RecordKind.passageRef,
  payload: PassageRecord(
    workVersion: VersionRef(
      record: RecordId.parse(form.edition.record),
      universe: form.edition.universe.isEmpty
          ? null
          : UniverseId.parse(form.edition.universe),
      version: RecordVersionId.parse(form.editionVersion),
    ),
    passageId: form.passageId,
    anchor: form.anchorEnabled
        ? RecordRef(
            record: RecordId.parse(form.anchor.record),
            universe: form.anchor.universe.isEmpty
                ? null
                : UniverseId.parse(form.anchor.universe),
          )
        : null,
  ),
);
UnfinishedPassageForm passageFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is! RecordNarrativeReferenceOperation ||
      op.record != RecordKind.passageRef ||
      op.payload is! PassageRecord) {
    throw const FormatException('Choose a passage reference from Changes.');
  }
  final record = op.payload as PassageRecord;
  return UnfinishedPassageForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    passageId: record.passageId,
    edition: ExpressionReferenceInput(
      record: record.workVersion.record.value,
      universe: record.workVersion.universe?.value ?? '',
    ),
    editionVersion: record.workVersion.version.value,
    anchorEnabled: record.anchor != null,
    anchor: ExpressionReferenceInput(
      record: record.anchor?.record.value ?? '',
      universe: record.anchor?.universe?.value ?? '',
    ),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest passageDraftRequest({
  required SavedDraft draft,
  required UnfinishedPassageForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this passage declaration.',
    );
  }
  final operation = passageOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = passageFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current passage fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This passage declaration is already in Changes. Edit it there.',
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
