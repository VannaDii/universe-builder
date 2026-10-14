import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'temporal_validity_draft.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
TemporalExpression _time(
  TemporalValidityInput input,
  TemporalExpression? original,
) {
  final time = buildTemporalValidity(
    input,
    original == null ? null : InstantValidity(original),
  );
  if (time is! InstantValidity) {
    throw const FormatException('Choose a communication time expression.');
  }
  return time.at;
}

RecordCommunicationOperation communicationOperation(
  UnfinishedCommunicationForm form,
) {
  if (form.distorted == null) {
    throw const FormatException(
      'Choose whether this communication was distorted.',
    );
  }
  if (form.actualRecipients.isNotEmpty && !form.receivedEnabled) {
    throw const FormatException(
      'Actual recipients require an authored receipt time.',
    );
  }
  return RecordCommunicationOperation(
    clientRef: form.clientRef,
    record: CommunicationRecord(
      sender: _reference(form.sender),
      intendedRecipients: form.intendedRecipients.map(_reference),
      actualRecipients: form.actualRecipients.map(_reference),
      content: form.content.map(_reference),
      channel: form.channelEnabled ? form.channel : null,
      distorted: form.distorted!,
      sentAt: _time(form.sentAt, form.original?.sentAt),
      receivedAt: form.receivedEnabled
          ? _time(form.receivedAt, form.original?.receivedAt)
          : null,
    ),
  );
}

UnfinishedCommunicationForm communicationFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! RecordCommunicationOperation) {
    throw const FormatException('Choose a communication from Changes.');
  }
  final record = operation.record;
  return UnfinishedCommunicationForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    sender: _input(record.sender),
    intendedRecipients: record.intendedRecipients.map(_input),
    actualRecipients: record.actualRecipients.map(_input),
    content: record.content.map(_input),
    channelEnabled: record.channel != null,
    channel: record.channel ?? '',
    distorted: record.distorted,
    sentAt: temporalValidityInput(InstantValidity(record.sentAt)),
    receivedEnabled: record.receivedAt != null,
    receivedAt: record.receivedAt == null
        ? const TemporalValidityInput(kind: 'instant_unspecified')
        : temporalValidityInput(InstantValidity(record.receivedAt!)),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest communicationDraftRequest({
  required SavedDraft draft,
  required UnfinishedCommunicationForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this communication declaration.',
    );
  }
  final operation = communicationOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = communicationFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current communication fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This communication declaration is already in Changes. Edit it there.',
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
