import 'package:ub_domain/ub_domain.dart';

import 'request.dart';
import 'workflow.dart';
import 'wire.dart';

// Transport DTOs retain delivery and evidence coverage as independent axes.

enum CapabilityStatus {
  implemented('implemented'),
  partial('partial'),
  descriptiveOnly('descriptive_only'),
  unsupported('unsupported');

  const CapabilityStatus(this.wireName);
  final String wireName;
  static CapabilityStatus fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown CapabilityStatus'),
  );
}

enum ScopeCategory {
  selectedWorld('selected_world'),
  shared('shared'),
  unassigned('unassigned'),
  requiredDependency('required_dependency');

  const ScopeCategory(this.wireName);
  final String wireName;
  static ScopeCategory fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown ScopeCategory'),
  );
}

final class Delivery {
  Delivery({required this.complete, this.cursor});
  final bool complete;
  final String? cursor;
  factory Delivery.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'complete', 'cursor'});
    return Delivery(
      complete: _responseBool(f.require('complete')),
      cursor: f.optional('cursor', (v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('complete', CanonicalBool(complete)),
    MapEntry(
      'cursor',
      cursor == null ? const CanonicalNull() : CanonicalString(cursor!),
    ),
  ]);
}

final class Capability {
  Capability({
    required this.id,
    required this.status,
    required this.limitation,
  });
  final String id;
  final CapabilityStatus status;
  final String limitation;
  factory Capability.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'id', 'status', 'limitation'});
    return Capability(
      id: wireString(f.require('id')),
      status: CapabilityStatus.fromName(wireString(f.require('status'))),
      limitation: wireString(f.require('limitation')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalString(id)),
    MapEntry('status', CanonicalString(status.wireName)),
    MapEntry('limitation', CanonicalString(limitation)),
  ]);
}

final class WorldSummary {
  WorldSummary({required this.id, required this.name});
  final WorldId id;
  final Selector name;
  factory WorldSummary.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'id', 'name'});
    return WorldSummary(
      id: WorldId.parse(wireString(f.require('id'))),
      name: Selector.fromWire(f.require('name')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalString(id.value)),
    MapEntry('name', name.toWire()),
  ]);
}

final class RepresentedContextSummary {
  RepresentedContextSummary({
    required this.id,
    required this.kind,
    required Map<String, String> labels,
  }) : labels = Map.unmodifiable(labels);
  final RecordId id;
  final RepresentedContextKind kind;
  final Map<String, String> labels;
  factory RepresentedContextSummary.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'id', 'kind', 'labels'});
    return RepresentedContextSummary(
      id: RecordId.parse(wireString(f.require('id'))),
      kind: RepresentedContextKind.fromWire(f.require('kind')),
      labels: _responseLabels(f.require('labels')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalString(id.value)),
    MapEntry('kind', kind.toWire()),
    MapEntry(
      'labels',
      CanonicalObject(
        labels.entries.map((e) => MapEntry(e.key, CanonicalString(e.value))),
      ),
    ),
  ]);
}

final class ContinuitySummary {
  ContinuitySummary({
    required this.id,
    required this.revisionId,
    required this.name,
    required Iterable<RepresentedContextSummary> representedContexts,
  }) : representedContexts = List.unmodifiable(representedContexts);
  final ContinuityId id;
  final RevisionId revisionId;
  final String name;
  final List<RepresentedContextSummary> representedContexts;
  factory ContinuitySummary.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'id',
      'revision_id',
      'name',
      'represented_contexts',
    });
    return ContinuitySummary(
      id: ContinuityId.parse(wireString(f.require('id'))),
      revisionId: RevisionId.parse(wireString(f.require('revision_id'))),
      name: wireString(f.require('name')),
      representedContexts: f
          .array('represented_contexts')
          .map((v) => RepresentedContextSummary.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalString(id.value)),
    MapEntry('revision_id', CanonicalString(revisionId.value)),
    MapEntry('name', CanonicalString(name)),
    MapEntry(
      'represented_contexts',
      CanonicalArray(representedContexts.map((v) => v.toWire())),
    ),
  ]);
}

