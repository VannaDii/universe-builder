import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'evidence_basis_draft.dart';
import 'temporal_validity_draft.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
RecordObservationOperation observationOperation(
  UnfinishedObservationForm form,
) {
  if (form.sensoryAccess == null) {
    throw const FormatException(
      'Choose whether this observer had sensory access.',
    );
  }
  if (form.basis.kind == 'retain' && form.original == null) {
    throw const FormatException(
      'Choose a source basis for this new observation.',
    );
  }
  final time = buildTemporalValidity(
    form.time,
    form.original == null ? null : InstantValidity(form.original!.time),
  );
  if (time is! InstantValidity) {
    throw const FormatException('Choose an observation time expression.');
  }
  return RecordObservationOperation(
    clientRef: form.clientRef,
    record: ObservationRecord(
      observer: _reference(form.observer),
      observed: _reference(form.observed),
      sensoryAccess: form.sensoryAccess!,
      time: time.at,
      interpretation: form.interpretationEnabled
          ? _reference(form.interpretation)
          : null,
      basis: buildEvidenceBasis(
        form.basis,
        form.original?.basis ?? const AuthorDecisionBasis(''),
      ),
    ),
  );
}

UnfinishedObservationForm observationFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! RecordObservationOperation) {
    throw const FormatException('Choose an observation from Changes.');
  }
  final record = operation.record;
  return UnfinishedObservationForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    observer: _input(record.observer),
    observed: _input(record.observed),
    sensoryAccess: record.sensoryAccess,
    time: temporalValidityInput(InstantValidity(record.time)),
    interpretationEnabled: record.interpretation != null,
    interpretation: _input(record.interpretation),
    basis: evidenceBasisInput(record.basis),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest observationDraftRequest({
  required SavedDraft draft,
  required UnfinishedObservationForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this observation declaration.',
    );
  }
  final operation = observationOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = observationFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current observation fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This observation declaration is already in Changes. Edit it there.',
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
