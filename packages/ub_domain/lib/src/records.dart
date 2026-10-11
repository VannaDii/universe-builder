import 'canonical.dart';
import 'fields.dart';
import 'record_identity.dart';
import 'references.dart';
import 'scope.dart';
import 'value.dart';

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
