import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';

final class ContinuityDifference {
  const ContinuityDifference({
    required this.record,
    required this.kind,
    required this.label,
    required this.targetVersion,
    required this.sourceVersion,
  });
  final RecordId record;
  final RecordKind kind;
  final String label;
  final RecordVersionId? targetVersion, sourceVersion;
  factory ContinuityDifference.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'record_id',
      'kind',
      'label',
      'target_version',
      'source_version',
    });
    return ContinuityDifference(
      record: RecordId.parse(f.string('record_id')),
      kind: RecordKind.parse(f.string('kind')),
      label: f.string('label'),
      targetVersion: f.optional(
        'target_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      sourceVersion: f.optional(
        'source_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
    );
  }
  String get change => sourceVersion == null
      ? 'Remove from target'
      : targetVersion == null
      ? 'Add to target'
      : 'Replace target version';
}

Future<List<ContinuityDifference>> compareContinuities(
  SavedChanges changes,
  ContinuitySummary target,
  ContinuitySummary source,
) async {
  final request = CompareContinuitiesEngineRequest(
    universe: changes.universe,
    target: target.id,
    targetRevision: target.revisionId,
    source: source.id,
    sourceRevision: source.revisionId,
  );
  final f = WireFields(await changes.session.call(request), {
    'differences',
    'target_revision',
    'source_revision',
  });
  _pins(f, target, source);
  return f.array('differences').map(ContinuityDifference.fromWire).toList();
}

void _pins(
  WireFields fields,
  ContinuitySummary target,
  ContinuitySummary source,
) {
  if (fields.string('target_revision') != target.revisionId.value ||
      fields.string('source_revision') != source.revisionId.value) {
    throw const FormatException('Comparison editions changed. Compare again.');
  }
}

Future<SavedDraft> stageContinuityAdoption({
  required SavedChanges changes,
  required ContinuitySummary target,
  required ContinuitySummary source,
  required Iterable<RecordId> selected,
  required String rationale,
}) async {
  final ids = selected.toList();
  if (ids.isEmpty || ids.length > 100 || ids.toSet().length != ids.length) {
    throw const FormatException('Select 1–100 distinct changes.');
  }
  if (changes.scope.continuity != target.id ||
      changes.scope.representedContext == null) {
    throw const FormatException(
      'Open a represented context in the target continuity.',
    );
  }
  final draft =
      await changes.load() ??
      SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: target.revisionId,
          representedContext: changes.scope.representedContext!,
          operations: [],
          rationale: '',
        ),
      );
  if (draft.content.proposal != null ||
      draft.content.baseRevision != target.revisionId ||
      draft.content.representedContext != changes.scope.representedContext) {
    throw const FormatException(
      'Review or rebase target Changes before adding this selection.',
    );
  }
  final f = WireFields(
    await changes.session.call(
      PrepareAdoptionEngineRequest(
        universe: changes.universe,
        target: target.id,
        targetRevision: target.revisionId,
        source: source.id,
        sourceRevision: source.revisionId,
        recordIds: ids,
      ),
    ),
    {'operations', 'target_revision', 'source_revision'},
  );
  _pins(f, target, source);
  final operations = [...draft.content.operations];
  final existing = operations.map((op) => op.toWire().toText()).toSet();
  for (final row in f.array('operations')) {
    final operation = DomainOperation.fromWire(row);
    if (operation is! AdoptRecordVersionOperation &&
        operation is! TombstoneRecordOperation) {
      throw const FormatException('Unexpected adoption operation.');
    }
    if (existing.add(operation.toWire().toText())) operations.add(operation);
  }
  if (operations.length == draft.content.operations.length) return draft;
  final next = DraftContent(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    operations: operations,
    rationale: [
      if (draft.content.rationale.isNotEmpty) draft.content.rationale,
      if (rationale.isNotEmpty && rationale != draft.content.rationale)
        rationale,
    ].join('\n\n'),
  );
  return next.toWire().toText() == draft.content.toWire().toText()
      ? draft
      : changes.saveContent(draft, next);
}
