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

ReviseItemPowerOperation itemPowerCorrectionOperation(
  UnfinishedItemPowerForm form,
) {
  final old = form.original;
  if (form.correctionTarget == null ||
      form.expectedRecordVersion == null ||
      old == null) {
    throw const FormatException('Open a published item power to correct it.');
  }
  final replacement = itemPowerOperation(form).record;
  if (replacement.item != old.item ||
      replacement.holderPredicate != old.holderPredicate ||
      replacement.powerPredicate != old.powerPredicate ||
      replacement.scope.context != old.scope.context) {
    throw const FormatException(
      'Retain the item, holder property, power property and represented context.',
    );
  }
  return ReviseItemPowerOperation(
    record: _reference(form.correctionTarget!),
    expectedVersion: form.expectedRecordVersion!,
    replacement: replacement,
    rationale: form.rationale,
  );
}

UnfinishedItemPowerForm itemPowerCorrectionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! ItemPowerRecord) {
    throw const FormatException('Choose a published item power.');
  }
  return _powerForm(
    record: record.payload as ItemPowerRecord,
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    correctionTarget: _input(
      RecordRef(
        universe: record.identity.universeId,
        record: record.identity.recordId,
      ),
    ),
    expectedRecordVersion: record.recordVersionId,
  );
}

UnfinishedItemPowerForm itemPowerFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is ReviseItemPowerOperation) {
    return _powerForm(
      record: operation.replacement,
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: operation.record.record.value,
      correctionTarget: _input(operation.record),
      expectedRecordVersion: operation.expectedVersion,
      rationale: operation.rationale,
      draftVersion: draft.version,
    );
  }
  if (operation is! DefineItemPowerOperation) {
    throw const FormatException('Choose an item power from Changes.');
  }
  return _powerForm(
    record: operation.record,
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    draftVersion: draft.version,
  );
}

UnfinishedItemPowerForm _powerForm({
  required ItemPowerRecord record,
  required RevisionId baseRevision,
  required RecordId representedContext,
  required String clientRef,
  ExpressionReferenceInput? correctionTarget,
  RecordVersionId? expectedRecordVersion,
  String rationale = '',
  BigInt? draftVersion,
}) => UnfinishedItemPowerForm(
  baseRevision: baseRevision,
  representedContext: representedContext,
  clientRef: clientRef,
  correctionTarget: correctionTarget,
  expectedRecordVersion: expectedRecordVersion,
  rationale: rationale,
  item: _input(record.item),
  holderPredicate: _input(record.holderPredicate),
  powerPredicate: _input(record.powerPredicate),
  value: qualifierInput('value', record.value),
  scope: scopeInput(record.scope),
  validity: actionValidityInput(record.validity),
  original: record,
  draftVersion: draftVersion,
);

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
  final operation = form.correctionTarget == null
      ? itemPowerOperation(form)
      : itemPowerCorrectionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = itemPowerFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.correctionTarget?.toWire().toText() !=
            before.correctionTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current item power fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is ReviseItemPowerOperation &&
          existing is ReviseItemPowerOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This power already has a correction. Edit it in Changes.',
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
