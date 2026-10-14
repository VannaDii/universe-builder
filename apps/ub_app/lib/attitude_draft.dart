import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;
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
KnowledgeAcquisitionInput acquisitionInput(KnowledgeAcquisition? acquisition) {
  if (acquisition == null) return const KnowledgeAcquisitionInput();
  final basis = acquisition.basis;
  return KnowledgeAcquisitionInput(
    enabled: true,
    truthContext: _input(acquisition.truthContext),
    time: temporalValidityInput(InstantValidity(acquisition.time)),
    worldEnabled: acquisition.world != null,
    world: _input(acquisition.world),
    basis: basis is AuthorEstablishedKnowledge
        ? 'author_established'
        : 'communication_receipt',
    communication: _input(
      basis is CommunicationKnowledge ? basis.communication : null,
    ),
    interpretationEnabled:
        basis is CommunicationKnowledge && basis.interpretation != null,
    interpretation: _input(
      basis is CommunicationKnowledge ? basis.interpretation : null,
    ),
  );
}

KnowledgeAcquisition? buildAcquisition(
  KnowledgeAcquisitionInput input,
  KnowledgeAcquisition? original,
) {
  if (!input.enabled) return null;
  final time = buildTemporalValidity(
    input.time,
    original == null ? null : InstantValidity(original.time),
  );
  if (time is! InstantValidity) {
    throw const FormatException('Choose an acquisition time expression.');
  }
  return KnowledgeAcquisition(
    truthContext: _reference(input.truthContext),
    time: time.at,
    world: input.worldEnabled ? _reference(input.world) : null,
    basis: switch (input.basis) {
      'author_established' => const AuthorEstablishedKnowledge(),
      'communication_receipt' => CommunicationKnowledge(
        communication: _reference(input.communication),
        interpretation: input.interpretationEnabled
            ? _reference(input.interpretation)
            : null,
      ),
      _ => throw const FormatException(
        'Choose the knowledge acquisition basis.',
      ),
    },
  );
}

AddBeliefOperation attitudeOperation(UnfinishedAttitudeForm form) {
  if (form.basis.kind == 'retain' && form.original == null) {
    throw const FormatException('Choose a source basis for this new attitude.');
  }
  return AddBeliefOperation(
    clientRef: form.clientRef,
    record: EpistemicAttitudeRecord(
      holder: _reference(form.holder),
      proposition: _reference(form.proposition),
      attitude: EpistemicAttitudeKind.fromName(form.attitude),
      certainty: form.certaintyEnabled ? form.certainty : null,
      validity: buildActionValidity(form.validity, form.original?.validity),
      basis: buildEvidenceBasis(
        form.basis,
        form.original?.basis ?? const AuthorDecisionBasis(''),
      ),
      acquisition: buildAcquisition(
        form.acquisition,
        form.original?.acquisition,
      ),
    ),
  );
}

UnfinishedAttitudeForm attitudeFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! AddBeliefOperation) {
    throw const FormatException('Choose an attitude from Changes.');
  }
  final record = operation.record;
  return UnfinishedAttitudeForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    holder: _input(record.holder),
    proposition: _input(record.proposition),
    attitude: record.attitude.name,
    certaintyEnabled: record.certainty != null,
    certainty: record.certainty ?? '',
    validity: actionValidityInput(record.validity),
    basis: evidenceBasisInput(record.basis),
    acquisition: acquisitionInput(record.acquisition),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest attitudeDraftRequest({
  required SavedDraft draft,
  required UnfinishedAttitudeForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this attitude declaration.',
    );
  }
  final operation = attitudeOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = attitudeFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current attitude fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This attitude declaration is already in Changes. Edit it there.',
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
