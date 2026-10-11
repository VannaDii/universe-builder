import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';

final class RecordDependency {
  const RecordDependency(this.record, this.version, this.path);
  final RecordId record;
  final RecordVersionId? version;
  final String path;
}

final class TypedDependency {
  const TypedDependency(this.record, this.kind);
  final RecordId record;
  final RecordKind kind;
}

/// The existing closed DTO traversal. Prose that looks like an ID remains
/// prose; names in declared value maps do not become DTO field names.
final class ReferenceScan {
  final records = <RecordDependency>[];
  final worlds = <WorldId>[];
  final typed = <TypedDependency>[];
  final scalars = <(String, String)>[];

  static const _prose = {
    'labels',
    'text',
    'title',
    'selector',
    'aliases',
    'rationale',
    'excerpt',
    'description',
    'note',
    'symbol',
    'client_ref',
    'originNote',
    'externallyAssertedAuthor',
    'unitStructure',
    'unit_structure',
    'dependencies',
  };
  static const _recordFields = {
    'parent',
    'classification',
    'subjectTypes',
    'subject_types',
    'participantTypes',
    'participant_types',
    'records',
    'types',
    'versions',
    'entityType',
    'entity_type',
    'referenced_records',
    'referencedRecords',
    'observer',
  };
  static const _worldFields = {'world', 'world_ids', 'worldIds'};
  static const _aliasFields = {
    'unit',
    'base',
    'calendar',
    'target',
    'definition',
  };

  static ReferenceScan collect(CanonicalValue value, UniverseId universe) {
    final result = ReferenceScan();
    result._walk(value, universe, '', '');
    return result;
  }

  void _walk(
    CanonicalValue value,
    UniverseId universe,
    String path,
    String key,
  ) {
    if (_prose.contains(key)) return;
    switch (value) {
      case CanonicalObject():
        final fields = objectFields(value);
        final owner = fields['universe'];
        if (owner is CanonicalString && owner.value != universe.value) {
          throw const FormatException('Cross-universe reference');
        }
        final record = fields['record'];
        if (record is CanonicalString && record.value.startsWith('rec_')) {
          if (owner is! CanonicalString || owner.value != universe.value) {
            throw const FormatException(
              'Canonical reference requires explicit universe',
            );
          }
          final version = fields['version'];
          records.add(
            RecordDependency(
              RecordId.parse(record.value),
              version is CanonicalString
                  ? RecordVersionId.parse(version.value)
                  : null,
              path,
            ),
          );
          // An exact version pin must not turn into a current-state dependency.
          for (final entry in fields.entries) {
            if (!{'record', 'universe', 'version'}.contains(entry.key)) {
              _walk(entry.value, universe, '$path/${entry.key}', entry.key);
            }
          }
          return;
        }
        for (final entry in fields.entries) {
          _walk(
            entry.value,
            universe,
            '$path/${entry.key}',
            {'metadata', 'qualifiers', 'fields'}.contains(key) ? '' : entry.key,
          );
        }
      case CanonicalArray():
        for (var i = 0; i < value.items.length; i++) {
          final item = value.items[i];
          _walk(item, universe, '$path/$i', item is CanonicalString ? key : '');
        }
      case CanonicalString():
        if (_recordFields.contains(key)) {
          final id = _try(RecordId.parse, value.value);
          if (id != null) records.add(RecordDependency(id, null, path));
        }
        final world = _try(WorldId.parse, value.value);
        if (world != null && _worldFields.contains(key)) {
          worlds.add(world);
          records.add(RecordDependency(worldRecord(world), null, path));
        }
        if (_aliasFields.contains(key)) {
          final alias = _alias(value.value);
          if (alias != null) {
            typed.add(alias);
            records.add(RecordDependency(alias.record, null, path));
          }
        }
        scalars.add((path, value.value));
      case CanonicalBool():
        scalars.add((path, value.toText()));
      case CanonicalNumber():
        scalars.add((path, value.toText()));
      case CanonicalNull():
        break;
    }
  }

  TypedDependency? _alias(String value) {
    final unit = _try(UnitId.parse, value);
    if (unit != null) {
      return TypedDependency(unit.toRecordId(), RecordKind.unit);
    }
    final calendar = _try(CalendarId.parse, value);
    if (calendar != null) {
      return TypedDependency(calendar.toRecordId(), RecordKind.calendar);
    }
    final definition = _try(ValueDefinitionId.parse, value);
    if (definition != null) {
      return TypedDependency(
        definition.toRecordId(),
        RecordKind.valueDefinition,
      );
    }
    final proposition = _try(PropositionId.parse, value);
    if (proposition != null) {
      return TypedDependency(proposition.toRecordId(), RecordKind.proposition);
    }
    final rule = _try(RuleId.parse, value);
    if (rule != null) {
      return TypedDependency(rule.toRecordId(), RecordKind.rule);
    }
    return null;
  }

  static T? _try<T>(T Function(String) parse, String value) {
    try {
      return parse(value);
    } on FormatException {
      return null;
    }
  }
}

RecordId worldRecord(WorldId world) =>
    RecordId.parse('rec_${world.value.substring(WorldId.prefix.length)}');
