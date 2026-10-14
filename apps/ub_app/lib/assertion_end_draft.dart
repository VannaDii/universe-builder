import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'evidence_basis_draft.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
EndAssertionAtOperation assertionEndOperation(UnfinishedAssertionEndForm form) {
  if (form.coordinate.trim().isEmpty) {
    throw const FormatException(
      'Enter an exact ending coordinate in the assertion’s calendar.',
    );
  }
  return EndAssertionAtOperation(
    record: _ref(form.target),
    expectedVersion: form.expectedRecordVersion,
    at: ExactTime(form.calendar, form.coordinate),
    basis: buildEvidenceBasis(form.basis, form.originalBasis),
  );
}

UnfinishedAssertionEndForm assertionEndFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  final payload = record.payload;
  if (payload is! AssertionRecord ||
      payload.validity is! CalendarIntervalValidity) {
    throw const FormatException(
      'Choose an assertion with a declared calendar interval.',
    );
  }
  return UnfinishedAssertionEndForm(
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
    calendar: (payload.validity as CalendarIntervalValidity).calendar,
    originalBasis: payload.basis,
    basis: evidenceBasisInput(payload.basis),
  );
}

UnfinishedAssertionEndForm assertionEndFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is! EndAssertionAtOperation || op.at is! ExactTime) {
    throw const FormatException('Choose an assertion ending from Changes.');
  }
  return UnfinishedAssertionEndForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.record.record.value,
    target: _input(op.record),
    expectedRecordVersion: op.expectedVersion,
    calendar: (op.at as ExactTime).calendar,
    coordinate: (op.at as ExactTime).value,
    originalBasis: op.basis,
    basis: evidenceBasisInput(op.basis),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest assertionEndDraftRequest({
  required SavedDraft draft,
  required UnfinishedAssertionEndForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this assertion ending.',
    );
  }
  final operation = assertionEndOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = assertionEndFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.target.toWire().toText() != before.target.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion ||
        form.calendar != before.calendar) {
      throw const FormatException(
        'The draft changed. Reopen its current assertion-ending fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (existing is EndAssertionAtOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This assertion already has an ending. Edit it in Changes.',
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
            'This assertion ending is already in Changes. Edit it there.',
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
