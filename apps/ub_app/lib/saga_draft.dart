import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
CreateSagaOperation sagaOperation(UnfinishedSagaForm form) {
  if (form.membershipTarget != null) {
    throw const FormatException('Use the published saga membership operation.');
  }
  final labels = <String, String>{};
  for (final label in form.labels) {
    if (labels.containsKey(label.language)) {
      throw const FormatException(
        'Give each saga label a distinct language key.',
      );
    }
    labels[label.language] = label.text;
  }
  return CreateSagaOperation(
    clientRef: form.clientRef,
    record: SagaRecord(
      title: form.title,
      labels: labels,
      memberships: form.memberships.map(
        (m) => SagaMembership(
          work: _reference(m.work),
          role: m.role,
          order: m.orderEnabled ? BigInt.parse(m.order) : null,
        ),
      ),
    ),
  );
}

SagaMembership _membership(SagaMembershipInput m) => SagaMembership(
  work: _reference(m.work),
  role: m.role,
  order: m.orderEnabled ? BigInt.parse(m.order) : null,
);
SagaMembershipInput _membershipInput(SagaMembership m) => SagaMembershipInput(
  work: _input(m.work),
  role: m.role,
  orderEnabled: m.order != null,
  order: m.order?.toString() ?? '',
);
SetSagaMembershipOperation sagaMembershipOperation(UnfinishedSagaForm form) {
  if (form.membershipTarget == null ||
      form.expectedRecordVersion == null ||
      form.memberships.length != 1) {
    throw const FormatException(
      'Open a published saga and set one work membership.',
    );
  }
  return SetSagaMembershipOperation(
    record: _reference(form.membershipTarget!),
    expectedVersion: form.expectedRecordVersion!,
    membership: _membership(form.memberships.single),
  );
}

UnfinishedSagaForm sagaMembershipFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! SagaRecord) {
    throw const FormatException('Choose a published saga.');
  }
  return UnfinishedSagaForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    membershipTarget: ExpressionReferenceInput(
      record: record.identity.recordId.value,
      universe: record.identity.universeId.value,
    ),
    expectedRecordVersion: record.recordVersionId,
    memberships: [const SagaMembershipInput()],
  );
}

UnfinishedSagaForm sagaFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is SetSagaMembershipOperation) {
    return UnfinishedSagaForm(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: operation.record.record.value,
      membershipTarget: _input(operation.record),
      expectedRecordVersion: operation.expectedVersion,
      memberships: [_membershipInput(operation.membership)],
      draftVersion: draft.version,
    );
  }
  if (operation is! CreateSagaOperation) {
    throw const FormatException('Choose a saga from Changes.');
  }
  final record = operation.record;
  return UnfinishedSagaForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    title: record.title,
    labels: record.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    memberships: record.memberships.map(
      (m) => SagaMembershipInput(
        work: _input(m.work),
        role: m.role,
        orderEnabled: m.order != null,
        order: m.order?.toString() ?? '',
      ),
    ),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest sagaDraftRequest({
  required SavedDraft draft,
  required UnfinishedSagaForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this saga declaration.',
    );
  }
  final operation = form.membershipTarget == null
      ? sagaOperation(form)
      : sagaMembershipOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = sagaFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.membershipTarget?.toWire().toText() !=
            before.membershipTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current saga fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is SetSagaMembershipOperation &&
          existing is SetSagaMembershipOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This saga already has a membership change. Edit it in Changes.',
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
            'This saga declaration is already in Changes. Edit it there.',
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
