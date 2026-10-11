part of 'records.dart';

sealed class OccurrenceMode {
  const OccurrenceMode();
  CanonicalValue toWire();
  CanonicalValue toCanonical() => toWire();
  static OccurrenceMode fromWire(CanonicalValue value) {
    if (value is CanonicalString) {
      return SimpleOccurrence(OccurrenceKind.fromName(value.value));
    }
    final f = Fields(value)..allow({'descriptive'});
    final inner = Fields(f.require('descriptive'))..allow({'label'});
    return DescriptiveOccurrence(inner.string('label'));
  }
}

enum OccurrenceKind {
  occurred,
  planned,
  predicted,
  hypothetical,
  reported;

  static OccurrenceKind fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown occurrence mode'),
  );
}

final class SimpleOccurrence extends OccurrenceMode {
  const SimpleOccurrence(this.kind);
  final OccurrenceKind kind;
  @override
  CanonicalString toWire() => CanonicalString(kind.name);
}

final class DescriptiveOccurrence extends OccurrenceMode {
  const DescriptiveOccurrence(this.label);
  final String label;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'descriptive',
      CanonicalObject([MapEntry('label', CanonicalString(label))]),
    ),
  ]);
  @override
  CanonicalObject toCanonical() =>
      tagged('descriptive', [MapEntry('label', CanonicalString(label))]);
}

final class EventParticipant {
  const EventParticipant(this.record, this.role);
  final RecordRef record;
  final String role;
  factory EventParticipant.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'record', 'role'});
    return EventParticipant(
      RecordRef.fromCanonical(f.require('record')),
      f.string('role'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record', record.toCanonical()),
    MapEntry('role', CanonicalString(role)),
  ]);
}

final class EntityEffect {
  EntityEffect({
    required this.slot,
    required this.proposition,
    required this.polarity,
    required this.validity,
    required this.scope,
    required BigInt order,
  }) : order = _checkedU64(order);
  final String slot;
  final RecordRef proposition;
  final Polarity polarity;
  final Validity validity;
  final Scope scope;
  final BigInt order;
  factory EntityEffect.fromWire(CanonicalValue value) {
    final f = Fields(
      value,
    )..allow({'slot', 'proposition', 'polarity', 'validity', 'scope', 'order'});
    return EntityEffect(
      slot: f.string('slot'),
      proposition: RecordRef.fromCanonical(f.require('proposition')),
      polarity: Polarity.fromWire(f.require('polarity')),
      validity: Validity.fromWire(f.require('validity')),
      scope: Scope.fromWire(f.require('scope')),
      order: _u64(f, 'order'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('slot', CanonicalString(slot)),
    MapEntry('proposition', proposition.toCanonical()),
    MapEntry('polarity', polarity.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('order', CanonicalNumber(order.toString())),
  ]);
}

/// A canonical plan or report does not become an occurred event by being stored.
final class EventRecord extends RecordPayload {
  EventRecord({
    required this.occurrence,
    this.action,
    Iterable<WorldId> worlds = const [],
    this.region,
    required this.time,
    this.sequence,
    this.occurrenceId,
    required Iterable<EventParticipant> participants,
    Iterable<Expr> preconditions = const [],
    Iterable<EntityEffect> effects = const [],
    required Map<String, String> labels,
    this.expansionVersion,
  }) : worlds = List.unmodifiable(worlds),
       participants = List.unmodifiable(participants),
       preconditions = List.unmodifiable(preconditions),
       effects = List.unmodifiable(effects),
       labels = Map.unmodifiable(labels);
  final OccurrenceMode occurrence;
  final RecordRef? action, region;
  final List<WorldId> worlds;
  final TemporalExpression time;
  final String? sequence, occurrenceId, expansionVersion;
  final List<EventParticipant> participants;
  final List<Expr> preconditions;
  final List<EntityEffect> effects;
  final Map<String, String> labels;
  factory EventRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.event, {
      'occurrence',
      'action',
      'worlds',
      'region',
      'time',
      'sequence',
      'occurrenceId',
      'participants',
      'preconditions',
      'effects',
      'labels',
      'expansionVersion',
    });
    return EventRecord(
      occurrence: OccurrenceMode.fromWire(f.require('occurrence')),
      action: _optionalRef(f, 'action'),
      worlds: _array(f, 'worlds').map((v) => WorldId.parse(_string(v))),
      region: _optionalRef(f, 'region'),
      time: TemporalExpression.fromWire(f.require('time')),
      sequence: f.optionalString('sequence'),
      occurrenceId: f.optionalString('occurrenceId'),
      participants: f.array('participants').map(EventParticipant.fromWire),
      preconditions: _array(f, 'preconditions').map(Expr.fromWire),
      effects: _array(f, 'effects').map(EntityEffect.fromWire),
      labels: _strings(f, 'labels'),
      expansionVersion: f.optionalString('expansionVersion'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.event;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('occurrence', occurrence.toWire()),
    if (action != null) MapEntry('action', action!.toCanonical()),
    MapEntry('worlds', _idArray(worlds)),
    if (region != null) MapEntry('region', region!.toCanonical()),
    MapEntry('time', time.encode(canonical: false)),
    if (sequence != null) MapEntry('sequence', CanonicalString(sequence!)),
    if (occurrenceId != null)
      MapEntry('occurrenceId', CanonicalString(occurrenceId!)),
    MapEntry(
      'participants',
      CanonicalArray(participants.map((p) => p.toWire())),
    ),
    MapEntry(
      'preconditions',
      CanonicalArray(preconditions.map((e) => e.toWire())),
    ),
    MapEntry('effects', CanonicalArray(effects.map((e) => e.toWire()))),
    MapEntry('labels', _stringMap(labels)),
    if (expansionVersion != null)
      MapEntry('expansionVersion', CanonicalString(expansionVersion!)),
  ]);
}

final class AttributeRequirement {
  const AttributeRequirement(this.role, this.predicate, this.value);
  final String role;
  final RecordRef predicate;
  final DomainValue value;
  factory AttributeRequirement.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'role', 'predicate', 'value'});
    return AttributeRequirement(
      f.string('role'),
      RecordRef.fromCanonical(f.require('predicate')),
      DomainValue.fromWire(f.require('value')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('predicate', predicate.toCanonical()),
    MapEntry('value', value.toWire()),
  ]);
}

