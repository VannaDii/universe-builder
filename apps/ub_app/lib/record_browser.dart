import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

/// Projects only the permission-filtered material returned by the service.
/// A relationship must be declared, not inferred from shared evidence.
List<({RecordVersion proposition, List<RecordVersion> assertions})>
dossierRelationships(Records material, UniverseId universe, RecordId entity) {
  final rows = [...material.records, ...material.evidence];
  bool local(RecordRef ref, RecordId id) =>
      ref.record == id && (ref.universe == null || ref.universe == universe);
  final relations = rows
      .where(
        (row) =>
            row.payload is RelationRecord &&
            row.identity.universeId == universe,
      )
      .map((row) => row.identity.recordId)
      .toSet();
  return [
    for (final row in rows)
      if (row.payload
          case PropositionRecord(:final predicate, :final subject, :final roles)
          when row.identity.universeId == universe)
        if ((predicate.universe == null || predicate.universe == universe) &&
            relations.contains(predicate.record) &&
            (local(subject, entity) ||
                roles.any((role) => local(role.participant, entity))))
          (
            proposition: row,
            assertions: [
              for (final candidate in rows)
                if (candidate.payload case AssertionRecord(:final proposition)
                    when candidate.identity.universeId == universe)
                  if (local(proposition, row.identity.recordId)) candidate,
            ],
          ),
  ];
}

String dossierReferenceLabel(
  Records material,
  UniverseId universe,
  RecordRef ref,
) {
  for (final row in [...material.records, ...material.evidence]) {
    if (row.identity.recordId != ref.record ||
        row.identity.universeId != (ref.universe ?? universe)) {
      continue;
    }
    final labels = switch (row.payload) {
      EntityRecord(:final labels) ||
      RelationRecord(:final labels) ||
      EventRecord(:final labels) ||
      CalendarRecord(:final labels) ||
      RepresentedContextRecord(:final labels) => labels,
      _ => const <String, String>{},
    };
    if (labels['en'] case final String label when label.isNotEmpty) {
      return label;
    }
    for (final label in labels.values) {
      if (label.isNotEmpty) return label;
    }
    if (row.payload case EntityRecord(:final names)) {
      if (names.isNotEmpty) return names.first.text;
    }
  }
  return 'Unavailable name (${ref.record.value})';
}

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
