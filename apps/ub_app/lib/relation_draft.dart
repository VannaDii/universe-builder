import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

DefineRelationOperation relationOperation(UnfinishedRelationForm form) {
  if ([form.namespace, form.key, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException(
      'Enter a namespace and relation-definition key.',
    );
  }
  final labels = <String, String>{};
  for (final l in form.labels) {
    if (labels.containsKey(l.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[l.language] = l.text;
  }
  return DefineRelationOperation(
    clientRef: form.clientRef,
    record: RelationRecord(
      namespace: form.namespace,
      key: form.key,
      labels: labels,
      roles: form.roles.map(
        (r) => RoleDefinition(
          name: r.name,
          participantTypes: r.participantTypes.map(RecordId.parse),
          multiplicity: Multiplicity.fromName(r.multiplicity),
          ordered: r.ordered,
        ),
      ),
    ),
  );
}

UnfinishedRelationForm relationFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is! DefineRelationOperation) {
    throw const FormatException('Choose a relation definition from Changes.');
  }
  final v = op.record;
  return UnfinishedRelationForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    namespace: v.namespace,
    key: v.key,
    labels: v.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    roles: v.roles.map(
      (r) => RelationRoleInput(
        name: r.name,
        participantTypes: r.participantTypes.map((t) => t.value),
        multiplicity: r.multiplicity.name,
        ordered: r.ordered,
      ),
    ),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest relationDraftRequest({
  required SavedDraft draft,
  required UnfinishedRelationForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this relation definition.',
    );
  }
  final operation = relationOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = relationFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current relation-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This relation definition is already in Changes. Edit it there.',
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
