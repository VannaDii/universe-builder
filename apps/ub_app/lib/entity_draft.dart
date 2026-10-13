import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'temporal_validity_draft.dart';
import 'qualifier_draft.dart';

SaveDraftEngineRequest entityDraftRequest({
  required Selector universe,
  required ContinuityId continuity,
  required UnfinishedEntityForm form,
  required SavedDraft? previous,
}) {
  if (form.name.trim().isEmpty || form.clientRef.trim().isEmpty) {
    throw const FormatException('Enter a name.');
  }
  if (form.worlds.isNotEmpty && form.worldRole.trim().isEmpty) {
    throw const FormatException('Describe the role of the selected worlds.');
  }
  final operation = IntroduceInstanceOperation(
    clientRef: form.clientRef,
    name: _name(form, null),
    classification: form.classification.isEmpty
        ? null
        : RecordId.parse(form.classification),
    worldAssociations: form.worlds.map(
      (world) => WorldAssociation(
        world: world,
        role: form.worldRole,
        validity: const UnspecifiedValidity(),
        qualifiers: {},
      ),
    ),
  );
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this entity.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
    if (ref is CanonicalString && ref.value == operation.clientRef) {
      if (existing.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'This entity reference is already used in Changes. Review that operation before replacing it.',
        );
      }
      return SaveDraftEngineRequest(
        universe: universe,
        continuityId: continuity,
        expectedVersion: previous!.version,
        content: old!,
      );
    }
  }
  if (old?.proposal != null) {
    throw const FormatException(
      'Continue editing separately in Changes before adding to a submitted proposal.',
    );
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: previous?.version ?? BigInt.zero,
    content: DraftContent(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      operations: [...?old?.operations, operation],
      rationale: [
        if (old != null && old.rationale.isNotEmpty) old.rationale,
        if (form.rationale.isNotEmpty) form.rationale,
      ].join('\n\n'),
    ),
  );
}

/// Adds another authored name to an existing identity, retaining its exact
/// opened revision and expected version through recovery and Changes.
SaveDraftEngineRequest entityNameDraftRequest({
  required Selector universe,
  required UniverseId universeId,
  required ContinuityId continuity,
  required RecordId record,
  required UnfinishedEntityForm form,
  required SavedDraft? previous,
}) {
  if (form.name.trim().isEmpty ||
      form.clientRef != record.value ||
      form.expectedRecordVersion == null) {
    throw const FormatException(
      'Enter a name and reopen its published entity.',
    );
  }
  final operation = AddNameOperation(
    record: RecordRef(universe: universeId, record: record),
    expectedVersion: form.expectedRecordVersion!,
    name: _name(form, null),
  );
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this name.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    if (existing is AddNameOperation &&
        existing.record == operation.record &&
        existing.name.toWire().toText() == operation.name.toWire().toText()) {
      if (existing.expectedVersion != operation.expectedVersion) {
        throw const FormatException(
          'Changes already contains this name based on another entity version. Review it before replacing it.',
        );
      }
      return SaveDraftEngineRequest(
        universe: universe,
        continuityId: continuity,
        expectedVersion: previous!.version,
        content: old!,
      );
    }
  }
  if (old?.proposal != null) {
    throw const FormatException(
      'Continue editing separately in Changes before adding to a submitted proposal.',
    );
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: previous?.version ?? BigInt.zero,
    content: DraftContent(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      operations: [...?old?.operations, operation],
      rationale: [
        if (old != null && old.rationale.isNotEmpty) old.rationale,
        if (form.rationale.isNotEmpty) form.rationale,
      ].join('\n\n'),
    ),
  );
}

UnfinishedEntityForm entityFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! IntroduceInstanceOperation) {
    throw const FormatException('Choose a new entity from Changes.');
  }
  return UnfinishedEntityForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    name: operation.name.text,
    nameDetails: EntityNameForm(
      language: operation.name.language,
      community: operation.name.community,
      role: operation.name.role,
    ),
    classification: operation.classification?.value ?? '',
    worldRole: '',
    rationale: '',
    draftVersion: draft.version,
    associations: [
      for (var i = 0; i < operation.worldAssociations.length; i++)
        EntityAssociationForm(
          world: operation.worldAssociations[i].world.value,
          role: operation.worldAssociations[i].role,
          originalOrdinal: i,
          qualifiers: [
            for (final q in operation.worldAssociations[i].qualifiers.entries)
              qualifierInput(q.key, q.value),
          ],
        ),
    ],
  );
}

/// Field edits retain independently authored name metadata and the validity
/// and qualifiers of retained association rows. Associations are not locations.
DraftContent replaceDraftEntity({
  required SavedDraft draft,
  required int index,
  required UnfinishedEntityForm form,
}) {
  final old = entityFormFromDraft(draft, index);
  if (draft.content.proposal != null ||
      form.draftVersion != draft.version ||
      form.clientRef != old.clientRef ||
      form.baseRevision != old.baseRevision ||
      form.representedContext != old.representedContext) {
    throw const FormatException(
      'The draft changed. Reopen its current entity fields before saving.',
    );
  }
  if (form.name.trim().isEmpty) throw const FormatException('Enter a name.');
  final operation =
      draft.content.operations[index] as IntroduceInstanceOperation;
  final edited = IntroduceInstanceOperation(
    clientRef: operation.clientRef,
    name: _name(form, operation.name),
    classification: form.classification.isEmpty
        ? null
        : RecordId.parse(form.classification),
    worldAssociations: form.associations == null
        ? operation.worldAssociations
        : form.associations!.map((a) {
            if (a.role.trim().isEmpty) {
              throw const FormatException(
                'Describe each world association’s role.',
              );
            }
            final world = WorldId.parse(a.world);
            WorldAssociation? original;
            if (a.originalOrdinal != null) {
              if (a.originalOrdinal! < 0 ||
                  a.originalOrdinal! >= operation.worldAssociations.length) {
                throw const FormatException(
                  'The source association changed. Reopen the current draft fields.',
                );
              }
              original = operation.worldAssociations[a.originalOrdinal!];
            }
            return WorldAssociation(
              world: world,
              role: a.role,
              validity: a.temporalValidity != null
                  ? buildTemporalValidity(
                      a.temporalValidity!,
                      original?.validity,
                    )
                  : a.validity ??
                        original?.validity ??
                        const UnspecifiedValidity(),
              qualifiers: a.qualifiers == null
                  ? original?.qualifiers ?? {}
                  : buildQualifiers(a.qualifiers!, original?.qualifiers ?? {}),
            );
          }),
  );
  return DraftContent(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    operations: [
      for (var i = 0; i < draft.content.operations.length; i++)
        i == index ? edited : draft.content.operations[i],
    ],
    rationale: draft.content.rationale,
  );
}

ContextualName _name(UnfinishedEntityForm form, ContextualName? original) {
  final fields = form.nameDetails;
  return ContextualName(
    text: form.name,
    language: fields == null ? original?.language : fields.language,
    community: fields == null ? original?.community : fields.community,
    role: fields == null ? original?.role : fields.role,
    validity: fields?.temporalValidity != null
        ? buildTemporalValidity(fields!.temporalValidity!, original?.validity)
        : fields?.validity ?? original?.validity ?? const UnspecifiedValidity(),
  );
}
