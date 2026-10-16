import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_browser.dart';
import 'saved_changes.dart';

Future<OpenedContext> openDraftChoiceContext(
  SavedChanges changes,
  SavedDraft draft,
) async => Envelope<OpenedContext>.fromWire(
  await changes.session.call(
    ToolEngineRequest(
      request: OpenContextRequest(
        universe: changes.universe,
        universeId: changes.scope.universe,
        continuityId: changes.scope.continuity,
        revision: ExactRevisionSelector(revisionId: draft.content.baseRevision),
        representedContext: ContextIdSelector(draft.content.representedContext),
        temporalQuery: const TimelessFrameTime(),
        temporalSystems: [],
        perspective: const AuthorPerspective(),
      ),
    ),
  ),
  OpenedContext.fromWire,
).result;

LibraryEntry _library(SavedChanges changes) =>
    LibraryEntry(changes.scope.universe, changes.universe.value);

Future<Envelope<SearchResults>> searchDraftChoices({
  required SavedChanges changes,
  required OpenedContext context,
  required RecordKind? kind,
  String query = '',
  String? cursor,
  int limit = 50,
}) => searchContextRecords(
  session: changes.session,
  universe: _library(changes),
  context: context,
  query: query,
  kind: kind,
  cursor: cursor,
  limit: limit,
);

/// Resolve titles only through the same pinned, permission-checked context.
Future<String> _sourceVersionChoiceLabel(
  SavedChanges changes,
  OpenedContext context,
  RecordId id,
) async {
  final row = await readDraftChoiceVersion(
    changes: changes,
    context: context,
    reference: RecordRef(record: id),
    kind: RecordKind.sourceVersion,
  );
  final source = row.payload as SourceVersionRecord;
  String title;
  try {
    final parent = await readDraftChoiceVersion(
      changes: changes,
      context: context,
      reference: source.source,
      kind: RecordKind.source,
    );
    title = (parent.payload as SourceRecord).label;
    if (title.trim().isEmpty) {
      title = 'Untitled source';
    }
  } on Object {
    title = 'Source title unavailable';
  }
  return '$title · ${source.importTime}';
}

/// Policy configuration packs are not qualifying-source categories. Reads use
/// the same pinned context and normal access checks as the original search.
Future<List<SearchHit>> excludeUniversePolicyChoices({
  required SavedChanges changes,
  required OpenedContext context,
  required Iterable<SearchHit> hits,
}) async {
  final choices = <SearchHit>[];
  for (final hit in hits) {
    if (hit.kind != RecordKind.domainPack) {
      choices.add(hit);
      continue;
    }
    final row = await readDraftChoiceVersion(
      changes: changes,
      context: context,
      reference: RecordRef(universe: changes.scope.universe, record: hit.recordId),
      kind: RecordKind.domainPack,
    );
    if (!isUniversePolicyRecord(row)) {
      choices.add(hit);
    }
  }
  return List.unmodifiable(choices);
}

Future<RecordSummary> readDraftChoiceSummary({
  required SavedChanges changes,
  required OpenedContext context,
  required RecordId record,
  required RecordKind? kind,
}) async {
  final read = await readContextRecordMaterial(
    session: changes.session,
    universe: _library(changes),
    context: context,
    record: record,
    group: FieldGroup.summary,
  );
  if (!read.delivery.complete ||
      read.result.summaries.length != 1 ||
      read.result.summaries.single.recordId != record ||
      (kind != null && read.result.summaries.single.kind != kind)) {
    throw const FormatException('Record is not available for this choice.');
  }
  final summary = read.result.summaries.single;
  if (summary.kind != RecordKind.sourceVersion) {
    return summary;
  }
  return RecordSummary(
    recordId: summary.recordId,
    kind: summary.kind,
    label: await _sourceVersionChoiceLabel(changes, context, record),
  );
}

Future<RecordRef> selectDraftChoice({
  required SavedChanges changes,
  required OpenedContext context,
  required SearchHit hit,
  required RecordKind? kind,
}) async {
  if (kind != null && hit.kind != kind) {
    throw const FormatException('Choose the required record type.');
  }
  final record = await readContextRecord(
    session: changes.session,
    universe: _library(changes),
    context: context,
    record: hit.recordId,
  );
  if (record.payload.recordKind != (kind ?? hit.kind)) {
    throw const FormatException('Choose the required record type.');
  }
  return RecordRef(
    universe: record.identity.universeId,
    record: record.identity.recordId,
  );
}

/// Exact published selection at the draft's pinned revision.
Future<RecordVersion> readDraftChoiceVersion({
  required SavedChanges changes,
  required OpenedContext context,
  required RecordRef reference,
  required RecordKind kind,
}) async {
  if (reference.universe != null &&
      reference.universe != changes.scope.universe) {
    throw const FormatException('Choose a category in this universe.');
  }
  final row = await readContextRecord(
    session: changes.session,
    universe: _library(changes),
    context: context,
    record: reference.record,
  );
  if (row.payload.recordKind != kind) {
    throw const FormatException('Choose the required record type.');
  }
  return row;
}

RecordId worldChoiceRecord(String world) => RecordId.parse(
  '${RecordId.prefix}${WorldId.parse(world).value.substring(WorldId.prefix.length)}',
);
WorldId worldFromChoice(RecordRef record) => WorldId.parse(
  '${WorldId.prefix}${record.record.value.substring(RecordId.prefix.length)}',
);

RecordId calendarChoiceRecord(String calendar) => RecordId.parse(
  '${RecordId.prefix}${CalendarId.parse(calendar).value.substring(CalendarId.prefix.length)}',
);
CalendarId calendarFromChoice(RecordRef record) => CalendarId.parse(
  '${CalendarId.prefix}${record.record.value.substring(RecordId.prefix.length)}',
);

RecordId unitChoiceRecord(String unit) => RecordId.parse(
  '${RecordId.prefix}${UnitId.parse(unit).value.substring(UnitId.prefix.length)}',
);
UnitId unitFromChoice(RecordRef record) => UnitId.parse(
  '${UnitId.prefix}${record.record.value.substring(RecordId.prefix.length)}',
);

RecordId valueDefinitionChoiceRecord(String definition) => RecordId.parse(
  '${RecordId.prefix}${ValueDefinitionId.parse(definition).value.substring(ValueDefinitionId.prefix.length)}',
);
ValueDefinitionId valueDefinitionFromChoice(
  RecordRef record,
) => ValueDefinitionId.parse(
  '${ValueDefinitionId.prefix}${record.record.value.substring(RecordId.prefix.length)}',
);
