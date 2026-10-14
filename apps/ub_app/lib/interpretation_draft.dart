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
ReviseInterpretationOperation interpretationOperation(
  UnfinishedInterpretationForm form,
) => ReviseInterpretationOperation(
  record: _ref(form.target),
  expectedVersion: form.expectedRecordVersion,
  interpretation: form.interpretationEnabled ? _ref(form.interpretation) : null,
  rationale: form.rationale,
);
UnfinishedInterpretationForm interpretationFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  final payload = record.payload;
  if (payload is! EpistemicAttitudeRecord ||
      payload.attitude != EpistemicAttitudeKind.knows ||
      payload.acquisition?.basis is! CommunicationKnowledge) {
    throw const FormatException(
      'Choose existing knowledge acquired from a communication receipt.',
    );
  }
  final basis = payload.acquisition!.basis as CommunicationKnowledge;
  return UnfinishedInterpretationForm(
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
    interpretationEnabled: basis.interpretation != null,
    interpretation: _input(basis.interpretation),
  );
}

UnfinishedInterpretationForm interpretationFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is! ReviseInterpretationOperation) {
    throw const FormatException(
      'Choose an interpretation correction from Changes.',
    );
  }
  return UnfinishedInterpretationForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.record.record.value,
    target: _input(op.record),
    expectedRecordVersion: op.expectedVersion,
    interpretationEnabled: op.interpretation != null,
    interpretation: _input(op.interpretation),
    rationale: op.rationale,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest interpretationDraftRequest({
  required SavedDraft draft,
  required UnfinishedInterpretationForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this interpretation declaration.',
    );
  }
  final operation = interpretationOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = interpretationFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.target.toWire().toText() != before.target.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current interpretation fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (existing is ReviseInterpretationOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This knowledge already has an interpretation correction. Edit it in Changes.',
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
            'This interpretation declaration is already in Changes. Edit it there.',
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
