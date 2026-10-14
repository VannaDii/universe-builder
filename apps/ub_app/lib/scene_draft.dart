import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'work_draft.dart' show buildWorldAssociation, worldAssociationInput;

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
RecordNarrativeReferenceOperation sceneOperation(UnfinishedSceneForm form) =>
    RecordNarrativeReferenceOperation(
      clientRef: form.clientRef,
      record: RecordKind.sceneRef,
      payload: SceneRecord(
        workVersion: VersionRef(
          record: RecordId.parse(form.edition.record),
          universe: form.edition.universe.isEmpty
              ? null
              : UniverseId.parse(form.edition.universe),
          version: RecordVersionId.parse(form.editionVersion),
        ),
        sceneId: form.sceneId,
        viewpoint: form.viewpointEnabled ? _reference(form.viewpoint) : null,
        narrationFrame: form.narrationEnabled
            ? _reference(form.narration)
            : null,
        narrativePosition: form.positionEnabled
            ? BigInt.parse(form.position)
            : null,
        disclosedRecords: form.disclosed.map(_reference),
        depictedEvents: form.depicted.map(_reference),
        worldAssociations: form.associations.map((a) {
          WorldAssociation? original;
          if (a.originalOrdinal != null) {
            original = form.original?.worldAssociations.elementAtOrNull(
              a.originalOrdinal!,
            );
            if (original == null) {
              throw const FormatException(
                'Reopen the original scene world associations.',
              );
            }
          }
          return buildWorldAssociation(a, original);
        }),
      ),
    );
UnfinishedSceneForm sceneFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! RecordNarrativeReferenceOperation ||
      operation.record != RecordKind.sceneRef ||
      operation.payload is! SceneRecord) {
    throw const FormatException('Choose a scene reference from Changes.');
  }
  final record = operation.payload as SceneRecord;
  return UnfinishedSceneForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    sceneId: record.sceneId,
    edition: ExpressionReferenceInput(
      record: record.workVersion.record.value,
      universe: record.workVersion.universe?.value ?? '',
    ),
    editionVersion: record.workVersion.version.value,
    viewpointEnabled: record.viewpoint != null,
    viewpoint: _input(record.viewpoint),
    narrationEnabled: record.narrationFrame != null,
    narration: _input(record.narrationFrame),
    positionEnabled: record.narrativePosition != null,
    position: record.narrativePosition?.toString() ?? '',
    disclosed: record.disclosedRecords.map(_input),
    depicted: record.depictedEvents.map(_input),
    associations: [
      for (var i = 0; i < record.worldAssociations.length; i++)
        worldAssociationInput(record.worldAssociations[i], originalOrdinal: i),
    ],
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest sceneDraftRequest({
  required SavedDraft draft,
  required UnfinishedSceneForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this scene declaration.',
    );
  }
  final operation = sceneOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = sceneFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current scene fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This scene declaration is already in Changes. Edit it there.',
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
