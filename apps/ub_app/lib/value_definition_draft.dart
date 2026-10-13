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

UnfinishedValueDefinitionForm valueDefinitionFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final op = draft.content.operations[index];
  if (op is! DefineValueOperation) {
    throw const FormatException('Choose a value definition from Changes.');
  }
  final v = op.record;
  return UnfinishedValueDefinitionForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
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
    draftVersion: draft.version,
  );
}

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
  final operation = valueDefinitionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = valueDefinitionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current value-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
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
