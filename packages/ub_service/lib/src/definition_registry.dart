import 'dart:collection';

import 'package:ub_domain/ub_domain.dart';

const knownDefinitionCapabilities = [
  'assertion.qualified.v1',
  'time.exact_interval.v1',
  'time.relative_order.v1',
  'state.declared_persistence.v1',
  'rule.finite_constraints.v1',
  'knowledge.explicit_attitudes.v1',
  'continuity.pinned_inheritance.v1',
];
const maxValueDefinitionDepth = 32;

final class DefinitionAdmissionError implements Exception {
  const DefinitionAdmissionError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

Never _fail(String code, String message) =>
    throw DefinitionAdmissionError(code, message);
RecordId _alias(TypedId id) =>
    RecordId.parse('rec_${id.value.substring(id.value.indexOf('_') + 1)}');
bool _blank(String s) => !RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
).hasMatch(s);

/// Definitions from one candidate snapshot. Superseded bytes belong in history.
final class DefinitionRegistry {
  UniverseId? _universe;
  UniverseId? get universe => _universe;
  final _families = <RecordKind, SplayTreeMap<String, RecordPayload>>{};
  final _names = <(RecordKind, String, String), String>{};
  Iterable<MapEntry<String, RecordPayload>> _entries(RecordKind kind) =>
      _families[kind]?.entries ?? <MapEntry<String, RecordPayload>>[];
  RecordPayload? get(TypedId id, RecordKind kind) =>
      _families[kind]?[_alias(id).value];

  void add(RecordVersion version) {
    final id = version.identity.recordId.value;
    if (!version.verifiesDigest) {
      _fail('DIGEST_MISMATCH', 'digest mismatch for record $id');
    }
    final p = version.payload;
    final (String, String)? name = switch (p) {
      EntityTypeRecord(:final namespace, :final key) ||
      PropertyRecord(:final namespace, :final key) ||
      RelationRecord(:final namespace, :final key) ||
      UnitRecord(:final namespace, :final key) ||
      CalendarRecord(:final namespace, :final key) ||
      ValueDefinitionRecord(:final namespace, :final key) => (namespace, key),
      DomainPackRecord(:final key) => ('', key),
      _ => null,
    };
    if (name == null) return;
    if (_universe != null && _universe != version.identity.universeId) {
      _fail(
        'CROSS_UNIVERSE_REFERENCE',
        'record $id belongs to universe ${version.identity.universeId.value}; registry is ${_universe!.value}',
      );
    }
    _universe ??= version.identity.universeId;
    final nameKey = (p.recordKind, name.$1, name.$2);
    final old = _names[nameKey];
    if (old != null && old != id) {
      _fail(
        'DUPLICATE_DEFINITION',
        'duplicate definition key ${name.$1}:${name.$2} in ${p.recordKind.wireName} ($id)',
      );
    }
    _names[nameKey] = id;
    (_families[p.recordKind] ??= SplayTreeMap())[id] = p;
  }