final class Description {
  Description({
    required this.fixture,
    required Iterable<WorldSummary> worlds,
    required Iterable<Capability> capabilities,
    required Iterable<RecordId> definitionIds,
    required Iterable<ContinuitySummary> continuities,
  }) : worlds = List.unmodifiable(worlds),
       capabilities = List.unmodifiable(capabilities),
       definitionIds = List.unmodifiable(definitionIds),
       continuities = List.unmodifiable(continuities);
  final bool fixture;
  final List<WorldSummary> worlds;
  final List<Capability> capabilities;
  final List<RecordId> definitionIds;
  final List<ContinuitySummary> continuities;
  factory Description.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'fixture',
      'worlds',
      'capabilities',
      'definition_ids',
      'continuities',
    });
    return Description(
      fixture: _responseBool(f.require('fixture')),
      worlds: f.array('worlds').map((v) => WorldSummary.fromWire(v)),
      capabilities: f.array('capabilities').map((v) => Capability.fromWire(v)),
      definitionIds: f
          .array('definition_ids')
          .map((v) => RecordId.parse(wireString(v))),
      continuities: f
          .array('continuities')
          .map((v) => ContinuitySummary.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('fixture', CanonicalBool(fixture)),
    MapEntry('worlds', CanonicalArray(worlds.map((v) => v.toWire()))),
    MapEntry(
      'capabilities',
      CanonicalArray(capabilities.map((v) => v.toWire())),
    ),
    MapEntry(
      'definition_ids',
      CanonicalArray(definitionIds.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'continuities',
      CanonicalArray(continuities.map((v) => v.toWire())),
    ),
  ]);
}

final class OpenedContext {
  OpenedContext({required this.contextId, required this.frame});
  final ContextId contextId;
  final Frame frame;
  factory OpenedContext.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'context_id', 'frame'});
    return OpenedContext(
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      frame: Frame.fromWire(f.require('frame')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('frame', frame.toWire()),
  ]);
}

final class SearchHit {
  SearchHit({
    required this.recordId,
    required this.kind,
    required this.label,
    required Iterable<WorldId> worldIds,
    required this.scopeCategory,
  }) : worldIds = List.unmodifiable(worldIds);
  final RecordId recordId;
  final RecordKind kind;
  final String label;
  final List<WorldId> worldIds;
  final ScopeCategory scopeCategory;
  factory SearchHit.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'record_id',
      'kind',
      'label',
      'world_ids',
      'scope_category',
    });
    return SearchHit(
      recordId: RecordId.parse(wireString(f.require('record_id'))),
      kind: RecordKind.parse(wireString(f.require('kind'))),
      label: wireString(f.require('label')),
      worldIds: f.array('world_ids').map((v) => WorldId.parse(wireString(v))),
      scopeCategory: ScopeCategory.fromName(
        wireString(f.require('scope_category')),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_id', CanonicalString(recordId.value)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('label', CanonicalString(label)),
    MapEntry(
      'world_ids',
      CanonicalArray(worldIds.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('scope_category', CanonicalString(scopeCategory.wireName)),
  ]);
}

final class SearchResults {
  SearchResults({required Iterable<SearchHit> hits})
    : hits = List.unmodifiable(hits);
  final List<SearchHit> hits;
  factory SearchResults.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'hits'});
    return SearchResults(
      hits: f.array('hits').map((v) => SearchHit.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('hits', CanonicalArray(hits.map((v) => v.toWire()))),
  ]);
}

