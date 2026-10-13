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
  required RecordKind kind,
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

Future<RecordSummary> readDraftChoiceSummary({
  required SavedChanges changes,
  required OpenedContext context,
  required RecordId record,
  required RecordKind kind,
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
      read.result.summaries.single.kind != kind) {
    throw const FormatException('Record is not available for this choice.');
  }
  return read.result.summaries.single;
}

Future<RecordRef> selectDraftChoice({
  required SavedChanges changes,
  required OpenedContext context,
  required SearchHit hit,
  required RecordKind kind,
}) async {
  if (hit.kind != kind) {
    throw const FormatException('Choose the required record type.');
  }
  final record = await readContextRecord(
    session: changes.session,
    universe: _library(changes),
    context: context,
    record: hit.recordId,
  );
  if (record.payload.recordKind != kind) {
    throw const FormatException('Choose the required record type.');
  }
  return RecordRef(
    universe: record.identity.universeId,
    record: record.identity.recordId,
  );
}

RecordId worldChoiceRecord(String world) => RecordId.parse(
  '${RecordId.prefix}${WorldId.parse(world).value.substring(WorldId.prefix.length)}',
);
WorldId worldFromChoice(RecordRef record) => WorldId.parse(
  '${WorldId.prefix}${record.record.value.substring(RecordId.prefix.length)}',
);
