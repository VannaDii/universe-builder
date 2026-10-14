import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
WorkBinding workVersionBinding(UnfinishedWorkVersionForm form) =>
    switch (form.bindingKind) {
      'unbound' => const UnboundWork(),
      'bound' => BoundWork(
        ContinuityId.parse(form.continuity),
        RevisionId.parse(form.revision),
      ),
      'segments' => SegmentedWork(
        form.segments.map(
          (s) => WorkSegment(
            segment: s.segment,
            continuity: ContinuityId.parse(s.continuity),
            revision: RevisionId.parse(s.revision),
          ),
        ),
      ),
      _ => throw const FormatException('Choose an explicit edition binding.'),
    };
RecordNarrativeReferenceOperation workVersionOperation(
  UnfinishedWorkVersionForm form,
) {
  if (form.bindingTarget != null) {
    throw const FormatException('Use the published edition binding operation.');
  }
  return RecordNarrativeReferenceOperation(
    clientRef: form.clientRef,
    record: RecordKind.workVersion,
    payload: WorkVersionRecord(
      work: _reference(form.work),
      versionLabel: form.versionLabel,
      binding: workVersionBinding(form),
    ),
  );
}

SetWorkBindingOperation workBindingOperation(UnfinishedWorkVersionForm form) {
  if (form.bindingTarget == null || form.expectedRecordVersion == null) {
    throw const FormatException(
      'Open the published edition before changing its binding.',
    );
  }
  return SetWorkBindingOperation(
    record: _reference(form.bindingTarget!),
    expectedVersion: form.expectedRecordVersion!,
    binding: workVersionBinding(form),
  );
}

UnfinishedWorkVersionForm _bindingForm({
  required RevisionId baseRevision,
  required RecordId representedContext,
  required String clientRef,
  required WorkBinding binding,
  ExpressionReferenceInput work = const ExpressionReferenceInput(),
  String versionLabel = '',
  ExpressionReferenceInput? target,
  RecordVersionId? expectedVersion,
  BigInt? draftVersion,
}) => UnfinishedWorkVersionForm(
  baseRevision: baseRevision,
  representedContext: representedContext,
  clientRef: clientRef,
  work: work,
  versionLabel: versionLabel,
  bindingKind: switch (binding) {
    UnboundWork() => 'unbound',
    BoundWork() => 'bound',
    SegmentedWork() => 'segments',
  },
  continuity: binding is BoundWork ? binding.continuity.value : '',
  revision: binding is BoundWork ? binding.revision.value : '',
  segments: binding is SegmentedWork
      ? binding.segments.map(
          (s) => WorkSegmentInput(
            segment: s.segment,
            continuity: s.continuity.value,
            revision: s.revision.value,
          ),
        )
      : [],
  bindingTarget: target,
  expectedRecordVersion: expectedVersion,
  draftVersion: draftVersion,
);
ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
UnfinishedWorkVersionForm workBindingFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  final payload = record.payload;
  if (payload is! WorkVersionRecord) {
    throw const FormatException('Choose a published work edition.');
  }
  return _bindingForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    binding: payload.binding,
    work: _input(payload.work),
    versionLabel: payload.versionLabel,
    target: ExpressionReferenceInput(
      record: record.identity.recordId.value,
      universe: record.identity.universeId.value,
    ),
    expectedVersion: record.recordVersionId,
  );
}

UnfinishedWorkVersionForm workVersionFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is SetWorkBindingOperation) {
    return _bindingForm(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: operation.record.record.value,
      binding: operation.binding,
      target: _input(operation.record),
      expectedVersion: operation.expectedVersion,
      draftVersion: draft.version,
    );
  }
  if (operation is! RecordNarrativeReferenceOperation ||
      operation.record != RecordKind.workVersion ||
      operation.payload is! WorkVersionRecord) {
    throw const FormatException('Choose a work edition from Changes.');
  }
  final payload = operation.payload as WorkVersionRecord;
  return _bindingForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    binding: payload.binding,
    work: _input(payload.work),
    versionLabel: payload.versionLabel,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest workVersionDraftRequest({
  required SavedDraft draft,
  required UnfinishedWorkVersionForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this work edition.',
    );
  }
  final operation = form.bindingTarget == null
      ? workVersionOperation(form)
      : workBindingOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = workVersionFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.bindingTarget?.toWire().toText() !=
            before.bindingTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current edition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is SetWorkBindingOperation &&
          existing is SetWorkBindingOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This edition binding already has a change. Edit it in Changes.',
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
            'This work edition is already in Changes. Edit it there.',
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
