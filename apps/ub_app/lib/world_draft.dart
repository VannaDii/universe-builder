import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

SaveDraftEngineRequest renameWorldDraftRequest({
  required Selector universe,
  required UniverseId universeId,
  required ContinuityId continuity,
  required UnfinishedWorldForm form,
  required SavedDraft? previous,
}) {
  if (form.selector.trim().isEmpty || form.expectedRecordVersion == null) {
    throw const FormatException(
      'Enter a world name and reopen the published world before adding its rename.',
    );
  }
  final operation = RenameWorldSelectorOperation(
    record: RecordRef(universe: universeId, record: form.record),
    expectedVersion: form.expectedRecordVersion!,
    newSelector: form.selector,
  );
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this rename.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    if (existing is RenameWorldSelectorOperation &&
        existing.record == operation.record) {
      if (existing.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'This world already has a different rename in Changes. Review that operation before replacing it.',
        );
      }
      return SaveDraftEngineRequest(
        universe: universe,
        continuityId: continuity,
        expectedVersion: previous!.version,
        content: old!,
      );
    }
  }
  if (old?.proposal != null) {
    throw const FormatException(
      'Continue editing separately in Changes before adding a rename to a submitted proposal.',
    );
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: previous?.version ?? BigInt.zero,
    content: DraftContent(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      operations: [...?old?.operations, operation],
      rationale: [
        if (old != null && old.rationale.isNotEmpty) old.rationale,
        if (form.rationale.isNotEmpty) form.rationale,
      ].join('\n\n'),
    ),
  );
}

SaveDraftEngineRequest worldAliasDraftRequest({
  required Selector universe,
  required UniverseId universeId,
  required ContinuityId continuity,
  required UnfinishedWorldForm form,
  required SavedDraft? previous,
}) {
  if (form.selector.trim().isEmpty || form.expectedRecordVersion == null) {
    throw const FormatException(
      'Enter an alias and reopen the published world before adding it.',
    );
  }
  final operation = AddWorldAliasOperation(
    record: RecordRef(universe: universeId, record: form.record),
    expectedVersion: form.expectedRecordVersion!,
    alias: form.selector,
  );
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this alias.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    if (existing is AddWorldAliasOperation &&
        existing.record == operation.record &&
        existing.alias == operation.alias) {
      if (existing.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'Changes already contains this alias based on another world version. Review that operation before replacing it.',
        );
      }
      return SaveDraftEngineRequest(
        universe: universe,
        continuityId: continuity,
        expectedVersion: previous!.version,
        content: old!,
      );
    }
  }
  if (old?.proposal != null) {
    throw const FormatException(
      'Continue editing separately in Changes before adding an alias to a submitted proposal.',
    );
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: previous?.version ?? BigInt.zero,
    content: DraftContent(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      operations: [...?old?.operations, operation],
      rationale: [
        if (old != null && old.rationale.isNotEmpty) old.rationale,
        if (form.rationale.isNotEmpty) form.rationale,
      ].join('\n\n'),
    ),
  );
}

/// Edits the visible fields without replacing an operation's authored identity
/// or details that this editor does not expose.
DraftContent editWorldDraftFields({
  required DraftContent draft,
  required int index,
  required String selector,
  required String settingType,
  required String englishLabel,
}) {
  if (draft.proposal != null) {
    throw const FormatException(
      'Continue editing separately before changing a submitted proposal.',
    );
  }
  if (selector.trim().isEmpty) {
    throw const FormatException('Enter a world name before saving changes.');
  }
  final operation = draft.operations[index];
  if (operation is! CreateWorldOperation) {
    throw const FormatException(
      'Choose a world creation to edit these fields.',
    );
  }
  final original = operation.record;
  final labels = {...original.labels};
  // An untouched empty value remains exact; explicitly clearing a label removes
  // it, matching the ordinary new-world form's optional label behavior.
  if (englishLabel != (original.labels['en'] ?? '')) {
    if (englishLabel.isEmpty) {
      labels.remove('en');
    } else {
      labels['en'] = englishLabel;
    }
  }
  final operations = [...draft.operations];
  operations[index] = CreateWorldOperation(
    clientRef: operation.clientRef,
    record: WorldRecord(
      selector: selector,
      settingType: settingType == (original.settingType ?? '')
          ? original.settingType
          : settingType.isEmpty
          ? null
          : settingType,
      aliases: original.aliases,
      labels: labels,
      metadata: original.metadata,
    ),
  );
  return DraftContent(
    baseRevision: draft.baseRevision,
    representedContext: draft.representedContext,
    operations: operations,
    rationale: draft.rationale,
  );
}

/// Converts completed fields only when the author explicitly adds them.
SaveDraftEngineRequest worldDraftRequest({
  required Selector universe,
  required ContinuityId continuity,
  required UnfinishedWorldForm form,
  required SavedDraft? previous,
}) {
  if (form.selector.trim().isEmpty) {
    throw const FormatException(
      'Enter a world name before adding it to changes.',
    );
  }
  final operation = CreateWorldOperation(
    clientRef: form.record.value,
    record: WorldRecord(
      selector: form.selector,
      aliases: form.aliases,
      settingType: form.settingType.isEmpty ? null : form.settingType,
      labels: Map.fromEntries(
        form.labels.entries.where((entry) => entry.value.isNotEmpty),
      ),
    ),
  );
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'The saved changes use another revision or context. Review them before combining work.',
    );
  }
  final operations = [...?old?.operations];
  final existing = operations.whereType<CreateWorldOperation>().where(
    (item) => item.clientRef == operation.clientRef,
  );
  if (existing.isNotEmpty) {
    if (existing.single.toWire().toText() != operation.toWire().toText()) {
      throw const FormatException(
        'This world is already in changes with different fields. Edit it there before adding it again.',
      );
    }
    return SaveDraftEngineRequest(
      universe: universe,
      continuityId: continuity,
      expectedVersion: previous!.version,
      content: old!,
    );
  }
  if (old?.proposal != null) {
    throw const FormatException(
      'These changes already have a proposal. Review it before adding more work.',
    );
  }
  operations.add(operation);
  final rationale = [
    if (old != null && old.rationale.isNotEmpty) old.rationale,
    if (form.rationale.isNotEmpty) form.rationale,
  ].join('\n\n');
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: previous?.version ?? BigInt.zero,
    content: DraftContent(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      operations: operations,
      rationale: rationale,
    ),
  );
}