final class Records {
  Records({
    required Iterable<RecordVersion> records,
    Iterable<RecordSummary> summaries = const [],
    Iterable<RecordVersion> evidence = const [],
    Iterable<HistoryEntry> history = const [],
    this.historyCoverage,
  }) : records = List.unmodifiable(records),
       summaries = List.unmodifiable(summaries),
       evidence = List.unmodifiable(evidence),
       history = List.unmodifiable(history);
  final List<RecordVersion> records;
  final List<RecordSummary> summaries;
  final List<RecordVersion> evidence;
  final List<HistoryEntry> history;
  final Coverage? historyCoverage;
  factory Records.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'records',
      'summaries',
      'evidence',
      'history',
      'history_coverage',
    });
    return Records(
      records: f.array('records').map((v) => RecordVersion.fromWire(v)),
      summaries: f
          .array('summaries', defaultEmpty: true)
          .map((v) => RecordSummary.fromWire(v)),
      evidence: f
          .array('evidence', defaultEmpty: true)
          .map((v) => RecordVersion.fromWire(v)),
      history: f
          .array('history', defaultEmpty: true)
          .map((v) => HistoryEntry.fromWire(v)),
      historyCoverage: f.optional(
        'history_coverage',
        (v) => Coverage.fromName(wireString(v)),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('records', CanonicalArray(records.map((v) => v.toWire()))),
    if (summaries.isNotEmpty)
      MapEntry('summaries', CanonicalArray(summaries.map((v) => v.toWire()))),
    if (evidence.isNotEmpty)
      MapEntry('evidence', CanonicalArray(evidence.map((v) => v.toWire()))),
    if (history.isNotEmpty)
      MapEntry('history', CanonicalArray(history.map((v) => v.toWire()))),
    if (historyCoverage != null)
      MapEntry('history_coverage', CanonicalString(historyCoverage!.wireName)),
  ]);
}

final class RecordSummary {
  RecordSummary({
    required this.recordId,
    required this.kind,
    required this.label,
  });
  final RecordId recordId;
  final RecordKind kind;
  final String label;
  factory RecordSummary.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record_id', 'kind', 'label'});
    return RecordSummary(
      recordId: RecordId.parse(wireString(f.require('record_id'))),
      kind: RecordKind.parse(wireString(f.require('kind'))),
      label: wireString(f.require('label')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_id', CanonicalString(recordId.value)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('label', CanonicalString(label)),
  ]);
}

final class HistoryEntry {
  HistoryEntry({
    required this.recordId,
    required this.revision,
    required this.continuity,
    required this.principal,
    required this.reason,
    this.record,
  });
  final RecordId recordId;
  final RevisionId revision;
  final ContinuityId continuity;
  final PrincipalId principal;
  final String reason;
  final RecordVersion? record;
  factory HistoryEntry.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'record_id',
      'revision',
      'continuity',
      'principal',
      'reason',
      'record',
    });
    return HistoryEntry(
      recordId: RecordId.parse(wireString(f.require('record_id'))),
      revision: RevisionId.parse(wireString(f.require('revision'))),
      continuity: ContinuityId.parse(wireString(f.require('continuity'))),
      principal: PrincipalId.parse(wireString(f.require('principal'))),
      reason: wireString(f.require('reason')),
      record: f.optional('record', (v) => RecordVersion.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_id', CanonicalString(recordId.value)),
    MapEntry('revision', CanonicalString(revision.value)),
    MapEntry('continuity', CanonicalString(continuity.value)),
    MapEntry('principal', CanonicalString(principal.value)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'record',
      record == null ? const CanonicalNull() : record!.toWire(),
    ),
  ]);
}

final class ContextBrief {
  ContextBrief({
    required Iterable<RecordVersion> records,
    required Iterable<RecordId> requiredDependencies,
    required this.coverage,
  }) : records = List.unmodifiable(records),
       requiredDependencies = List.unmodifiable(requiredDependencies);
  final List<RecordVersion> records;
  final List<RecordId> requiredDependencies;
  final Coverage coverage;
  factory ContextBrief.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'records',
      'required_dependencies',
      'coverage',
    });
    return ContextBrief(
      records: f.array('records').map((v) => RecordVersion.fromWire(v)),
      requiredDependencies: f
          .array('required_dependencies')
          .map((v) => RecordId.parse(wireString(v))),
      coverage: Coverage.fromName(wireString(f.require('coverage'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('records', CanonicalArray(records.map((v) => v.toWire()))),
    MapEntry(
      'required_dependencies',
      CanonicalArray(requiredDependencies.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
  ]);
}

bool _responseBool(CanonicalValue value) => switch (value) {
  CanonicalBool(:final value) => value,
  _ => throw const FormatException('Expected response boolean'),
};
Map<String, String> _responseLabels(CanonicalValue value) {
  if (value is! CanonicalObject) {
    throw const FormatException('Expected response labels');
  }
  return {for (final e in value.fields) e.key: wireString(e.value)};
}
