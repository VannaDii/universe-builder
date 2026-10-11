part of 'records.dart';

/// Administrative names preserve their display spelling, separately from keys.
final class WorldRecord extends RecordPayload {
  WorldRecord({
    required this.selector,
    Iterable<String> aliases = const [],
    this.settingType,
    Map<String, String> labels = const {},
    Map<String, DomainValue> metadata = const {},
  }) : aliases = List.unmodifiable(aliases),
       labels = Map.unmodifiable(labels),
       metadata = Map.unmodifiable(metadata);
  final String selector;
  final List<String> aliases;
  final String? settingType;
  final Map<String, String> labels;
  final Map<String, DomainValue> metadata;
  factory WorldRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.world, {
      'selector',
      'aliases',
      'settingType',
      'labels',
      'metadata',
    });
    return WorldRecord(
      selector: f.string('selector'),
      aliases: _array(f, 'aliases').map(_string),
      settingType: f.optionalString('settingType'),
      labels: _strings(f, 'labels', defaultEmpty: true),
      metadata: _values(f, 'metadata', defaultEmpty: true),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.world;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('selector', CanonicalString(selector)),
    if (aliases.isNotEmpty)
      MapEntry('aliases', CanonicalArray(aliases.map(CanonicalString.new))),
    if (settingType != null)
      MapEntry('settingType', CanonicalString(settingType!)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('metadata', _valueMap(metadata)),
  ]);
}

final class RealmRecord extends RecordPayload {
  RealmRecord({
    required Map<String, String> labels,
    required Map<String, DomainValue> metadata,
  }) : labels = Map.unmodifiable(labels),
       metadata = Map.unmodifiable(metadata);
  final Map<String, String> labels;
  final Map<String, DomainValue> metadata;
  factory RealmRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.realm, {'labels', 'metadata'});
    return RealmRecord(
      labels: _strings(f, 'labels'),
      metadata: _values(f, 'metadata'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.realm;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('labels', _stringMap(labels)),
    MapEntry('metadata', _valueMap(metadata)),
  ]);
}

/// A contextual name does not change or duplicate the person's stable identity.
final class ContextualName {
  const ContextualName({
    required this.text,
    this.language,
    this.community,
    this.role,
    required this.validity,
  });
  final String text;
  final String? language, community, role;
  final Validity validity;
  factory ContextualName.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'text', 'language', 'community', 'role', 'validity'});
    return ContextualName(
      text: f.string('text'),
      language: f.optionalString('language'),
      community: f.optionalString('community'),
      role: f.optionalString('role'),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('text', CanonicalString(text)),
    MapEntry('language', _nullableString(language)),
    MapEntry('community', _nullableString(community)),
    MapEntry('role', _nullableString(role)),
    MapEntry('validity', validity.toWire()),
  ]);
}

/// World association and physical location remain distinct authored facts.
final class WorldAssociation {
  WorldAssociation({
    required this.world,
    required this.role,
    required this.validity,
    required Map<String, DomainValue> qualifiers,
  }) : qualifiers = Map.unmodifiable(qualifiers);
  final WorldId world;
  final String role;
  final Validity validity;
  final Map<String, DomainValue> qualifiers;
  factory WorldAssociation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'world', 'role', 'validity', 'qualifiers'});
    return WorldAssociation(
      world: WorldId.parse(f.string('world')),
      role: f.string('role'),
      validity: Validity.fromWire(f.require('validity')),
      qualifiers: _values(f, 'qualifiers'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('world', CanonicalString(world.value)),
    MapEntry('role', CanonicalString(role)),
    MapEntry('validity', validity.toWire()),
    MapEntry('qualifiers', _valueMap(qualifiers)),
  ]);
  @override
  bool operator ==(Object other) =>
      other is WorldAssociation && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toWire().toText().hashCode;
}

final class EntityRecord extends RecordPayload {
  EntityRecord({
    required Iterable<ContextualName> names,
    this.classification,
    required this.classificationResolution,
    required Iterable<WorldAssociation> worldAssociations,
    required Map<String, String> labels,
    required Map<String, DomainValue> metadata,
  }) : names = List.unmodifiable(names),
       worldAssociations = List.unmodifiable(worldAssociations),
       labels = Map.unmodifiable(labels),
       metadata = Map.unmodifiable(metadata);
  final List<ContextualName> names;
  final RecordId? classification;
  final ClassificationResolution classificationResolution;
  final List<WorldAssociation> worldAssociations;
  final Map<String, String> labels;
  final Map<String, DomainValue> metadata;
  factory EntityRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.entity, {
      'names',
      'classification',
      'classificationResolution',
      'worldAssociations',
      'labels',
      'metadata',
    });
    final classification = f.optionalString('classification');
    return EntityRecord(
      names: f.array('names').map(ContextualName.fromWire),
      classification: classification == null
          ? null
          : RecordId.parse(classification),
      classificationResolution: ClassificationResolution.fromName(
        f.string('classificationResolution'),
      ),
      worldAssociations: f
          .array('worldAssociations')
          .map(WorldAssociation.fromWire),
      labels: _strings(f, 'labels'),
      metadata: _values(f, 'metadata'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.entity;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('names', CanonicalArray(names.map((n) => n.toWire()))),
    MapEntry('classification', _nullableId(classification)),
    MapEntry(
      'classificationResolution',
      CanonicalString(classificationResolution.name),
    ),
    MapEntry(
      'worldAssociations',
      CanonicalArray(worldAssociations.map((w) => w.toWire())),
    ),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('metadata', _valueMap(metadata)),
  ]);
}
