import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'action_draft.dart' show actionValidityInput, buildActionValidity;
import 'scope_draft.dart';
import 'qualifier_draft.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
DefineItemPowerOperation itemPowerOperation(UnfinishedItemPowerForm form) {
  if (!{'universe_wide', 'worlds'}.contains(form.scope.applicability)) {
    throw const FormatException(
      'Choose an explicit universe-wide or world scope for this item power.',
    );
  }
  return DefineItemPowerOperation(
    clientRef: form.clientRef,
    record: ItemPowerRecord(
      item: _reference(form.item),
      holderPredicate: _reference(form.holderPredicate),
      powerPredicate: _reference(form.powerPredicate),
      value: buildQualifierValue(form.value, form.original?.value),
      scope: buildScope(form.scope),
      validity: buildActionValidity(form.validity, form.original?.validity),
    ),
  );
}

UnfinishedItemPowerForm itemPowerFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! DefineItemPowerOperation) {
    throw const FormatException('Choose an item power from Changes.');
  }
  final record = operation.record;
  return UnfinishedItemPowerForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    item: _input(record.item),
    holderPredicate: _input(record.holderPredicate),
    powerPredicate: _input(record.powerPredicate),
    value: qualifierInput('value', record.value),
    scope: scopeInput(record.scope),
    validity: actionValidityInput(record.validity),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest itemPowerDraftRequest({
  required SavedDraft draft,
  required UnfinishedItemPowerForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this item power declaration.',
    );
  }
  final operation = itemPowerOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = itemPowerFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current item power fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This item power declaration is already in Changes. Edit it there.',
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
