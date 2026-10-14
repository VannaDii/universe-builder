import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;
import 'qualifier_draft.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
CreateWorkOperation workOperation(UnfinishedWorkForm form) {
  final labels = <String, String>{};
  for (final label in form.labels) {
    if (labels.containsKey(label.language)) {
      throw const FormatException(
        'Give each work label a distinct language key.',
      );
    }
    labels[label.language] = label.text;
  }
  return CreateWorkOperation(
    clientRef: form.clientRef,
    record: WorkRecord(
      kind: WorkKind.fromName(form.kind),
      title: form.title,
      labels: labels,
      sourceRefs: form.sources.map(_reference),
      versions: form.versions.map(RecordId.parse),
      worldAssociations: form.associations.map((a) {
        WorldAssociation? original;
        if (a.originalOrdinal != null) {
          original = form.original?.worldAssociations.elementAtOrNull(
            a.originalOrdinal!,
          );
          if (original == null) {
            throw const FormatException(
              'Reopen the original work associations.',
            );
          }
        }
        return WorldAssociation(
          world: WorldId.parse(a.world),
          role: a.role,
          validity: buildActionValidity(a.validity, original?.validity),
          qualifiers: buildQualifiers(a.qualifiers, original?.qualifiers ?? {}),
        );
      }),
    ),
  );
}

UnfinishedWorkForm workFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! CreateWorkOperation) {
    throw const FormatException('Choose a work from Changes.');
  }
  final record = operation.record;
  return UnfinishedWorkForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    kind: record.kind.wireName,
    title: record.title,
    labels: record.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    sources: record.sourceRefs.map(_input),
    versions: record.versions.map((v) => v.value),
    associations: [
      for (var i = 0; i < record.worldAssociations.length; i++)
        WorkAssociationInput(
          world: record.worldAssociations[i].world.value,
          role: record.worldAssociations[i].role,
          validity: actionValidityInput(record.worldAssociations[i].validity),
          qualifiers: record.worldAssociations[i].qualifiers.entries.map(
            (e) => qualifierInput(e.key, e.value),
          ),
          originalOrdinal: i,
        ),
    ],
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest workDraftRequest({
  required SavedDraft draft,
  required UnfinishedWorkForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this work declaration.',
    );
  }
  final operation = workOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = workFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current work fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This work declaration is already in Changes. Edit it there.',
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
