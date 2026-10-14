import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'attribute_draft.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
AttributeEvidence assertionCorrectionEvidence(AssertionRecord assertion) =>
    AttributeEvidence(
      attributeMode: assertion.attributeMode,
      polarity: assertion.polarity,
      scope: assertion.scope,
      validity: assertion.validity,
      persistence: assertion.persistence,
      precision: assertion.precision,
      alternatives: assertion.alternatives,
      basis: assertion.basis,
    );
SupersedeAssertionOperation assertionCorrectionOperation(
  UnfinishedAssertionCorrectionForm form,
) {
  if (form.rationale.trim().isEmpty) {
    throw const FormatException(
      'Explain why this assertion is being corrected.',
    );
  }
  final evidence = editAttributeEvidence(
    form.evidence,
    assertionCorrectionEvidence(form.original),
  );
  return SupersedeAssertionOperation(
    record: _ref(form.target),
    expectedVersion: form.expectedRecordVersion,
    replacement: AssertionRecord(
      proposition: _ref(form.proposition),
      attributeMode: evidence.attributeMode,
      polarity: evidence.polarity,
      scope: evidence.scope,
      validity: evidence.validity,
      persistence: evidence.persistence,
      precision: evidence.precision,
      alternatives: evidence.alternatives,
      basis: evidence.basis,
      establishedBy: form.original.establishedBy,
    ),
    rationale: form.rationale,
  );
}

UnfinishedAssertionCorrectionForm assertionCorrectionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  final payload = record.payload;
  if (payload is! AssertionRecord) {
    throw const FormatException('Choose a published assertion to correct.');
  }
  return UnfinishedAssertionCorrectionForm(
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
    original: payload,
    proposition: _input(payload.proposition),
  );
}

UnfinishedAssertionCorrectionForm assertionCorrectionFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is! SupersedeAssertionOperation) {
    throw const FormatException('Choose an assertion correction from Changes.');
  }
  return UnfinishedAssertionCorrectionForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.record.record.value,
    target: _input(op.record),
    expectedRecordVersion: op.expectedVersion,
    original: op.replacement,
    proposition: _input(op.replacement.proposition),
    rationale: op.rationale,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest assertionCorrectionDraftRequest({
  required SavedDraft draft,
  required UnfinishedAssertionCorrectionForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this assertion correction.',
    );
  }
  final operation = assertionCorrectionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = assertionCorrectionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.target.toWire().toText() != before.target.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current assertion-correction fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (existing is SupersedeAssertionOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This assertion already has a correction. Edit it in Changes.',
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
            'This assertion correction is already in Changes. Edit it there.',
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
