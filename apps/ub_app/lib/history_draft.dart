import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';

bool canRestoreRecordVersion(RecordVersion current, RecordVersion source) =>
    current.identity.universeId == source.identity.universeId &&
    current.identity.recordId == source.identity.recordId &&
    current.identity.recordKind == source.identity.recordKind &&
    current.recordVersionId != source.recordVersionId &&
    !_effectAssertion(current.payload) &&
    !_effectAssertion(source.payload);

bool _effectAssertion(RecordPayload payload) =>
    payload is AssertionRecord && payload.establishedBy != null;

/// A historical version becomes an ordinary compensating proposal operation.
/// Earlier revisions and the currently published record are unchanged.
Future<SavedDraft> stageHistoryRestoration({
  required SavedChanges changes,
  required OpenedContext context,
  required RecordVersion current,
  required RecordVersion source,
  required String rationale,
}) async {
  if (!canRestoreRecordVersion(current, source) ||
      current.identity.universeId != changes.scope.universe) {
    throw const FormatException(
      'Choose a different restorable version of this record.',
    );
  }
  final frame = context.frame;
  if (frame.continuity != changes.scope.continuity ||
      frame.context.record != changes.scope.representedContext) {
    throw const FormatException(
      'Open this record in the draft’s represented context.',
    );
  }
  final draft =
      await changes.load() ??
      SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: frame.revision,
          representedContext: frame.context.record,
          operations: [],
          rationale: '',
        ),
      );
  if (draft.content.proposal != null ||
      draft.content.baseRevision != frame.revision ||
      draft.content.representedContext != frame.context.record) {
    throw const FormatException(
      'Review or rebase Changes before restoring from this revision.',
    );
  }
  final operation = AdoptRecordVersionOperation(
    source: source,
    expectedVersion: current.recordVersionId,
  );
  if (draft.content.operations.any(
    (op) => op.toWire().toText() == operation.toWire().toText(),
  )) {
    return draft;
  }
  return changes.saveContent(
    draft,
    DraftContent(
      baseRevision: frame.revision,
      representedContext: frame.context.record,
      operations: [...draft.content.operations, operation],
      rationale: [
        if (draft.content.rationale.isNotEmpty) draft.content.rationale,
        if (rationale.isNotEmpty && rationale != draft.content.rationale)
          rationale,
      ].join('\n\n'),
    ),
  );
}
