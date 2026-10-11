part of 'records.dart';

final class ConsequenceInteger {
  ConsequenceInteger(this.digits) {
    final n = BigInt.tryParse(digits);
    if (n == null ||
        n.toString() != digits ||
        n < ExactAmount.minimum ||
        n > ExactAmount.maximum) {
      throw const FormatException('Invalid consequence integer');
    }
  }
  final String digits;
  BigInt get value => BigInt.parse(digits);
}

final class ConsequenceDecimal {
  ConsequenceDecimal(this.digits) {
    if (!ExactAmount.isConsequenceDecimal(digits)) {
      throw const FormatException('Invalid consequence decimal');
    }
  }
  final String digits;
  ExactAmount get amount => ExactAmount.tryParse(digits)!;
}

enum EffectPresence {
  required,
  optional;

  static EffectPresence fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown effect presence'),
  );
}

final class EffectTarget {
  const EffectTarget(this.role, this.predicate);
  final String role;
  final RecordRef predicate;
  factory EffectTarget.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'role', 'predicate'});
    return EffectTarget(
      f.string('role'),
      RecordRef.fromCanonical(f.require('predicate')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('predicate', predicate.toCanonical()),
  ]);
}

sealed class EffectCondition {
  const EffectCondition();
  CanonicalObject toWire();
  static EffectCondition fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'always':
        f.allow({'kind'});
        return const AlwaysEffect();
      case 'attribute_equals':
        f.allow({'kind', 'role', 'predicate', 'value'});
        return AttributeEqualsEffect(
          f.string('role'),
          RecordRef.fromCanonical(f.require('predicate')),
          DomainValue.fromWire(f.require('value')),
        );
      default:
        throw const FormatException('Unknown effect condition');
    }
  }
}

final class AlwaysEffect extends EffectCondition {
  const AlwaysEffect();
  @override
  CanonicalObject toWire() => tagged('always', []);
}

final class AttributeEqualsEffect extends EffectCondition {
  const AttributeEqualsEffect(this.role, this.predicate, this.value);
  final String role;
  final RecordRef predicate;
  final DomainValue value;
  @override
  CanonicalObject toWire() => tagged('attribute_equals', [
    MapEntry('role', CanonicalString(role)),
    MapEntry('predicate', predicate.toCanonical()),
    MapEntry('value', value.toWire()),
  ]);
}

sealed class EffectChange {
  const EffectChange();
  CanonicalObject toWire();
  static EffectChange fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'set':
        f.allow({'kind', 'polarity', 'value'});
        return SetEffect(
          Polarity.fromWire(f.require('polarity')),
          DomainValue.fromWire(f.require('value')),
        );
      case 'delta':
        f.allow({'kind', 'delta', 'minimum', 'maximum', 'unit'});
        f.require('unit');
        final unit = f.optionalString('unit');
        return DeltaEffect(
          delta: ConsequenceDecimal(f.string('delta')),
          minimum: ConsequenceDecimal(f.string('minimum')),
          maximum: ConsequenceDecimal(f.string('maximum')),
          unit: unit == null ? null : UnitId.parse(unit),
        );
      default:
        throw const FormatException('Unknown effect change');
    }
  }
}

final class SetEffect extends EffectChange {
  const SetEffect(this.polarity, this.value);
  final Polarity polarity;
  final DomainValue value;
  @override
  CanonicalObject toWire() => tagged('set', [
    MapEntry('polarity', polarity.toWire()),
    MapEntry('value', value.toWire()),
  ]);
}

final class DeltaEffect extends EffectChange {
  const DeltaEffect({
    required this.delta,
    required this.minimum,
    required this.maximum,
    required this.unit,
  });
  final ConsequenceDecimal delta, minimum, maximum;
  final UnitId? unit;
  @override
  CanonicalObject toWire() => tagged('delta', [
    MapEntry('delta', CanonicalString(delta.digits)),
    MapEntry('minimum', CanonicalString(minimum.digits)),
    MapEntry('maximum', CanonicalString(maximum.digits)),
    MapEntry('unit', _nullableId(unit)),
  ]);
}

sealed class EffectLifetime {
  const EffectLifetime();
  CanonicalObject toWire();
  static EffectLifetime fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'until_changed':
        f.allow({'kind'});
        return const UntilChangedEffect();
      case 'ticks':
        f.allow({'kind', 'count'});
        return TicksEffect(ConsequenceInteger(f.string('count')));
      default:
        throw const FormatException('Unknown effect lifetime');
    }
  }
}

final class UntilChangedEffect extends EffectLifetime {
  const UntilChangedEffect();
  @override
  CanonicalObject toWire() => tagged('until_changed', []);
}

