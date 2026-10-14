import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'scope_draft.dart';
import 'action_draft.dart' show actionValidityInput, buildActionValidity;

ExpressionReferenceInput _input(RecordRef reference) =>
    ExpressionReferenceInput(
      record: reference.record.value,
      universe: reference.universe?.value ?? '',
    );
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
SetCompletenessOperation completenessOperation(
  UnfinishedCompletenessForm form,
) {
  if (form.predicate.trim().isEmpty) {
    throw const FormatException('Choose a completeness predicate.');
  }
  return SetCompletenessOperation(
    clientRef: form.clientRef,
    record: CompletenessRecord(
      subject: _reference(form.subject),
      predicate: form.predicate,
      members: form.members.map(_reference),
      completeness: switch (form.kind) {
        'objective_reality' => const ObjectiveCompleteness(),
        'observer_known' => ObserverCompleteness(RecordId.parse(form.observer)),
        _ => throw const FormatException(
          'Choose objective or observer-known completeness.',
        ),
      },
      scope: buildScope(form.scope),
      validity: buildActionValidity(form.validity, form.original?.validity),
    ),
  );
}

UnfinishedCompletenessForm completenessFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! SetCompletenessOperation) {
    throw const FormatException(
      'Choose a completeness declaration from Changes.',
    );
  }
  final record = operation.record;
  return UnfinishedCompletenessForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    subject: _input(record.subject),
    predicate: record.predicate,
    members: record.members.map(_input),
    kind: record.completeness is ObjectiveCompleteness
        ? 'objective_reality'
        : 'observer_known',
    observer: record.completeness is ObserverCompleteness
        ? (record.completeness as ObserverCompleteness).observer.value
        : '',
    scope: scopeInput(record.scope),
    validity: actionValidityInput(record.validity),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest completenessDraftRequest({
  required SavedDraft draft,
  required UnfinishedCompletenessForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this completeness declaration.',
    );
  }
  final operation = completenessOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = completenessFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current completeness fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This completeness declaration is already in Changes. Edit it there.',
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