  void validate() {
    void invalid(RecordKind kind, String id, String reason) =>
        _fail('INVALID_DEFINITION', 'invalid ${kind.wireName} $id: $reason');
    void require(TypedId target, RecordKind kind, String from) {
      if (get(target, kind) == null) {
        _fail(
          'MISSING_REFERENCE',
          '$from references ${target.value}, which is not in the registry (${kind.wireName})',
        );
      }
    }

    for (final entry in _entries(RecordKind.entityType)) {
      final t = entry.value as EntityTypeRecord, id = entry.key;
      if (t.namespace.isEmpty || t.key.isEmpty) {
        invalid(t.recordKind, id, 'namespace and key must be non-empty');
      }
      if ((t.parentResolution == ParentResolution.resolved) !=
          (t.parent != null)) {
        invalid(
          t.recordKind,
          id,
          'parent resolution disagrees with parent identity',
        );
      }
      if (t.parent case final parent?) {
        require(parent, RecordKind.entityType, 'entity type $id');
      }
      for (final start in _entries(RecordKind.entityType)) {
        final path = <String>[], seen = <String, int>{};
        String? next = start.key;
        while (next != null) {
          if (seen[next] case final at?) {
            _fail(
              'INHERITANCE_CYCLE',
              'entity type inheritance cycle: ${[...path.skip(at), next].join(' -> ')}',
            );
          }
          seen[next] = path.length;
          path.add(next);
          final current =
              _families[RecordKind.entityType]?[next] as EntityTypeRecord?;
          next = current?.parent?.value;
        }
      }
    }
    for (final entry in _entries(RecordKind.property)) {
      final p = entry.value as PropertyRecord, id = entry.key;
      if (p.namespace.isEmpty || p.key.isEmpty) {
        invalid(p.recordKind, id, 'namespace and key must be non-empty');
      }
      for (final target in p.subjectTypes) {
        require(target, RecordKind.entityType, 'property $id');
      }
      final unit = switch (p.value) {
        QuantityShape(:final unit) => unit,
        RangeShape(:final unit) => unit,
        _ => null,
      };
      if (unit != null) {
        require(unit, RecordKind.unit, 'property $id');
        final d = get(unit, RecordKind.unit) as UnitRecord;
        if (p.unitDimension != null && p.unitDimension != d.dimension) {
          invalid(
            p.recordKind,
            id,
            'declares dimension ${p.unitDimension} but unit ${unit.value} is dimension ${d.dimension}',
          );
        }
      }
      switch (p.value) {
        case EnumShape(:final definition) || StructuredShape(:final definition):
          require(definition, RecordKind.valueDefinition, 'property $id');
        default:
          break;
      }
      if (p.inverse case final inverse?) {
        if (!_entries(RecordKind.property).any((e) {
          final d = e.value as PropertyRecord;
          return d.namespace == p.namespace && d.key == inverse;
        })) {
          _fail(
            'MISSING_REFERENCE',
            'property $id references $inverse, which is not in the registry (property)',
          );
        }
      }
    }
    for (final entry in _entries(RecordKind.relation)) {
      final r = entry.value as RelationRecord;
      if (r.roles.isEmpty) {
        invalid(
          r.recordKind,
          entry.key,
          'a relation declares at least one role',
        );
      }
      final names = <String>{};
      for (final role in r.roles) {
        if (role.name.isEmpty || !names.add(role.name)) {
          invalid(
            r.recordKind,
            entry.key,
            'role name `${role.name}` is empty or duplicated',
          );
        }
        for (final target in role.participantTypes) {
          require(target, RecordKind.entityType, 'relation ${entry.key}');
        }
      }
    }
    bool positive(String s) {
      if (s.startsWith('-')) return false;
      final rest = (s.startsWith('+') ? s.substring(1) : s)
          .replaceAll('.', '')
          .replaceFirst(RegExp(r'^0+'), '');
      return rest.isNotEmpty;
    }

    for (final entry in _entries(RecordKind.unit)) {
      final u = entry.value as UnitRecord;
      if (u.dimension.isEmpty) {
        invalid(u.recordKind, entry.key, 'a unit must declare a dimension');
      }
      if (u.scaleToBase case final scale?) {
        final valid = switch (scale) {
          IntegerValue(:final digits) ||
          DecimalValue(:final digits) => positive(digits),
          RationalValue(:final numerator, :final denominator) =>
            positive(numerator) && positive(denominator),
          _ => false,
        };
        if (!valid) {
          invalid(
            u.recordKind,
            entry.key,
            'scale_to_base must be a strictly positive exact number',
          );
        }
      }
      if (u.base case final base?) {
        if (_alias(base).value == entry.key) {
          invalid(u.recordKind, entry.key, 'a unit cannot be its own base');
        }
        require(base, RecordKind.unit, 'unit ${entry.key}');
        final d = get(base, RecordKind.unit) as UnitRecord;
        if (d.dimension != u.dimension) {
          invalid(
            u.recordKind,
            entry.key,
            'base unit ${base.value} has dimension ${d.dimension} but this unit has ${u.dimension}',
          );
        }
      }
    }
    for (final entry in _entries(RecordKind.calendar)) {
      for (final conv in (entry.value as CalendarRecord).conversions) {
        require(conv.target, RecordKind.calendar, 'calendar ${entry.key}');
      }
    }
    void visitValue(String id, List<String> trail, int depth) {
      if (depth > maxValueDefinitionDepth) {
        _fail(
          'SCHEMA_RECURSION',
          'recursive value definition: ${trail.join(' -> ')}',
        );
      }
      final d =
          _families[RecordKind.valueDefinition]?[id] as ValueDefinitionRecord?;
      if (d == null) return;
      trail.add(id);
      for (final field in d.fields) {
        if (field.shape case StructuredShape(:final definition)) {
          final target = _alias(definition).value;
          if (target == id) {
            _fail(
              'SCHEMA_RECURSION',
              'recursive value definition: ${[...trail, id].join(' -> ')}',
            );
          }
          visitValue(target, trail, depth + 1);
        }
      }
      trail.removeLast();
    }

    for (final entry in _entries(RecordKind.valueDefinition)) {
      final names = <String>{};
      for (final field in (entry.value as ValueDefinitionRecord).fields) {
        if (field.name.isEmpty || !names.add(field.name)) {
          invalid(
            RecordKind.valueDefinition,
            entry.key,
            'field `${field.name}` is empty or duplicated',
          );
        }
      }
      visitValue(entry.key, [], 0);
    }
    final packs = _entries(RecordKind.domainPack)
        .map((e) => (e.key, e.value as DomainPackRecord))
        .toList();
    for (final (id, pack) in packs) {
      void bad(String reason) => invalid(RecordKind.domainPack, id, reason);
      if (_blank(pack.key) || _blank(pack.version)) {
        bad('pack key and exact version are required');
      }
      if (packs.where((p) => p.$2.key == pack.key).length != 1) {
        bad('pack keys must be unique');
      }
      void visit(DomainPackRecord p, List<String> path, Set<String> visited) {
        if (visited.contains(p.key)) return;
        if (path.length > 32) bad('pack dependency depth exceeds 32');
        final dependencies = p.dependencies.keys.toList()..sort();
        for (final name in dependencies) {
          if (path.contains(name)) bad('pack dependency cycle');
          final matches = packs.where(
            (d) => d.$2.key == name && d.$2.version == p.dependencies[name],
          );
          if (matches.isEmpty) {
            bad('missing dependency or exact version mismatch');
          }
          final d = matches.first.$2;
          path.add(d.key);
          visit(d, path, visited);
          path.removeLast();
        }
        visited.add(p.key);
      }

      visit(pack, [pack.key], {});
      for (final cap in pack.capabilities) {
        if (!knownDefinitionCapabilities.contains(cap)) {
          _fail(
            'UNKNOWN_CAPABILITY',
            'pack declares unknown capability `$cap`',
          );
        }
      }
    }
  }
}
