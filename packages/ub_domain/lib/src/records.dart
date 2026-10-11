import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';
import 'record_identity.dart';
import 'references.dart';
import 'scope.dart';
import 'time_space.dart';
import 'value.dart';
import 'value_shape.dart';

part 'definition_records.dart';
part 'frame_records.dart';
part 'narrative_records.dart';
part 'source_records.dart';
part 'knowledge_records.dart';
part 'appearance_records.dart';

enum AttributeMode {
  instance('instance'),
  shared('shared'),
  initialValue('initial_value');

  const AttributeMode(this.wireName);
  final String wireName;
  static AttributeMode fromWire(CanonicalValue value) =>
      switch (_string(value)) {
        'instance' => instance,
        'shared' => shared,
        'initial_value' => initialValue,
        _ => throw const FormatException('Unknown attribute mode'),
      };
}

enum Quantification {
  particular('particular'),
  universal('universal'),
  exists('exists');

  const Quantification(this.wireName);
  final String wireName;
  static Quantification fromWire(CanonicalValue value) =>
      switch (_string(value)) {
        'particular' => particular,
        'universal' => universal,
        'exists' => exists,
        _ => throw const FormatException('Unknown quantification'),
      };
}

/// Typed record families under conversion. Unsupported families are explicit;
/// there is no generic application payload or opaque metadata fallback.
sealed class RecordPayload {
  const RecordPayload();
  RecordKind get recordKind;
  CanonicalObject toWire();
  // Payload canonical form uses serde record encoding, not manual value/scope
  // comparison encodings. That distinction preserves historical record digests.
  CanonicalObject toCanonical() => toWire();
  String get digest => payloadDigest(recordKind.wireName, toWire());
  static RecordPayload fromWire(CanonicalValue value) => switch (Fields(value)
      .string('record_kind')) {
    'epistemic_attitude' => EpistemicAttitudeRecord.fromWire(value),
    'observation' => ObservationRecord.fromWire(value),
    'communication' => CommunicationRecord.fromWire(value),
    'memory' => MemoryRecord.fromWire(value),
    'secret' => SecretRecord.fromWire(value),
    'completeness' => CompletenessRecord.fromWire(value),
    'appearance' => AppearanceRecord.fromWire(value),
    'image_asset' => ImageAssetRecord.fromWire(value),
    'work' => WorkRecord.fromWire(value),
    'work_version' => WorkVersionRecord.fromWire(value),
    'scene_ref' => SceneRecord.fromWire(value),
    'passage_ref' => PassageRecord.fromWire(value),
    'saga' => SagaRecord.fromWire(value),
    'source' => SourceRecord.fromWire(value),
    'source_version' => SourceVersionRecord.fromWire(value),
    'anchor' => AnchorRecord.fromWire(value),
    'entity' => EntityRecord.fromWire(value),
    'world' => WorldRecord.fromWire(value),
    'realm' => RealmRecord.fromWire(value),
    'entity_type' => EntityTypeRecord.fromWire(value),
    'property' => PropertyRecord.fromWire(value),
    'relation' => RelationRecord.fromWire(value),
    'unit' => UnitRecord.fromWire(value),
    'calendar' => CalendarRecord.fromWire(value),
    'value_definition' => ValueDefinitionRecord.fromWire(value),
    'domain_pack' => DomainPackRecord.fromWire(value),
    'proposition' => PropositionRecord.fromWire(value),
    'assertion' => AssertionRecord.fromWire(value),
    _ => throw const FormatException('Record family port is not implemented'),
  };
  @override
  bool operator ==(Object other) =>
      other is RecordPayload &&
      runtimeType == other.runtimeType &&
      toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
}

final class PropositionRole {
  const PropositionRole(this.role, this.participant);
  final String role;
  final RecordRef participant;
  factory PropositionRole.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'role', 'participant'});
    return PropositionRole(
      f.string('role'),
      RecordRef.fromCanonical(f.require('participant')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('participant', participant.toCanonical()),
  ]);
  @override
  bool operator ==(Object other) =>
      other is PropositionRole &&
      role == other.role &&
      participant == other.participant;
  @override
  int get hashCode => Object.hash(role, participant);
}

