import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;
import 'scope_draft.dart';
import 'expression_draft.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
SetCreativeBoundaryOperation boundaryOperation(UnfinishedBoundaryForm form) =>
    SetCreativeBoundaryOperation(
      clientRef: form.clientRef,
      record: BoundaryRecord(
        key: form.key,
        area: switch (form.areaKind) {
          'record' => RecordBoundaryArea(_reference(form.record)),
          'predicate' => PredicateBoundaryArea(
            form.predicate,
            form.subjectEnabled ? _reference(form.subject) : null,
          ),
          'category' => CategoryBoundaryArea(RecordId.parse(form.category)),
          _ => throw const FormatException('Choose a boundary area.'),
        },
        mode: BoundaryMode.fromName(form.mode),
        constraints: form.constraints.map(buildExpression),
        scope: buildScope(form.scope),
        validity: buildActionValidity(form.validity, form.original?.validity),
      ),
    );
UnfinishedBoundaryForm boundaryFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! SetCreativeBoundaryOperation) {
    throw const FormatException('Choose a creative boundary from Changes.');
  }
  final record = operation.record;
  return UnfinishedBoundaryForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    key: record.key,
    areaKind: switch (record.area) {
      RecordBoundaryArea() => 'record',
      PredicateBoundaryArea() => 'predicate',
      CategoryBoundaryArea() => 'category',
    },
    record: _input(
      record.area is RecordBoundaryArea
          ? (record.area as RecordBoundaryArea).record
          : null,
    ),
    predicate: record.area is PredicateBoundaryArea
        ? (record.area as PredicateBoundaryArea).predicate
        : '',
    subjectEnabled:
        record.area is PredicateBoundaryArea &&
        (record.area as PredicateBoundaryArea).subject != null,
    subject: _input(
      record.area is PredicateBoundaryArea
          ? (record.area as PredicateBoundaryArea).subject
          : null,
    ),
    category: record.area is CategoryBoundaryArea
        ? (record.area as CategoryBoundaryArea).entityType.value
        : '',
    mode: record.mode.wireName,
    constraints: record.constraints.map(expressionInput),
    scope: scopeInput(record.scope),
    validity: actionValidityInput(record.validity),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest boundaryDraftRequest({
  required SavedDraft draft,
  required UnfinishedBoundaryForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this boundary declaration.',
    );
  }
  final operation = boundaryOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = boundaryFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current boundary fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This boundary declaration is already in Changes. Edit it there.',
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