final class TicksEffect extends EffectLifetime {
  const TicksEffect(this.count);
  final ConsequenceInteger count;
  @override
  CanonicalObject toWire() =>
      tagged('ticks', [MapEntry('count', CanonicalString(count.digits))]);
}

final class EffectSlot {
  EffectSlot({
    required this.slot,
    required int order,
    required this.presence,
    required this.target,
    required this.condition,
    required this.change,
    required this.lifetime,
  }) : order = _checkedU32(order) {
    if (order > 255) throw const FormatException('Effect order exceeds u8');
  }
  final String slot;
  final int order;
  final EffectPresence presence;
  final EffectTarget target;
  final EffectCondition condition;
  final EffectChange change;
  final EffectLifetime lifetime;
  factory EffectSlot.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'slot',
        'order',
        'presence',
        'target',
        'condition',
        'change',
        'lifetime',
      });
    return EffectSlot(
      slot: f.string('slot'),
      order: _u32(f, 'order'),
      presence: EffectPresence.fromName(f.string('presence')),
      target: EffectTarget.fromWire(f.require('target')),
      condition: EffectCondition.fromWire(f.require('condition')),
      change: EffectChange.fromWire(f.require('change')),
      lifetime: EffectLifetime.fromWire(f.require('lifetime')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('slot', CanonicalString(slot)),
    MapEntry('order', CanonicalNumber(order.toString())),
    MapEntry('presence', CanonicalString(presence.name)),
    MapEntry('target', target.toWire()),
    MapEntry('condition', condition.toWire()),
    MapEntry('change', change.toWire()),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

/// A validated declaration, never an instruction to mutate event state.
final class ConsequenceContract {
  ConsequenceContract(Iterable<EffectSlot> slots)
    : slots = List.unmodifiable(slots) {
    validate();
  }
  final List<EffectSlot> slots;
  factory ConsequenceContract.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'slots'});
    if (f.string('kind') != 'action_consequences') {
      throw const FormatException('Unknown consequence contract');
    }
    return ConsequenceContract(f.array('slots').map(EffectSlot.fromWire));
  }
  CanonicalObject toWire() => tagged('action_consequences', [
    MapEntry('slots', CanonicalArray(slots.map((s) => s.toWire()))),
  ]);
  void validate() {
    if (slots.length > 64) {
      throw const FormatException('At most 64 consequence slots');
    }
    final names = <String>{};
    final orders = <int>{};
    final targets = <(String, RecordRef)>{};
    for (final slot in slots) {
      if (!_consequenceName(slot.slot) ||
          !_consequenceName(slot.target.role) ||
          slot.order > 63 ||
          !names.add(slot.slot) ||
          !orders.add(slot.order) ||
          !targets.add((slot.target.role, slot.target.predicate))) {
        throw const FormatException(
          'Consequence slots need bounded unique names, orders and targets',
        );
      }
      if (slot.condition case AttributeEqualsEffect(
        :final role,
        :final value,
      )) {
        if (!_consequenceName(role)) {
          throw const FormatException('Invalid condition role');
        }
        value.validate();
      }
      switch (slot.change) {
        case SetEffect(:final value):
          value.validate();
        case DeltaEffect(:final delta, :final minimum, :final maximum):
          if (delta.amount.coefficient == BigInt.zero ||
              _compareAmounts(minimum.amount, maximum.amount) > 0 ||
              slot.lifetime is! UntilChangedEffect) {
            throw const FormatException(
              'Delta needs nonzero amount, increasing bounds and until_changed lifetime',
            );
          }
      }
      if (slot.lifetime case TicksEffect(:final count)) {
        if (count.value <= BigInt.zero) {
          throw const FormatException('Ticks must be positive');
        }
      }
    }
  }
}

int _compareAmounts(ExactAmount a, ExactAmount b) {
  final scale = a.scale > b.scale ? a.scale : b.scale;
  BigInt aligned(ExactAmount value) {
    final n = value.coefficient * BigInt.from(10).pow(scale - value.scale);
    if (n < ExactAmount.minimum || n > ExactAmount.maximum) {
      throw const FormatException('Exact decimal comparison overflow');
    }
    return n;
  }

  return aligned(a).compareTo(aligned(b));
}

bool _consequenceName(String name) =>
    utf8.encode(name).length <= 120 &&
    name.runes.any(
      (c) =>
          !((c >= 9 && c <= 13) ||
              c == 0x20 ||
              c == 0x85 ||
              c == 0xa0 ||
              c == 0x1680 ||
              (c >= 0x2000 && c <= 0x200a) ||
              c == 0x2028 ||
              c == 0x2029 ||
              c == 0x202f ||
              c == 0x205f ||
              c == 0x3000),
    );