/// A proposition describes a claim; its existence does not assert its truth.
final class PropositionRecord extends RecordPayload {
  PropositionRecord({
    required this.predicate,
    required this.subject,
    Iterable<PropositionRole> roles = const [],
    this.value,
    required this.quantification,
    required this.context,
  }) : roles = List.unmodifiable(roles);
  final RecordRef predicate, subject, context;
  final List<PropositionRole> roles;
  final DomainValue? value;
  final Quantification quantification;
  factory PropositionRecord.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'record_kind',
        'predicate',
        'subject',
        'roles',
        'value',
        'quantification',
        'context',
      });
    if (f.string('record_kind') != 'proposition') {
      throw const FormatException('Wrong proposition record kind');
    }
    return PropositionRecord(
      predicate: RecordRef.fromCanonical(f.require('predicate')),
      subject: RecordRef.fromCanonical(f.require('subject')),
      roles: _array(f, 'roles').map(PropositionRole.fromWire),
      value: f.values['value'] == null || f.values['value'] is CanonicalNull
          ? null
          : DomainValue.fromWire(f.require('value')),
      quantification: Quantification.fromWire(f.require('quantification')),
      context: RecordRef.fromCanonical(f.require('context')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.proposition;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_kind', CanonicalString(recordKind.wireName)),
    MapEntry('predicate', predicate.toCanonical()),
    MapEntry('subject', subject.toCanonical()),
    if (roles.isNotEmpty)
      MapEntry('roles', CanonicalArray(roles.map((r) => r.toWire()))),
    if (value != null) MapEntry('value', value!.toWire()),
    MapEntry('quantification', CanonicalString(quantification.wireName)),
    MapEntry('context', context.toCanonical()),
  ]);
}

final class EventEffectRef {
  const EventEffectRef(this.event, this.slot);
  final RecordRef event;
  final String slot;
  factory EventEffectRef.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'event', 'slot'});
    return EventEffectRef(
      RecordRef.fromCanonical(f.require('event')),
      f.string('slot'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('event', event.toCanonical()),
    MapEntry('slot', CanonicalString(slot)),
  ]);
  @override
  bool operator ==(Object other) =>
      other is EventEffectRef && event == other.event && slot == other.slot;
  @override
  int get hashCode => Object.hash(event, slot);
}

/// Approval does not erase context, evidence limits or opposing assertions.
final class AssertionRecord extends RecordPayload {
  AssertionRecord({
    required this.attributeMode,
    required this.proposition,
    required this.polarity,
    required this.scope,
    required this.validity,
    required this.persistence,
    required this.precision,
    Iterable<DomainValue> alternatives = const [],
    required this.basis,
    this.establishedBy,
  }) : alternatives = List.unmodifiable(alternatives);
  final AttributeMode attributeMode;
  final RecordRef proposition;
  final Polarity polarity;
  final Scope scope;
  final Validity validity;
  final PersistenceSemantics persistence;
  final Precision precision;
  final List<DomainValue> alternatives;
  final EvidenceBasis basis;
  final EventEffectRef? establishedBy;
  factory AssertionRecord.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'record_kind',
        'attributeMode',
        'proposition',
        'polarity',
        'scope',
        'validity',
        'persistence',
        'precision',
        'alternatives',
        'basis',
        'establishedBy',
      });
    if (f.string('record_kind') != 'assertion') {
      throw const FormatException('Wrong assertion record kind');
    }
    return AssertionRecord(
      attributeMode: AttributeMode.fromWire(f.require('attributeMode')),
      proposition: RecordRef.fromCanonical(f.require('proposition')),
      polarity: Polarity.fromWire(f.require('polarity')),
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
      persistence: PersistenceSemantics.fromWire(f.require('persistence')),
      precision: Precision.fromWire(f.require('precision')),
      alternatives: _array(f, 'alternatives').map(DomainValue.fromWire),
      basis: EvidenceBasis.fromWire(f.require('basis')),
      establishedBy:
          f.values['establishedBy'] == null ||
              f.values['establishedBy'] is CanonicalNull
          ? null
          : EventEffectRef.fromWire(f.require('establishedBy')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.assertion;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_kind', CanonicalString(recordKind.wireName)),
    MapEntry('attributeMode', CanonicalString(attributeMode.wireName)),
    MapEntry('proposition', proposition.toCanonical()),
    MapEntry('polarity', polarity.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('persistence', persistence.toWire()),
    MapEntry('precision', precision.toWire()),
    if (alternatives.isNotEmpty)
      MapEntry(
        'alternatives',
        CanonicalArray(alternatives.map((v) => v.toWire())),
      ),
    MapEntry('basis', basis.toWire()),
    if (establishedBy != null)
      MapEntry('establishedBy', establishedBy!.toWire()),
  ]);
}

