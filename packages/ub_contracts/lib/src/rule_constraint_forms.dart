import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class RuleConstraintInput {
  const RuleConstraintInput({
    this.cardinalityEnabled = false,
    this.chronologyEnabled = false,
    this.relation = const ExpressionReferenceInput(),
    this.grouping = '',
    this.groupingRole = '',
    this.countedRole = '',
    this.maximum = '',
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.channel = '',
    this.forwardOnly,
    this.minimumEnabled = false,
    this.maximumEnabled = false,
    this.minimumDelay = '',
    this.maximumDelay = '',
  });
  final bool cardinalityEnabled,
      chronologyEnabled,
      minimumEnabled,
      maximumEnabled;
  final ExpressionReferenceInput relation;
  final String grouping,
      groupingRole,
      countedRole,
      maximum,
      channel,
      minimumDelay,
      maximumDelay;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final bool? forwardOnly;
  RuleConstraintInput copyWith({
    bool? cardinalityEnabled,
    bool? chronologyEnabled,
    ExpressionReferenceInput? relation,
    String? grouping,
    String? groupingRole,
    String? countedRole,
    String? maximum,
    ScopeInput? scope,
    TemporalValidityInput? validity,
    String? channel,
    bool? forwardOnly,
    bool? minimumEnabled,
    bool? maximumEnabled,
    String? minimumDelay,
    String? maximumDelay,
  }) => RuleConstraintInput(
    cardinalityEnabled: cardinalityEnabled ?? this.cardinalityEnabled,
    chronologyEnabled: chronologyEnabled ?? this.chronologyEnabled,
    relation: relation ?? this.relation,
    grouping: grouping ?? this.grouping,
    groupingRole: groupingRole ?? this.groupingRole,
    countedRole: countedRole ?? this.countedRole,
    maximum: maximum ?? this.maximum,
    scope: scope ?? this.scope,
    validity: validity ?? this.validity,
    channel: channel ?? this.channel,
    forwardOnly: forwardOnly ?? this.forwardOnly,
    minimumEnabled: minimumEnabled ?? this.minimumEnabled,
    maximumEnabled: maximumEnabled ?? this.maximumEnabled,
    minimumDelay: minimumDelay ?? this.minimumDelay,
    maximumDelay: maximumDelay ?? this.maximumDelay,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('cardinality_enabled', CanonicalBool(cardinalityEnabled)),
    MapEntry('chronology_enabled', CanonicalBool(chronologyEnabled)),
    MapEntry('relation', relation.toWire()),
    MapEntry('grouping', CanonicalString(grouping)),
    MapEntry('grouping_role', CanonicalString(groupingRole)),
    MapEntry('counted_role', CanonicalString(countedRole)),
    MapEntry('maximum', CanonicalString(maximum)),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('channel', CanonicalString(channel)),
    if (forwardOnly != null)
      MapEntry('forward_only', CanonicalBool(forwardOnly!)),
    MapEntry('minimum_enabled', CanonicalBool(minimumEnabled)),
    MapEntry('maximum_enabled', CanonicalBool(maximumEnabled)),
    MapEntry('minimum_delay', CanonicalString(minimumDelay)),
    MapEntry('maximum_delay', CanonicalString(maximumDelay)),
  ]);
  factory RuleConstraintInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'cardinality_enabled',
      'chronology_enabled',
      'relation',
      'grouping',
      'grouping_role',
      'counted_role',
      'maximum',
      'scope',
      'validity',
      'channel',
      'forward_only',
      'minimum_enabled',
      'maximum_enabled',
      'minimum_delay',
      'maximum_delay',
    });
    return RuleConstraintInput(
      cardinalityEnabled: f.boolean('cardinality_enabled'),
      chronologyEnabled: f.boolean('chronology_enabled'),
      relation: ExpressionReferenceInput.fromWire(f.require('relation')),
      grouping: f.string('grouping'),
      groupingRole: f.string('grouping_role'),
      countedRole: f.string('counted_role'),
      maximum: f.string('maximum'),
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      channel: f.string('channel'),
      forwardOnly: f.values.containsKey('forward_only')
          ? f.boolean('forward_only')
          : null,
      minimumEnabled: f.boolean('minimum_enabled'),
      maximumEnabled: f.boolean('maximum_enabled'),
      minimumDelay: f.string('minimum_delay'),
      maximumDelay: f.string('maximum_delay'),
    );
  }
}
