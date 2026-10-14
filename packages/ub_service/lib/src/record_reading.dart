import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show StoredVersion, recordDependencies;

Set<RecordId> _dependencies(RecordVersion row) => recordDependencies(
  StoredVersion(
    versionId: row.recordVersionId,
    identity: row.identity,
    payload: row.payload.toWire(),
    digest: row.payloadDigest,
  ),
);

String recordReadLabel(RecordVersion row) {
  String? first(Map<String, String> labels) {
    if (labels.isEmpty) return null;
    return wireString(
      CanonicalObject(
        labels.entries.map(
          (entry) => MapEntry(entry.key, CanonicalString(entry.value)),
        ),
      ).fields.first.value,
    );
  }

  return switch (row.payload) {
    EntityRecord(:final labels, :final names) =>
      first(labels) ??
          (names.isEmpty ? row.identity.recordId.value : names.first.text),
    WorldRecord(:final selector) => selector,
    BoundaryRecord(:final key) => key,
    RealmRecord(:final labels) => first(labels) ?? row.identity.recordId.value,
    AnchorRecord(:final excerpt) => excerpt,
    RepresentedContextRecord(:final labels, :final kind) =>
      first(labels) ??
          (kind is AuthoredContext ? kind.label : row.identity.recordId.value),
    WorkRecord(:final title) => title,
    SagaRecord(:final title) => title,
    AppearanceRecord(:final label) => label,
    ImageAssetRecord(:final originalName) => originalName,
    SourceRecord(:final label) => label,
    EntityTypeRecord(:final labels, :final key) => first(labels) ?? key,
    PropertyRecord(:final labels, :final key) => first(labels) ?? key,
    RelationRecord(:final labels, :final key) => first(labels) ?? key,
    ActionDefinitionRecord(:final labels, :final key) => first(labels) ?? key,
    EventRecord(:final labels) => first(labels) ?? row.identity.recordId.value,
    UnitRecord(:final labels, :final key) => first(labels) ?? key,
    ValueDefinitionRecord(:final labels, :final key) => first(labels) ?? key,
    CalendarRecord(:final labels, :final key) => first(labels) ?? key,
    RuleRecord(:final labels, :final namespace, :final key) =>
      first(labels) ?? '$namespace:$key',
    _ => row.identity.recordId.value,
  };
}

/// Run only over records already admitted by permissions and perspective.
/// Appearance attachments follow their entries; cycles are visited once.
Set<RecordId> readDependencyClosure(
  List<RecordVersion> records,
  Iterable<RecordId> seeds,
) {
  final byId = {for (final row in records) row.identity.recordId: row};
  final pending = seeds.toList();
  final attachments = <RecordId, List<RecordId>>{};
  for (final row in records) {
    if (row.payload case AppearanceRecord(:final target)) {
      switch (target) {
        case UniverseAppearance():
          pending.add(row.identity.recordId);
        case EntryAppearance(:final entry):
          attachments
              .putIfAbsent(entry.record, () => [])
              .add(row.identity.recordId);
      }
    }
  }
  final visited = <RecordId>{};
  var edges = 0;
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    final row = byId[id];
    if (row == null || !visited.add(id)) continue;
    pending.addAll(attachments[id] ?? []);
    final dependencies = _dependencies(row);
    edges += dependencies.length;
    if (edges > 5000000) {
      throw const EvaluationLimitReachedError(
        message: 'dependency traversal budget exceeded',
      );
    }
    pending.addAll(dependencies);
  }
  return Set.unmodifiable(visited);
}

/// Research includes authored evidence about a subject, but does not follow
/// reverse context/predicate edges into unrelated assertions.
Set<RecordId> readResearchClosure(
  List<RecordVersion> records,
  Iterable<RecordId> seeds,
) => readResearchSelection(records, seeds).$1;

(Set<RecordId>, bool) readResearchSelection(
  List<RecordVersion> records,
  Iterable<RecordId> seeds,
) {
  final edges = <RecordId, List<RecordId>>{};
  final pending = seeds.toList();
  var count = 0;
  for (final row in records) {
    final id = row.identity.recordId;
    final dependencies = _dependencies(row);
    final targets = switch (row.payload) {
      PropositionRecord(:final context, :final predicate) =>
        dependencies
            .where((id) => id != context.record && id != predicate.record)
            .toList(),
      AssertionRecord(:final proposition) => [proposition.record],
      CompletenessRecord(:final subject) => [subject.record],
      EpistemicAttitudeRecord(:final holder, :final proposition) => [
        holder.record,
        proposition.record,
      ],
      CommunicationRecord(
        :final intendedRecipients,
        :final actualRecipients,
        :final content,
        :final sender,
      ) =>
        [
          ...intendedRecipients,
          ...actualRecipients,
          ...content,
          sender,
        ].map((r) => r.record).toList(),
      ObservationRecord(
        :final observer,
        :final observed,
        :final interpretation,
      ) =>
        [
          observer.record,
          observed.record,
          if (interpretation != null) interpretation.record,
        ],
      PassageRecord(:final anchor) => [if (anchor != null) anchor.record],
      SceneRecord(:final depictedEvents) =>
        depictedEvents.map((r) => r.record).toList(),
      EventRecord(:final participants) =>
        participants.map((p) => p.record.record).toList(),
      RuleRecord(:final knowledgeBoundary?) => [
        knowledgeBoundary.holder.record,
        knowledgeBoundary.proposition.record,
      ],
      ExceptionRecord(:final rule) => [rule.record],
      AppearanceRecord(target: EntryAppearance(:final entry)) => [entry.record],
      _ => <RecordId>[],
    };
    if (switch (row.payload) {
      BoundaryRecord() ||
      IssueDecisionRecord() ||
      AppearanceRecord(target: UniverseAppearance()) => true,
      _ => false,
    }) {
      pending.add(id);
    }
    final cardinalityTargets = <RecordId>[];
    if (row.payload case RuleRecord(:final relationCardinality?)) {
      for (final candidate in records) {
        if (candidate.payload case PropositionRecord(
          :final predicate,
          :final context,
        )) {
          if (predicate == relationCardinality.relation &&
              context == relationCardinality.scope.context) {
            cardinalityTargets.add(candidate.identity.recordId);
          }
        }
      }
    }
    count += dependencies.length + targets.length + cardinalityTargets.length;
    if (count > 5000000) {
      throw const EvaluationLimitReachedError(
        message: 'research dependency budget exceeded',
      );
    }
    edges.putIfAbsent(id, () => []).addAll([
      ...dependencies,
      ...cardinalityTargets,
    ]);
    for (final target in targets) {
      edges.putIfAbsent(target, () => []).add(id);
    }
  }
  final existing = records.map((row) => row.identity.recordId).toSet();
  final visited = <RecordId>{};
  var closed = true;
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (!existing.contains(id)) {
      closed = false;
    } else if (visited.add(id)) {
      pending.addAll(edges[id] ?? []);
    }
  }
  return (Set.unmodifiable(visited), closed);
}
