part of 'request.dart';

/// Ordinary writer input, distinct from internal typed DomainValue wrappers.
/// Decode raw JSON with CanonicalValue.parseWireJson to preserve numeric kinds.
sealed class FactValue {
  const FactValue();
  CanonicalValue toWire();
  static FactValue fromWire(CanonicalValue value) {
    switch (value) {
      case CanonicalString(:final value):
        return FactTextValue(value);
      case CanonicalBool(:final value):
        return FactBooleanValue(value);
      case CanonicalNumber():
        return FactNumberValue(value);
      case CanonicalObject(:final fields):
        // Rust's untagged union tries Object before Quantity and ignores
        // additional object members. Preserve that historical decoding rule.
        final map = {for (final e in fields) e.key: e.value};
        if (map['object'] case CanonicalString(:final value)) {
          return FactObjectValue(value);
        }
        if (map['amount'] case final CanonicalNumber amount) {
          if (map['unit'] case CanonicalString(:final value)) {
            return FactQuantityValue(amount: amount, unit: value);
          }
        }
      default:
        break;
    }
    throw const FormatException('Expected ordinary fact value');
  }
}

final class FactTextValue extends FactValue {
  const FactTextValue(this.value);
  final String value;
  @override
  CanonicalString toWire() => CanonicalString(value);
}

final class FactBooleanValue extends FactValue {
  const FactBooleanValue(this.value);
  final bool value;
  @override
  CanonicalBool toWire() => CanonicalBool(value);
}

final class FactNumberValue extends FactValue {
  FactNumberValue(CanonicalNumber value) : value = _factNumber(value);
  final CanonicalNumber value;
  @override
  CanonicalNumber toWire() => value;
}

final class FactObjectValue extends FactValue {
  const FactObjectValue(this.object);
  final String object;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('object', CanonicalString(object))]);
}

final class FactQuantityValue extends FactValue {
  FactQuantityValue({required CanonicalNumber amount, required this.unit})
    : amount = _factNumber(amount);
  final CanonicalNumber amount;
  final String unit;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('amount', amount),
    MapEntry('unit', CanonicalString(unit)),
  ]);
}

CanonicalNumber _factNumber(CanonicalNumber value) {
  final parsed = CanonicalValue.parseWireJson(value.digits);
  if (parsed is! CanonicalNumber) {
    throw const FormatException('Expected ordinary JSON number');
  }
  return parsed;
}

sealed class FactLifetime {
  const FactLifetime();
  CanonicalObject toWire();
  static FactLifetime fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'end_tick', 'end_date'});
    return switch (f.string('kind')) {
      'unspecified' => FactUnspecifiedLifetime.fromWire(value),
      'until_changed' => FactUntilChangedLifetime.fromWire(value),
      'until' => FactUntilLifetime.fromWire(value),
      _ => throw const FormatException('Unknown fact lifetime'),
    };
  }
}

final class FactUnspecifiedLifetime extends FactLifetime {
  const FactUnspecifiedLifetime();
  factory FactUnspecifiedLifetime.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'unspecified') {
      throw const FormatException('Wrong fact lifetime');
    }
    return const FactUnspecifiedLifetime();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('unspecified'))]);
}

final class FactUntilChangedLifetime extends FactLifetime {
  const FactUntilChangedLifetime();
  factory FactUntilChangedLifetime.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'until_changed') {
      throw const FormatException('Wrong fact lifetime');
    }
    return const FactUntilChangedLifetime();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('until_changed'))]);
}

final class FactUntilLifetime extends FactLifetime {
  const FactUntilLifetime({this.endTick = '', this.endDate});
  final String endTick;
  final String? endDate;
  factory FactUntilLifetime.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'end_tick', 'end_date'});
    if (f.string('kind') != 'until') {
      throw const FormatException('Wrong fact lifetime');
    }
    return FactUntilLifetime(
      endTick: f.values.containsKey('end_tick') ? f.string('end_tick') : '',
      endDate: f.optional('end_date', wireString),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('until')),
    MapEntry('end_tick', CanonicalString(endTick)),
    if (endDate != null) MapEntry('end_date', CanonicalString(endDate!)),
  ]);
}

