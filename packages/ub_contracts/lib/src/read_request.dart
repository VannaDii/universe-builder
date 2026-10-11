import 'dart:convert';

import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'protocol_error.dart';

/// Exact administrative selector; validation never chooses a default universe.
final class Selector {
  const Selector(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is Selector && value == other.value;
  @override
  int get hashCode => value.hashCode;
  factory Selector.fromWire(CanonicalValue value) =>
      Selector(wireString(value));
  CanonicalString toWire() => CanonicalString(value);
}

enum FieldGroup {
  summary,
  payload,
  evidence,
  history;

  static FieldGroup fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown field group'),
  );
}

final class Filters {
  Filters({required Iterable<RecordKind> recordKinds})
    : recordKinds = List.unmodifiable(recordKinds);
  final List<RecordKind> recordKinds;
  factory Filters.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record_kinds'});
    return Filters(
      recordKinds: f
          .array('record_kinds')
          .map((v) => RecordKind.parse(wireString(v))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'record_kinds',
      CanonicalArray(recordKinds.map((v) => CanonicalString(v.wireName))),
    ),
  ]);
}

sealed class RevisionSelector {
  const RevisionSelector();
  CanonicalObject toWire();
  static RevisionSelector fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'revision_id'});
    return switch (f.string('kind')) {
      'head' => HeadRevisionSelector.fromWire(value),
      'exact' => ExactRevisionSelector.fromWire(value),
      _ => throw const FormatException('Unknown revision selector'),
    };
  }
}

final class HeadRevisionSelector extends RevisionSelector {
  const HeadRevisionSelector();
  factory HeadRevisionSelector.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'head') {
      throw const FormatException('Wrong revision selector');
    }
    return const HeadRevisionSelector();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('head'))]);
}

final class ExactRevisionSelector extends RevisionSelector {
  const ExactRevisionSelector({required this.revisionId});
  final RevisionId revisionId;
  factory ExactRevisionSelector.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'revision_id'});
    if (f.string('kind') != 'exact') {
      throw const FormatException('Wrong revision selector');
    }
    return ExactRevisionSelector(
      revisionId: RevisionId.parse(f.string('revision_id')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('exact')),
    MapEntry('revision_id', CanonicalString(revisionId.value)),
  ]);
}

sealed class RepresentedContextSelector {
  const RepresentedContextSelector();
  CanonicalValue toWire();
  static RepresentedContextSelector fromWire(CanonicalValue value) {
    if (value is CanonicalString) {
      return ContextIdSelector(RecordId.parse(value.value));
    }
    final f = WireFields(value, {'name'});
    return ContextNameSelector(f.string('name'));
  }
}

final class ContextIdSelector extends RepresentedContextSelector {
  const ContextIdSelector(this.recordId);
  final RecordId recordId;
  @override
  CanonicalString toWire() => CanonicalString(recordId.value);
}

final class ContextNameSelector extends RepresentedContextSelector {
  const ContextNameSelector(this.name);
  final String name;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('name', CanonicalString(name))]);
}

