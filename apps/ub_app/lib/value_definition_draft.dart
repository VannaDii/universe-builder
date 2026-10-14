import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'property_draft.dart';

DefineValueOperation valueDefinitionOperation(
  UnfinishedValueDefinitionForm form,
) {
  if ([form.namespace, form.key, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException('Enter a namespace and value-definition key.');
  }
  final labels = <String, String>{};
  for (final l in form.labels) {
    if (labels.containsKey(l.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[l.language] = l.text;
  }
  return DefineValueOperation(
    clientRef: form.clientRef,
    record: ValueDefinitionRecord(
      namespace: form.namespace,
      key: form.key,
      labels: labels,
      fields: form.fields.map(
        (f) => ValueDefinitionField(
          name: f.name,
          shape: buildValueShape(f.shape),
          required: f.required,
          allowsUnknown: f.allowsUnknown,
        ),
      ),
    ),
  );
}

ReviseDefinitionOperation valueDefinitionRevisionOperation(
  UnfinishedValueDefinitionForm form,
) {
  if (form.revisionTarget == null ||
      form.expectedRecordVersion == null ||
      form.original == null) {
    throw const FormatException(
      'Open a published value definition to revise it.',
    );
  }
  final next = valueDefinitionOperation(form).record;
  if (next.namespace != form.original!.namespace ||
      next.key != form.original!.key) {
    throw const FormatException(
      'Value-definition revisions retain namespace and key.',
    );
  }
  final target = form.revisionTarget!;
  return ReviseDefinitionOperation(
    record: RecordRef(
      record: RecordId.parse(target.record),
      universe: target.universe.isEmpty
          ? null
          : UniverseId.parse(target.universe),
    ),
    expectedVersion: form.expectedRecordVersion!,
    replacement: next,
  );
}

UnfinishedValueDefinitionForm valueDefinitionRevisionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! ValueDefinitionRecord) {
    throw const FormatException('Choose a published value definition.');
  }
  return _valueDefinitionForm(
    v: record.payload as ValueDefinitionRecord,
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    revisionTarget: ExpressionReferenceInput(
      record: record.identity.recordId.value,
      universe: record.identity.universeId.value,
    ),
    expectedRecordVersion: record.recordVersionId,
  );
}

UnfinishedValueDefinitionForm valueDefinitionFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is ReviseDefinitionOperation &&
      op.replacement is ValueDefinitionRecord) {
    return _valueDefinitionForm(
      v: op.replacement as ValueDefinitionRecord,
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: op.record.record.value,
      revisionTarget: ExpressionReferenceInput(
        record: op.record.record.value,
        universe: op.record.universe?.value ?? '',
      ),
      expectedRecordVersion: op.expectedVersion,
      draftVersion: draft.version,
    );
  }
  if (op is! DefineValueOperation) {
    throw const FormatException('Choose a value definition from Changes.');
  }
  return _valueDefinitionForm(
    v: op.record,
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    draftVersion: draft.version,
  );
}

UnfinishedValueDefinitionForm _valueDefinitionForm({
  required ValueDefinitionRecord v,
  required RevisionId baseRevision,
  required RecordId representedContext,
  required String clientRef,
  ExpressionReferenceInput? revisionTarget,
  RecordVersionId? expectedRecordVersion,
  BigInt? draftVersion,
}) => UnfinishedValueDefinitionForm(
  baseRevision: baseRevision,
  representedContext: representedContext,
  clientRef: clientRef,
  revisionTarget: revisionTarget,
  expectedRecordVersion: expectedRecordVersion,
  original: revisionTarget == null ? null : v,
  namespace: v.namespace,
  key: v.key,
  labels: v.labels.entries.map(
    (e) => PropertyLabelInput(language: e.key, text: e.value),
  ),
  fields: v.fields.map(
    (f) => ValueDefinitionFieldInput(
      name: f.name,
      shape: valueShapeInput(f.shape),
      required: f.required,
      allowsUnknown: f.allowsUnknown,
    ),
  ),
  draftVersion: draftVersion,
);

SaveDraftEngineRequest valueDefinitionDraftRequest({
  required SavedDraft draft,
  required UnfinishedValueDefinitionForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this value definition.',
    );
  }
  final operation = form.revisionTarget == null
      ? valueDefinitionOperation(form)
      : valueDefinitionRevisionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = valueDefinitionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.revisionTarget?.toWire().toText() !=
            before.revisionTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current value-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is ReviseDefinitionOperation &&
          existing is ReviseDefinitionOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This value definition already has a revision. Edit it in Changes.',
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
            'This value definition is already in Changes. Edit it there.',
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