final class FactChange {
  FactChange({
    required this.property,
    required this.value,
    this.negated = false,
    this.statement = 'objective',
    this.scope = 'unspecified',
    this.when = 'unspecified',
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
  });
  final String property;
  final FactValue value;
  final bool negated;
  final String statement;
  final String scope;
  final String when;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory FactChange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'property',
      'value',
      'negated',
      'statement',
      'scope',
      'when',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return FactChange(
      property: wireString(f.require('property')),
      value: FactValue.fromWire(f.require('value')),
      negated: f.values.containsKey('negated')
          ? _writingBool(f.require('negated'))
          : false,
      statement: f.values.containsKey('statement')
          ? wireString(f.require('statement'))
          : 'objective',
      scope: f.values.containsKey('scope')
          ? wireString(f.require('scope'))
          : 'unspecified',
      when: f.values.containsKey('when')
          ? wireString(f.require('when'))
          : 'unspecified',
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('property', CanonicalString(property)),
    MapEntry('value', value.toWire()),
    MapEntry('negated', CanonicalBool(negated)),
    MapEntry('statement', CanonicalString(statement)),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry('when', CanonicalString(when)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class ObjectChange {
  ObjectChange({
    required this.name,
    this.introduce = false,
    this.classification,
    Iterable<FactChange> facts = const [],
  }) : facts = List.unmodifiable(facts);
  final String name;
  final bool introduce;
  final String? classification;
  final List<FactChange> facts;
  factory ObjectChange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'introduce',
      'classification',
      'facts',
    });
    return ObjectChange(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
      classification: f.optional('classification', (v) => wireString(v)),
      facts: f
          .array('facts', defaultEmpty: true)
          .map((v) => FactChange.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry(
      'classification',
      classification == null
          ? const CanonicalNull()
          : CanonicalString(classification!),
    ),
    MapEntry('facts', CanonicalArray(facts.map((v) => v.toWire()))),
  ]);
}

final class DefinitionChange {
  DefinitionChange({
    required this.name,
    this.introduce = false,
    this.parent,
    this.scope = 'unspecified',
    Iterable<FactChange> sharedAttributes = const [],
    Iterable<FactChange> initialValues = const [],
  }) : sharedAttributes = List.unmodifiable(sharedAttributes),
       initialValues = List.unmodifiable(initialValues);
  final String name;
  final bool introduce;
  final String? parent;
  final String scope;
  final List<FactChange> sharedAttributes;
  final List<FactChange> initialValues;
  factory DefinitionChange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'introduce',
      'parent',
      'scope',
      'shared_attributes',
      'initial_values',
    });
    return DefinitionChange(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
      parent: f.optional('parent', (v) => wireString(v)),
      scope: f.values.containsKey('scope')
          ? wireString(f.require('scope'))
          : 'unspecified',
      sharedAttributes: f
          .array('shared_attributes', defaultEmpty: true)
          .map((v) => FactChange.fromWire(v)),
      initialValues: f
          .array('initial_values', defaultEmpty: true)
          .map((v) => FactChange.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry(
      'parent',
      parent == null ? const CanonicalNull() : CanonicalString(parent!),
    ),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'shared_attributes',
      CanonicalArray(sharedAttributes.map((v) => v.toWire())),
    ),
    MapEntry(
      'initial_values',
      CanonicalArray(initialValues.map((v) => v.toWire())),
    ),
  ]);
}

final class WritingClaim {
  WritingClaim({
    required this.subject,
    required this.property,
    required this.value,
  });
  final String subject;
  final String property;
  final FactValue value;
  factory WritingClaim.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'subject', 'property', 'value'});
    return WritingClaim(
      subject: wireString(f.require('subject')),
      property: wireString(f.require('property')),
      value: FactValue.fromWire(f.require('value')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('subject', CanonicalString(subject)),
    MapEntry('property', CanonicalString(property)),
    MapEntry('value', value.toWire()),
  ]);
}

