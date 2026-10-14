import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput ref) => RecordRef(
  record: RecordId.parse(ref.record),
  universe: ref.universe.isEmpty ? null : UniverseId.parse(ref.universe),
);

DomainOperation secretOperation(UnfinishedSecretForm form) {
  if (form.readerDisclosed == null) {
    throw const FormatException('Choose whether the reader has been told.');
  }
  final Validity validity;
  switch (form.validityKind) {
    case 'unspecified':
      validity = const UnspecifiedValidity();
    case 'retain':
      if (form.original == null) {
        throw const FormatException('No original validity to retain.');
      }
      validity = form.original!.validity;
    case 'calendar_interval':
      TemporalBound bound(String text, bool unbounded) {
        if (unbounded) return const UnboundedBound();
        if (text.isEmpty) {
          throw const FormatException(
            'Enter the time bound or choose explicitly unbounded.',
          );
        }
        return ExactBound(text);
      }
      validity = CalendarIntervalValidity(
        CalendarId.parse(form.calendar),
        bound(form.start, form.startUnbounded),
        bound(form.end, form.endUnbounded),
      );
    default:
      throw const FormatException('Choose the secret’s time scope.');
  }
  final record = SecretRecord(
    scope: form.scope.map(_reference),
    fictionalKnowers: form.fictionalKnowers.map(_reference),
    readerDisclosed: form.readerDisclosed!,
    concealment: form.hasConcealment ? form.concealment : null,
    validity: validity,
  );
  if (form.revisionTarget != null) {
    if (form.expectedRecordVersion == null) {
      throw const FormatException(
        'The original secret version is unavailable.',
      );
    }
    return ReviseSecretOperation(
      record: _reference(form.revisionTarget!),
      expectedVersion: form.expectedRecordVersion!,
      replacement: record,
    );
  }
  return CreateSecretOperation(clientRef: form.clientRef, record: record);
}

UnfinishedSecretForm _fromSecret({
  required SecretRecord secret,
  required RevisionId revision,
  required RecordId context,
  required String clientRef,
  RecordRef? target,
  RecordVersionId? expected,
  BigInt? draftVersion,
}) => UnfinishedSecretForm(
  baseRevision: revision,
  representedContext: context,
  clientRef: clientRef,
  scope: secret.scope.map(_input),
  fictionalKnowers: secret.fictionalKnowers.map(_input),
  readerDisclosed: secret.readerDisclosed,
  hasConcealment: secret.concealment != null,
  concealment: secret.concealment ?? '',
  validityKind: 'retain',
  original: secret,
  revisionTarget: target == null ? null : _input(target),
  expectedRecordVersion: expected,
  draftVersion: draftVersion,
);

UnfinishedSecretForm secretFormFromDraft(SavedDraft draft, int index) =>
    switch (draft.content.operations[index]) {
      CreateSecretOperation(:final clientRef, :final record) => _fromSecret(
        secret: record,
        revision: draft.content.baseRevision,
        context: draft.content.representedContext,
        clientRef: clientRef,
        draftVersion: draft.version,
      ),
      ReviseSecretOperation(
        :final record,
        :final expectedVersion,
        :final replacement,
      ) =>
        _fromSecret(
          secret: replacement,
          revision: draft.content.baseRevision,
          context: draft.content.representedContext,
          clientRef: record.record.value,
          target: record,
          expected: expectedVersion,
          draftVersion: draft.version,
        ),
      _ => throw const FormatException('Choose a story secret from Changes.'),
    };

UnfinishedSecretForm secretFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! SecretRecord) {
    throw const FormatException('Choose a published story secret.');
  }
  return _fromSecret(
    secret: record.payload as SecretRecord,
    revision: baseRevision,
    context: representedContext,
    clientRef: record.identity.recordId.value,
    target: RecordRef(
      universe: record.identity.universeId,
      record: record.identity.recordId,
    ),
    expected: record.recordVersionId,
  );
}

SaveDraftEngineRequest secretDraftRequest({
  required SavedDraft draft,
  required UnfinishedSecretForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this story secret.',
    );
  }
  final operation = secretOperation(form),
      operations = [...draft.content.operations];
  if (index != null) {
    if (form.draftVersion != draft.version ||
        index < 0 ||
        index >= operations.length ||
        secretFormFromDraft(draft, index).clientRef != form.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen the current secret fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final duplicate =
          operation is CreateSecretOperation &&
              existing is CreateSecretOperation &&
              existing.clientRef == operation.clientRef ||
          operation is ReviseSecretOperation &&
              existing is ReviseSecretOperation &&
              existing.record == operation.record;
      if (duplicate) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This secret is already in Changes. Edit it there.',
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