List<CanonicalValue> _array(Fields f, String key) =>
    f.values.containsKey(key) ? f.array(key) : const [];
String _string(CanonicalValue value) {
  if (value is! CanonicalString) {
    throw const FormatException('Expected record enum string');
  }
  return value.value;
}

Fields _recordFields(CanonicalValue value, RecordKind kind, Set<String> keys) {
  final f = Fields(value)..allow({'record_kind', ...keys});
  if (f.string('record_kind') != kind.wireName) {
    throw const FormatException('Wrong record kind');
  }
  return f;
}

CanonicalObject _recordWire(
  RecordKind kind,
  Iterable<MapEntry<String, CanonicalValue>> fields,
) => CanonicalObject([
  MapEntry('record_kind', CanonicalString(kind.wireName)),
  ...fields,
]);
Map<String, String> _strings(
  Fields f,
  String key, {
  bool defaultEmpty = false,
}) {
  if (defaultEmpty && !f.values.containsKey(key)) return const {};
  final object = Fields(f.require(key));
  return Map.unmodifiable({
    for (final k in object.values.keys) k: object.string(k),
  });
}

Map<String, DomainValue> _values(
  Fields f,
  String key, {
  bool defaultEmpty = false,
}) {
  if (defaultEmpty && !f.values.containsKey(key)) return const {};
  final object = Fields(f.require(key));
  return Map.unmodifiable({
    for (final entry in object.values.entries)
      entry.key: DomainValue.fromWire(entry.value),
  });
}

CanonicalObject _stringMap(Map<String, String> map) => CanonicalObject(
  map.entries.map((e) => MapEntry(e.key, CanonicalString(e.value))),
);
CanonicalObject _valueMap(Map<String, DomainValue> map) =>
    CanonicalObject(map.entries.map((e) => MapEntry(e.key, e.value.toWire())));
CanonicalValue _nullableString(String? value) =>
    value == null ? const CanonicalNull() : CanonicalString(value);
CanonicalValue _nullableId(TypedId? id) => _nullableString(id?.value);
List<RecordId> _ids(Iterable<CanonicalValue> values) =>
    values.map((v) => RecordId.parse(_string(v))).toList();
CanonicalArray _idArray(Iterable<TypedId> ids) =>
    CanonicalArray(ids.map((id) => CanonicalString(id.value)));

final _maximumU64 = BigInt.parse('18446744073709551615');
BigInt _checkedU64(BigInt value) {
  if (value.isNegative || value > _maximumU64) {
    throw const FormatException('Unsigned 64-bit value outside range');
  }
  return value;
}

BigInt _u64(Fields fields, String key) {
  final value = fields.require(key);
  if (value is! CanonicalNumber ||
      !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value.digits)) {
    throw FormatException('Expected unsigned integer: $key');
  }
  return _checkedU64(BigInt.parse(value.digits));
}

BigInt? _optionalU64(Fields fields, String key) =>
    fields.values[key] == null || fields.values[key] is CanonicalNull
    ? null
    : _u64(fields, key);
CanonicalValue _nullableU64(BigInt? value) => value == null
    ? const CanonicalNull()
    : CanonicalNumber(_checkedU64(value).toString());
RecordRef? _optionalRef(Fields fields, String key) =>
    fields.values[key] == null || fields.values[key] is CanonicalNull
    ? null
    : RecordRef.fromCanonical(fields.require(key));
CanonicalValue _nullableRef(RecordRef? value) =>
    value?.toCanonical() ?? const CanonicalNull();

TemporalExpression? _optionalTime(Fields fields, String key) =>
    fields.values[key] == null || fields.values[key] is CanonicalNull
    ? null
    : TemporalExpression.fromWire(fields.require(key));
CanonicalValue _nullableTime(TemporalExpression? value) =>
    value?.encode(canonical: false) ?? const CanonicalNull();
CanonicalArray _refs(Iterable<RecordRef> values) =>
    CanonicalArray(values.map((r) => r.toCanonical()));