/// Read-only contract subset. No routing, visibility or service execution here.
sealed class ReadRequest {
  const ReadRequest();
  Selector get universe;
  String get toolName;
  CanonicalObject toArgs();
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('tool', CanonicalString(toolName)),
    MapEntry('args', toArgs()),
  ]);
  static ReadRequest fromWire(CanonicalValue value) {
    final f = WireFields(value, {'tool', 'args'});
    return _parse(f.string('tool'), f.require('args'));
  }

  static ReadRequest fromTool(String name, CanonicalValue args) {
    try {
      final request = _parse(name, args);
      request.validate();
      return request;
    } on FormatException catch (e) {
      throw InvalidArgumentError(field: 'arguments', message: e.message);
    }
  }

  static ReadRequest _parse(String name, CanonicalValue args) => switch (name) {
    'universe_open_context' => OpenContextRequest.fromArgs(args),
    'universe_search' => SearchRequest.fromArgs(args),
    'universe_get' => GetRequest.fromArgs(args),
    'universe_get_state' => GetStateRequest.fromArgs(args),
    'universe_get_context' => GetContextRequest.fromArgs(args),
    'universe_describe' => _describe(args),
    _ => throw const FormatException('Unknown read tool'),
  };
  static ReadRequest _describe(CanonicalValue args) {
    if (args is! CanonicalObject) {
      throw const FormatException('Expected describe object');
    }
    final mode = WireFields(args, {
      'mode',
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
    }).string('mode');
    return switch (mode) {
      'summary' => DescribeSummaryRequest.fromArgs(args),
      'capabilities' => DescribeCapabilitiesRequest.fromArgs(args),
      'worlds' => DescribeWorldsRequest.fromArgs(args),
      'definitions' => DescribeDefinitionsRequest.fromArgs(args),
      _ => throw const FormatException('Unknown describe mode'),
    };
  }

  void validate() {
    final args = {for (final e in toArgs().fields) e.key: e.value};
    for (final key in ['universe', 'world']) {
      final value = args[key];
      if (value != null) {
        final text = wireString(value);
        final first = text.runes.firstOrNull;
        if (!hasRustText(text) ||
            utf8.encode(text).length > 256 ||
            (text.contains('*') || text.contains('/') || text.contains('\\')) ||
            text.runes.any((r) => r <= 0x1f || (r >= 0x7f && r <= 0x9f)) ||
            (first != null && !hasRustText(String.fromCharCode(first)))) {
          throw InvalidArgumentError(
            field: key,
            message: 'expected an exact nonblank selector',
          );
        }
      }
    }
    if (args.containsKey('world_id') && !args.containsKey('world')) {
      throw const InvalidArgumentError(
        field: 'world_id',
        message: 'requires world',
      );
    }
    if (args.containsKey('event') != args.containsKey('event_side')) {
      throw const InvalidArgumentError(
        field: 'event',
        message: 'event and event_side must be supplied together',
      );
    }
    final purpose = args['purpose'];
    if (purpose != null) {
      final text = wireString(purpose);
      if (!hasRustText(text) || utf8.encode(text).length > 4096) {
        throw const InvalidArgumentError(
          field: 'purpose',
          message: 'expected 1..4096 bytes',
        );
      }
    }
    for (final key in ['record_ids', 'entity_ids', 'focus_ids']) {
      final list = args[key];
      if (list is CanonicalArray &&
          (list.items.isEmpty || list.items.length > 100)) {
        throw InvalidArgumentError(
          field: key,
          message: 'expected 1..100 items',
        );
      }
    }
    for (final (key, lo, hi) in [
      ('limit', 1, 100),
      ('byte_budget', 256, 65536),
    ]) {
      final value = args[key];
      if (value != null) {
        final number = _requestU32(value);
        if (number < lo || number > hi) {
          throw InvalidArgumentError(
            field: key,
            message: 'outside request limits',
          );
        }
      }
    }
  }
}

T? _requestOptional<T>(
  WireFields fields,
  String key,
  T Function(CanonicalValue) parse,
) => fields.values.containsKey(key) ? parse(fields.require(key)) : null;
int _requestU32(CanonicalValue value) {
  final f = WireFields(CanonicalObject([MapEntry('value', value)]), {'value'});
  final number = f.u64('value');
  if (number > BigInt.from(4294967295)) {
    throw const FormatException('Integer outside u32');
  }
  return number.toInt();
}

int _checkedRequestU32(int value) {
  if (value < 0 || value > 4294967295) {
    throw const FormatException('Integer outside u32');
  }
  return value;
}

final class DescribeSummaryRequest extends ReadRequest {
  DescribeSummaryRequest({required this.universe, this.universeId});
  @override
  final Selector universe;
  final UniverseId? universeId;
  factory DescribeSummaryRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {'universe', 'universe_id', 'mode'});
    if (f.string('mode') != 'summary') {
      throw const FormatException('Wrong describe mode');
    }
    return DescribeSummaryRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
    );
  }
  @override
  String get toolName => 'universe_describe';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('summary')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
  ]);
}

final class DescribeCapabilitiesRequest extends ReadRequest {
  DescribeCapabilitiesRequest({required this.universe, this.universeId});
  @override
  final Selector universe;
  final UniverseId? universeId;
  factory DescribeCapabilitiesRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {'universe', 'universe_id', 'mode'});
    if (f.string('mode') != 'capabilities') {
      throw const FormatException('Wrong describe mode');
    }
    return DescribeCapabilitiesRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
    );
  }
  @override
  String get toolName => 'universe_describe';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('capabilities')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
  ]);
}

