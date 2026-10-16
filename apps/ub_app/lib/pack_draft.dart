import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'universe_policies.dart';

DefineUniversePolicyOperation universePolicyOperation(UnfinishedPackForm form) {
  if (form.realWorldPolicy == null || form.key.trim().isEmpty) {
    throw const FormatException('Give this policy a name.');
  }
  return DefineUniversePolicyOperation(
    clientRef: form.clientRef,
    key: form.key,
    realWorld: form.realWorldPolicy!,
    activate: form.activatePolicy,
    expectedRootVersion: form.activatePolicy ? form.expectedRootVersion : null,
  );
}

InstallPackOperation packOperation(UnfinishedPackForm form) {
  if ([form.key, form.version, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException('Enter a pack key and exact version.');
  }
  final dependencies = <String, String>{};
  for (final d in form.dependencies) {
    if (d.key.trim().isEmpty ||
        d.version.trim().isEmpty ||
        dependencies.containsKey(d.key)) {
      throw const FormatException(
        'Give each dependency a distinct key and an exact version.',
      );
    }
    dependencies[d.key] = d.version;
  }
  return InstallPackOperation(
    clientRef: form.clientRef,
    record: DomainPackRecord(
      key: form.key,
      version: form.version,
      dependencies: dependencies,
      capabilities: form.capabilities,
      records: form.records.map(RecordId.parse),
    ),
  );
}

UpgradePackOperation packRevisionOperation(UnfinishedPackForm form) {
  if (form.revisionTarget == null ||
      form.expectedRecordVersion == null ||
      form.original == null) {
    throw const FormatException('Open a published domain pack to revise it.');
  }
  final next = packOperation(form).record;
  if (next.key != form.original!.key ||
      (form.draftVersion == null && next.version == form.original!.version)) {
    throw const FormatException(
      'Pack upgrades retain the key and require a different exact version.',
    );
  }
  final target = form.revisionTarget!;
  return UpgradePackOperation(
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

UnfinishedPackForm packRevisionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! DomainPackRecord) {
    throw const FormatException('Choose a published domain pack.');
  }
  return _packForm(
    c: record.payload as DomainPackRecord,
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

UnfinishedPackForm packFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is DefineUniversePolicyOperation) {
    return UnfinishedPackForm(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: op.clientRef, key: op.key,
      realWorldPolicy: op.realWorld, activatePolicy: op.activate,
      expectedRootVersion: op.expectedRootVersion,
      draftVersion: draft.version,
    );
  }
  if (op is UpgradePackOperation) {
    return _packForm(
      c: op.replacement,
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
  if (op is! InstallPackOperation) {
    throw const FormatException('Choose a domain pack from Changes.');
  }
  return _packForm(
    c: op.record,
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    draftVersion: draft.version,
  );
}

UnfinishedPackForm _packForm({
  required DomainPackRecord c,
  required RevisionId baseRevision,
  required RecordId representedContext,
  required String clientRef,
  ExpressionReferenceInput? revisionTarget,
  RecordVersionId? expectedRecordVersion,
  BigInt? draftVersion,
}) => UnfinishedPackForm(
  baseRevision: baseRevision,
  representedContext: representedContext,
  clientRef: clientRef,
  revisionTarget: revisionTarget,
  expectedRecordVersion: expectedRecordVersion,
  original: revisionTarget == null ? null : c,
  key: c.key,
  version: c.version,
  dependencies: c.dependencies.entries.map(
    (e) => PackDependencyInput(key: e.key, version: e.value),
  ),
  capabilities: c.capabilities,
  records: c.records.map((r) => r.value),
  draftVersion: draftVersion,
);

SaveDraftEngineRequest packDraftRequest({
  required SavedDraft draft,
  required UnfinishedPackForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this domain pack.',
    );
  }
  final DomainOperation operation = form.realWorldPolicy != null
          ? universePolicyOperation(form)
          : form.revisionTarget == null
          ? packOperation(form)
          : packRevisionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = packFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.revisionTarget?.toWire().toText() !=
            before.revisionTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current pack fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is UpgradePackOperation &&
          existing is UpgradePackOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This pack already has an upgrade. Edit it in Changes.',
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
            'This pack is already in Changes. Edit it there.',
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
    if (isUniverseRootChange(operation) && operations.any(isUniverseRootChange)) {
      throw const FormatException('A root change is already in Changes. Review or edit it there.');
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
