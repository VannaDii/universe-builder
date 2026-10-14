import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';

ExpressionReferenceInput _input(RecordRef reference) =>
    ExpressionReferenceInput(
      record: reference.record.value,
      universe: reference.universe?.value ?? '',
    );
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
DefinePropositionOperation propositionOperation(
  UnfinishedPropositionForm form,
) {
  return DefinePropositionOperation(
    clientRef: form.clientRef,
    record: PropositionRecord(
      subject: _reference(form.subject),
      predicate: _reference(form.predicate),
      context: _reference(form.context),
      roles: form.roles.map(
        (r) => PropositionRole(
          r.role,
          _reference(
            ExpressionReferenceInput(record: r.record, universe: r.universe),
          ),
        ),
      ),
      quantification: switch (form.quantification) {
        'particular' => Quantification.particular,
        'universal' => Quantification.universal,
        'exists' => Quantification.exists,
        _ => throw const FormatException(
          'Choose the proposition quantification.',
        ),
      },
      value: form.hasValue
          ? buildQualifierValue(form.value, form.original?.value)
          : null,
    ),
  );
}

UnfinishedPropositionForm propositionFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! DefinePropositionOperation) {
    throw const FormatException(
      'Choose a proposition declaration from Changes.',
    );
  }
  final record = operation.record;
  return UnfinishedPropositionForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    subject: _input(record.subject),
    predicate: _input(record.predicate),
    context: _input(record.context),
    roles: record.roles.map(
      (r) => PropositionRoleInput(
        role: r.role,
        record: r.participant.record.value,
        universe: r.participant.universe?.value ?? '',
      ),
    ),
    quantification: record.quantification.wireName,
    hasValue: record.value != null,
    value: record.value == null
        ? const QualifierInput(kind: 'text')
        : qualifierInput('value', record.value!),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest propositionDraftRequest({
  required SavedDraft draft,
  required UnfinishedPropositionForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this proposition declaration.',
    );
  }
  final operation = propositionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = propositionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current proposition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This proposition declaration is already in Changes. Edit it there.',
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