final class DescribeWorldsRequest extends ReadRequest {
  DescribeWorldsRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  factory DescribeWorldsRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'mode',
    });
    if (f.string('mode') != 'worlds') {
      throw const FormatException('Wrong describe mode');
    }
    return DescribeWorldsRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
    );
  }
  @override
  String get toolName => 'universe_describe';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('worlds')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
  ]);
}

final class DescribeDefinitionsRequest extends ReadRequest {
  DescribeDefinitionsRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
  });
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  factory DescribeDefinitionsRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'mode',
    });
    if (f.string('mode') != 'definitions') {
      throw const FormatException('Wrong describe mode');
    }
    return DescribeDefinitionsRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
    );
  }
  @override
  String get toolName => 'universe_describe';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('mode', CanonicalString('definitions')),
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
  ]);
}

final class OpenContextRequest extends ReadRequest {
  OpenContextRequest({
    required this.universe,
    this.universeId,
    required this.continuityId,
    required this.revision,
    required this.representedContext,
    required this.temporalQuery,
    required Iterable<CalendarId> temporalSystems,
    required this.perspective,
    this.readerScene,
  }) : temporalSystems = List.unmodifiable(temporalSystems);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContinuityId continuityId;
  final RevisionSelector revision;
  final RepresentedContextSelector representedContext;
  final FrameTime temporalQuery;
  final List<CalendarId> temporalSystems;
  final Perspective perspective;
  final RepresentedContextSelector? readerScene;
  factory OpenContextRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'continuity_id',
      'revision',
      'represented_context',
      'temporal_query',
      'temporal_systems',
      'perspective',
      'reader_scene',
    });
    return OpenContextRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      continuityId: ContinuityId.parse(wireString(f.require('continuity_id'))),
      revision: RevisionSelector.fromWire(f.require('revision')),
      representedContext: RepresentedContextSelector.fromWire(
        f.require('represented_context'),
      ),
      temporalQuery: FrameTime.fromWire(f.require('temporal_query')),
      temporalSystems: f
          .array('temporal_systems')
          .map((v) => CalendarId.parse(wireString(v))),
      perspective: Perspective.fromWire(f.require('perspective')),
      readerScene: _requestOptional(
        f,
        'reader_scene',
        (v) => RepresentedContextSelector.fromWire(v),
      ),
    );
  }
  @override
  String get toolName => 'universe_open_context';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('continuity_id', CanonicalString(continuityId.value)),
    MapEntry('revision', revision.toWire()),
    MapEntry('represented_context', representedContext.toWire()),
    MapEntry('temporal_query', temporalQuery.toWire()),
    MapEntry(
      'temporal_systems',
      CanonicalArray(temporalSystems.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('perspective', perspective.toWire()),
    if (readerScene != null) MapEntry('reader_scene', readerScene!.toWire()),
  ]);
}

final class SearchRequest extends ReadRequest {
  SearchRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required this.query,
    required this.typedFilters,
    required int limit,
    this.cursor,
  }) : limit = _checkedRequestU32(limit);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final String query;
  final Filters typedFilters;
  final int limit;
  final String? cursor;
  factory SearchRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'query',
      'typed_filters',
      'limit',
      'cursor',
    });
    return SearchRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      query: wireString(f.require('query')),
      typedFilters: Filters.fromWire(f.require('typed_filters')),
      limit: _requestU32(f.require('limit')),
      cursor: _requestOptional(f, 'cursor', (v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_search';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry('query', CanonicalString(query)),
    MapEntry('typed_filters', typedFilters.toWire()),
    MapEntry('limit', CanonicalNumber(limit.toString())),
    if (cursor != null) MapEntry('cursor', CanonicalString(cursor!)),
  ]);
}

