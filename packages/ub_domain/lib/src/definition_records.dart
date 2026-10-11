part of 'records.dart';

enum ParentResolution {
  root,
  resolved,
  ambiguous;

  static ParentResolution fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown parent resolution'),
  );
}

enum ClassificationResolution {
  unclassified,
  resolved,
  ambiguous;

  static ClassificationResolution fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () =>
        throw const FormatException('Unknown classification resolution'),
  );
}

enum Multiplicity {
  single,
  multiple;

  static Multiplicity fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown multiplicity'),
  );
}

/// Parent knowledge is independent of the definition's stable identity.
final class EntityTypeRecord extends RecordPayload {
  EntityTypeRecord({
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    required this.name,
    this.parent,
    required this.parentResolution,
    required this.applicability,
    required this.classificationExecutable,
  }) : labels = Map.unmodifiable(labels);
  final String namespace, key, name;
  final Map<String, String> labels;
  final RecordId? parent;
  final ParentResolution parentResolution;
  final Applicability applicability;
  final bool classificationExecutable;
  factory EntityTypeRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.entityType, {
      'namespace',
      'key',
      'labels',
      'name',
      'parent',
      'parentResolution',
      'applicability',
      'classificationExecutable',
    });
    final parent = f.optionalString('parent');
    return EntityTypeRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      name: f.string('name'),
      parent: parent == null ? null : RecordId.parse(parent),
      parentResolution: ParentResolution.fromName(f.string('parentResolution')),
      applicability: Applicability.fromWire(f.require('applicability')),
      classificationExecutable: f.boolean('classificationExecutable'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.entityType;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('parent', _nullableId(parent)),
    MapEntry('parentResolution', CanonicalString(parentResolution.name)),
    MapEntry('applicability', applicability.toWire()),
    MapEntry(
      'classificationExecutable',
      CanonicalBool(classificationExecutable),
    ),
  ]);
}

/// Executable behavior is opt-in and is never inferred from display labels.
final class PropertyRecord extends RecordPayload {
  PropertyRecord({
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    Iterable<RecordId> subjectTypes = const [],
    required this.value,
    required this.multiplicity,
    this.unitDimension,
    required this.persistence,
    required this.exclusive,
    this.inverse,
    required this.symmetric,
    required this.transitive,
  }) : labels = Map.unmodifiable(labels),
       subjectTypes = List.unmodifiable(subjectTypes);
  final String namespace, key;
  final Map<String, String> labels;
  final List<RecordId> subjectTypes;
  final ValueShape value;
  final Multiplicity multiplicity;
  final String? unitDimension, inverse;
  final PersistenceSemantics persistence;
  final bool exclusive, symmetric, transitive;
  factory PropertyRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.property, {
      'namespace',
      'key',
      'labels',
      'subjectTypes',
      'value',
      'multiplicity',
      'unitDimension',
      'persistence',
      'exclusive',
      'inverse',
      'symmetric',
      'transitive',
    });
    return PropertyRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      subjectTypes: _ids(_array(f, 'subjectTypes')),
      value: ValueShape.fromWire(f.require('value')),
      multiplicity: Multiplicity.fromName(f.string('multiplicity')),
      unitDimension: f.optionalString('unitDimension'),
      persistence: PersistenceSemantics.fromWire(f.require('persistence')),
      exclusive: f.boolean('exclusive'),
      inverse: f.optionalString('inverse'),
      symmetric: f.boolean('symmetric'),
      transitive: f.boolean('transitive'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.property;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('subjectTypes', _idArray(subjectTypes)),
    MapEntry('value', value.toWire()),
    MapEntry('multiplicity', CanonicalString(multiplicity.name)),
    MapEntry('unitDimension', _nullableString(unitDimension)),
    MapEntry('persistence', persistence.toWire()),
    MapEntry('exclusive', CanonicalBool(exclusive)),
    MapEntry('inverse', _nullableString(inverse)),
    MapEntry('symmetric', CanonicalBool(symmetric)),
    MapEntry('transitive', CanonicalBool(transitive)),
  ]);
}

final class RoleDefinition {
  RoleDefinition({
    required this.name,
    Iterable<RecordId> participantTypes = const [],
    required this.multiplicity,
    required this.ordered,
  }) : participantTypes = List.unmodifiable(participantTypes);
  final String name;
  final List<RecordId> participantTypes;
  final Multiplicity multiplicity;
  final bool ordered;
  factory RoleDefinition.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'name', 'participantTypes', 'multiplicity', 'ordered'});
    return RoleDefinition(
      name: f.string('name'),
      participantTypes: _ids(_array(f, 'participantTypes')),
      multiplicity: Multiplicity.fromName(f.string('multiplicity')),
      ordered: f.boolean('ordered'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('participantTypes', _idArray(participantTypes)),
    MapEntry('multiplicity', CanonicalString(multiplicity.name)),
    MapEntry('ordered', CanonicalBool(ordered)),
  ]);
}

final class RelationRecord extends RecordPayload {
  RelationRecord({
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    required Iterable<RoleDefinition> roles,
  }) : labels = Map.unmodifiable(labels),
       roles = List.unmodifiable(roles);
  final String namespace, key;
  final Map<String, String> labels;
  final List<RoleDefinition> roles;
  factory RelationRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.relation, {
      'namespace',
      'key',
      'labels',
      'roles',
    });
    return RelationRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      roles: f.array('roles').map(RoleDefinition.fromWire),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.relation;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('roles', CanonicalArray(roles.map((r) => r.toWire()))),
  ]);
}

