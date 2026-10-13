import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

Future<Envelope<SearchResults>> searchContextRecords({
  required AppSession session,
  required LibraryEntry universe,
  required OpenedContext context,
  required String query,
  RecordKind? kind,
  String? cursor,
  int limit = 50,
}) async => Envelope<SearchResults>.fromWire(
  await session.call(
    ToolEngineRequest(
      request: SearchRequest(
        universe: Selector(universe.name),
        universeId: universe.id,
        contextId: context.contextId,
        query: query,
        typedFilters: Filters(recordKinds: [?kind]),
        limit: limit,
        cursor: cursor,
      ),
    ),
  ),
  SearchResults.fromWire,
);

Future<Envelope<Records>> readContextRecordMaterial({
  required AppSession session,
  required LibraryEntry universe,
  required OpenedContext context,
  required RecordId record,
  required FieldGroup group,
}) async {
  final result = Envelope<Records>.fromWire(
    await session.call(
      ToolEngineRequest(
        request: GetRequest(
          universe: Selector(universe.name),
          universeId: universe.id,
          contextId: context.contextId,
          recordIds: [record],
          fieldGroups: [group],
        ),
      ),
    ),
    Records.fromWire,
  );
  return result;
}

Future<RecordVersion> readContextRecord({
  required AppSession session,
  required LibraryEntry universe,
  required OpenedContext context,
  required RecordId record,
}) async {
  final result = await readContextRecordMaterial(
    session: session,
    universe: universe,
    context: context,
    record: record,
    group: FieldGroup.payload,
  );
  if (!result.delivery.complete ||
      result.result.records.length != 1 ||
      result.result.records.single.identity.recordId != record) {
    throw const FormatException('This record is not available in full.');
  }
  return result.result.records.single;
}