final class WritingCorrection {
  WritingCorrection({
    required this.factHandle,
    required this.value,
    required this.reason,
  });
  final String factHandle;
  final FactValue value;
  final String reason;
  factory WritingCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'fact_handle', 'value', 'reason'});
    return WritingCorrection(
      factHandle: wireString(f.require('fact_handle')),
      value: FactValue.fromWire(f.require('value')),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('fact_handle', CanonicalString(factHandle)),
    MapEntry('value', value.toWire()),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WritingFactEnding {
  WritingFactEnding({
    required this.factHandle,
    this.endTick = '',
    this.endDate,
    required this.reason,
  });
  final String factHandle;
  final String endTick;
  final String? endDate;
  final String reason;
  factory WritingFactEnding.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'fact_handle',
      'end_tick',
      'end_date',
      'reason',
    });
    return WritingFactEnding(
      factHandle: wireString(f.require('fact_handle')),
      endTick: f.values.containsKey('end_tick')
          ? wireString(f.require('end_tick'))
          : '',
      endDate: f.optional('end_date', (v) => wireString(v)),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('fact_handle', CanonicalString(factHandle)),
    MapEntry('end_tick', CanonicalString(endTick)),
    if (endDate != null) MapEntry('end_date', CanonicalString(endDate!)),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WritingFactWithdrawal {
  WritingFactWithdrawal({required this.factHandle, required this.reason});
  final String factHandle;
  final String reason;
  factory WritingFactWithdrawal.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'fact_handle', 'reason'});
    return WritingFactWithdrawal(
      factHandle: wireString(f.require('fact_handle')),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('fact_handle', CanonicalString(factHandle)),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class ReadFactsRequest extends ReadRequest {
  ReadFactsRequest({
    required this.universe,
    required this.contextId,
    this.world,
    required Iterable<String> objectNames,
  }) : objectNames = List.unmodifiable(objectNames);
  @override
  final Selector universe;
  final ContextId contextId;
  final String? world;
  final List<String> objectNames;
  factory ReadFactsRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'context_id',
      'world',
      'object_names',
    });
    return ReadFactsRequest(
      universe: Selector.fromWire(f.require('universe')),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      world: _requestOptional(f, 'world', (v) => wireString(v)),
      objectNames: f
          .array('object_names', defaultEmpty: false)
          .map((v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_read_facts';
  @override
  CanonicalObject toArgs() => toWireFields();
  CanonicalObject toWireFields() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    MapEntry('context_id', CanonicalString(contextId.value)),
    if (world != null) MapEntry('world', CanonicalString(world!)),
    MapEntry(
      'object_names',
      CanonicalArray(objectNames.map((v) => CanonicalString(v))),
    ),
  ]);
}

final class ReadContractsRequest extends ReadRequest {
  ReadContractsRequest({
    required this.universe,
    required this.contextId,
    Iterable<String> actionNames = const [],
  }) : actionNames = List.unmodifiable(actionNames);
  @override
  final Selector universe;
  final ContextId contextId;
  final List<String> actionNames;
  factory ReadContractsRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'universe', 'context_id', 'action_names'});
    return ReadContractsRequest(
      universe: Selector.fromWire(f.require('universe')),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      actionNames: f
          .array('action_names', defaultEmpty: true)
          .map((v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_read_contracts';
  @override
  CanonicalObject toArgs() => toWireFields();
  CanonicalObject toWireFields() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry(
      'action_names',
      CanonicalArray(actionNames.map((v) => CanonicalString(v))),
    ),
  ]);
}

bool _writingBool(CanonicalValue value) => switch (value) {
  CanonicalBool(:final value) => value,
  _ => throw const FormatException("Expected boolean"),
};