/// Unknown conversions remain unresolved; a label does not establish a rate.
final class UnitRecord extends RecordPayload {
  UnitRecord({
    required this.namespace,
    required this.key,
    required this.dimension,
    required this.symbol,
    required Map<String, String> labels,
    this.scaleToBase,
    this.base,
    required this.validity,
  }) : labels = Map.unmodifiable(labels);
  final String namespace, key, dimension, symbol;
  final Map<String, String> labels;
  final DomainValue? scaleToBase;
  final UnitId? base;
  final Validity validity;
  factory UnitRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.unit, {
      'namespace',
      'key',
      'dimension',
      'symbol',
      'labels',
      'scaleToBase',
      'base',
      'validity',
    });
    final base = f.optionalString('base');
    final scale = f.values['scaleToBase'];
    return UnitRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      dimension: f.string('dimension'),
      symbol: f.string('symbol'),
      labels: _strings(f, 'labels'),
      base: base == null ? null : UnitId.parse(base),
      scaleToBase: scale == null || scale is CanonicalNull
          ? null
          : DomainValue.fromWire(scale),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.unit;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('dimension', CanonicalString(dimension)),
    MapEntry('symbol', CanonicalString(symbol)),
    MapEntry('labels', _stringMap(labels)),
    if (scaleToBase != null) MapEntry('scaleToBase', scaleToBase!.toWire()),
    MapEntry('base', _nullableId(base)),
    MapEntry('validity', validity.toWire()),
  ]);
}

final class CalendarConversion {
  const CalendarConversion({
    required this.target,
    this.expression,
    required this.valid,
  });
  final CalendarId target;
  final String? expression;
  final bool valid;
  factory CalendarConversion.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'target', 'expression', 'valid'});
    return CalendarConversion(
      target: CalendarId.parse(f.string('target')),
      expression: f.optionalString('expression'),
      valid: f.boolean('valid'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('target', CanonicalString(target.value)),
    MapEntry('expression', _nullableString(expression)),
    MapEntry('valid', CanonicalBool(valid)),
  ]);
}

/// Empty authored conversion data does not confer arithmetic capability.
final class CalendarRecord extends RecordPayload {
  CalendarRecord({
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    this.epoch,
    required Map<String, String> unitStructure,
    Iterable<CalendarConversion> conversions = const [],
  }) : labels = Map.unmodifiable(labels),
       unitStructure = Map.unmodifiable(unitStructure),
       conversions = List.unmodifiable(conversions);
  final String namespace, key;
  final Map<String, String> labels, unitStructure;
  final String? epoch;
  final List<CalendarConversion> conversions;
  factory CalendarRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.calendar, {
      'namespace',
      'key',
      'labels',
      'epoch',
      'unitStructure',
      'conversions',
    });
    return CalendarRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      epoch: f.optionalString('epoch'),
      unitStructure: _strings(f, 'unitStructure'),
      conversions: _array(f, 'conversions').map(CalendarConversion.fromWire),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.calendar;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    if (epoch != null) MapEntry('epoch', CanonicalString(epoch!)),
    MapEntry('unitStructure', _stringMap(unitStructure)),
    if (conversions.isNotEmpty)
      MapEntry(
        'conversions',
        CanonicalArray(conversions.map((c) => c.toWire())),
      ),
  ]);
}

final class ValueDefinitionField {
  const ValueDefinitionField({
    required this.name,
    required this.shape,
    required this.required,
    required this.allowsUnknown,
  });
  final String name;
  final ValueShape shape;
  final bool required, allowsUnknown;
  factory ValueDefinitionField.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'name', 'shape', 'required', 'allowsUnknown'});
    return ValueDefinitionField(
      name: f.string('name'),
      shape: ValueShape.fromWire(f.require('shape')),
      required: f.boolean('required'),
      allowsUnknown: f.boolean('allowsUnknown'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('shape', shape.toWire()),
    MapEntry('required', CanonicalBool(required)),
    MapEntry('allowsUnknown', CanonicalBool(allowsUnknown)),
  ]);
}

final class ValueDefinitionRecord extends RecordPayload {
  ValueDefinitionRecord({
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    required Iterable<ValueDefinitionField> fields,
  }) : labels = Map.unmodifiable(labels),
       fields = List.unmodifiable(fields);
  final String namespace, key;
  final Map<String, String> labels;
  final List<ValueDefinitionField> fields;
  factory ValueDefinitionRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.valueDefinition, {
      'namespace',
      'key',
      'labels',
      'fields',
    });
    return ValueDefinitionRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      fields: f.array('fields').map(ValueDefinitionField.fromWire),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.valueDefinition;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('fields', CanonicalArray(fields.map((f) => f.toWire()))),
  ]);
}

/// A pack declares data and capability requirements; it cannot add executable code.
final class DomainPackRecord extends RecordPayload {
  DomainPackRecord({
    required this.key,
    required this.version,
    required Map<String, String> dependencies,
    required Iterable<String> capabilities,
    required Iterable<RecordId> records,
  }) : dependencies = Map.unmodifiable(dependencies),
       capabilities = List.unmodifiable(capabilities),
       records = List.unmodifiable(records);
  final String key, version;
  final Map<String, String> dependencies;
  final List<String> capabilities;
  final List<RecordId> records;
  factory DomainPackRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.domainPack, {
      'key',
      'version',
      'dependencies',
      'capabilities',
      'records',
    });
    return DomainPackRecord(
      key: f.string('key'),
      version: f.string('version'),
      dependencies: _strings(f, 'dependencies'),
      capabilities: f.array('capabilities').map(_string),
      records: _ids(f.array('records')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.domainPack;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('key', CanonicalString(key)),
    MapEntry('version', CanonicalString(version)),
    MapEntry('dependencies', _stringMap(dependencies)),
    MapEntry(
      'capabilities',
      CanonicalArray(capabilities.map(CanonicalString.new)),
    ),
    MapEntry('records', _idArray(records)),
  ]);
}