final class GetRequest extends ReadRequest {
  GetRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required Iterable<RecordId> recordIds,
    required Iterable<FieldGroup> fieldGroups,
  }) : recordIds = List.unmodifiable(recordIds),
       fieldGroups = List.unmodifiable(fieldGroups);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final List<RecordId> recordIds;
  final List<FieldGroup> fieldGroups;
  factory GetRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'record_ids',
      'field_groups',
    });
    return GetRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      recordIds: f
          .array('record_ids')
          .map((v) => RecordId.parse(wireString(v))),
      fieldGroups: f
          .array('field_groups')
          .map((v) => FieldGroup.fromName(wireString(v))),
    );
  }
  @override
  String get toolName => 'universe_get';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry(
      'record_ids',
      CanonicalArray(recordIds.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'field_groups',
      CanonicalArray(fieldGroups.map((v) => CanonicalString(v.name))),
    ),
  ]);
}

final class GetStateRequest extends ReadRequest {
  GetStateRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required Iterable<RecordId> entityIds,
    required Iterable<RecordId> predicateFilters,
    this.event,
    this.eventSide,
  }) : entityIds = List.unmodifiable(entityIds),
       predicateFilters = List.unmodifiable(predicateFilters);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final List<RecordId> entityIds;
  final List<RecordId> predicateFilters;
  final RecordId? event;
  final EventTimeSide? eventSide;
  factory GetStateRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'entity_ids',
      'predicate_filters',
      'event',
      'event_side',
    });
    return GetStateRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      entityIds: f
          .array('entity_ids')
          .map((v) => RecordId.parse(wireString(v))),
      predicateFilters: f
          .array('predicate_filters')
          .map((v) => RecordId.parse(wireString(v))),
      event: _requestOptional(f, 'event', (v) => RecordId.parse(wireString(v))),
      eventSide: _requestOptional(
        f,
        'event_side',
        (v) => EventTimeSide.fromName(wireString(v)),
      ),
    );
  }
  @override
  String get toolName => 'universe_get_state';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry(
      'entity_ids',
      CanonicalArray(entityIds.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'predicate_filters',
      CanonicalArray(predicateFilters.map((v) => CanonicalString(v.value))),
    ),
    if (event != null) MapEntry('event', CanonicalString(event!.value)),
    if (eventSide != null)
      MapEntry('event_side', CanonicalString(eventSide!.name)),
  ]);
}

final class GetContextRequest extends ReadRequest {
  GetContextRequest({
    required this.universe,
    this.universeId,
    required this.contextId,
    this.world,
    this.worldId,
    required Iterable<RecordId> focusIds,
    required this.purpose,
    required int byteBudget,
    this.cursor,
  }) : focusIds = List.unmodifiable(focusIds),
       byteBudget = _checkedRequestU32(byteBudget);
  @override
  final Selector universe;
  final UniverseId? universeId;
  final ContextId contextId;
  final Selector? world;
  final WorldId? worldId;
  final List<RecordId> focusIds;
  final String purpose;
  final int byteBudget;
  final String? cursor;
  factory GetContextRequest.fromArgs(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'universe_id',
      'context_id',
      'world',
      'world_id',
      'focus_ids',
      'purpose',
      'byte_budget',
      'cursor',
    });
    return GetContextRequest(
      universe: Selector.fromWire(f.require('universe')),
      universeId: _requestOptional(
        f,
        'universe_id',
        (v) => UniverseId.parse(wireString(v)),
      ),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => Selector.fromWire(v)),
      worldId: _requestOptional(
        f,
        'world_id',
        (v) => WorldId.parse(wireString(v)),
      ),
      focusIds: f.array('focus_ids').map((v) => RecordId.parse(wireString(v))),
      purpose: wireString(f.require('purpose')),
      byteBudget: _requestU32(f.require('byte_budget')),
      cursor: _requestOptional(f, 'cursor', (v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_get_context';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    if (universeId != null)
      MapEntry('universe_id', CanonicalString(universeId!.value)),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', world!.toWire()),
    if (worldId != null) MapEntry('world_id', CanonicalString(worldId!.value)),
    MapEntry(
      'focus_ids',
      CanonicalArray(focusIds.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('purpose', CanonicalString(purpose)),
    MapEntry('byte_budget', CanonicalNumber(byteBudget.toString())),
    if (cursor != null) MapEntry('cursor', CanonicalString(cursor!)),
  ]);
}
