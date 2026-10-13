import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

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