final class ActionDefinitionRecord extends RecordPayload {
  ActionDefinitionRecord({
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    required Iterable<AttributeRequirement> requirements,
    this.consequenceContract,
    required this.scope,
    required this.validity,
  }) : labels = Map.unmodifiable(labels),
       requirements = List.unmodifiable(requirements);
  final String namespace, key;
  final Map<String, String> labels;
  final List<AttributeRequirement> requirements;
  final ConsequenceContract? consequenceContract;
  final Scope scope;
  final Validity validity;
  factory ActionDefinitionRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.actionDefinition, {
      'namespace',
      'key',
      'labels',
      'requirements',
      'consequenceContract',
      'scope',
      'validity',
    });
    return ActionDefinitionRecord(
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      requirements: f.array('requirements').map(AttributeRequirement.fromWire),
      consequenceContract: f.values.containsKey('consequenceContract')
          ? ConsequenceContract.fromWire(f.require('consequenceContract'))
          : null,
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.actionDefinition;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry(
      'requirements',
      CanonicalArray(requirements.map((r) => r.toWire())),
    ),
    if (consequenceContract != null)
      MapEntry('consequenceContract', consequenceContract!.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
  ]);
}

final class ItemPowerRecord extends RecordPayload {
  const ItemPowerRecord({
    required this.item,
    required this.holderPredicate,
    required this.powerPredicate,
    required this.value,
    required this.scope,
    required this.validity,
  });
  final RecordRef item, holderPredicate, powerPredicate;
  final DomainValue value;
  final Scope scope;
  final Validity validity;
  factory ItemPowerRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.itemPower, {
      'item',
      'holderPredicate',
      'powerPredicate',
      'value',
      'scope',
      'validity',
    });
    return ItemPowerRecord(
      item: RecordRef.fromCanonical(f.require('item')),
      holderPredicate: RecordRef.fromCanonical(f.require('holderPredicate')),
      powerPredicate: RecordRef.fromCanonical(f.require('powerPredicate')),
      value: DomainValue.fromWire(f.require('value')),
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.itemPower;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('item', item.toCanonical()),
    MapEntry('holderPredicate', holderPredicate.toCanonical()),
    MapEntry('powerPredicate', powerPredicate.toCanonical()),
    MapEntry('value', value.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
  ]);
}
