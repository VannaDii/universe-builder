import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';
import 'references.dart';
import 'time_space.dart';

const maxSequenceItems = 1000;
const maxStructuredFields = 512;
const maxDigitRun = 1024;

/// Typed authored values. [toWire] preserves the existing serde record format;
/// [toCanonical] preserves the separate domain-value comparison format.
sealed class DomainValue {
  const DomainValue();
  CanonicalObject toWire();
  CanonicalObject toCanonical() => toWire();
  void validate() {}
  @override
  bool operator ==(Object other) =>
      other is DomainValue &&
      runtimeType == other.runtimeType &&
      toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;

  static DomainValue fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) throw const FormatException('Value nesting limit');
    final fields = Fields(value);
    final kind = fields.string('kind');
    DomainValue child(String key) =>
        fromWire(fields.require(key), depth: depth + 1);
    void allow(Set<String> names) => fields.allow({'kind', ...names});
    switch (kind) {
      case 'text':
        allow({'text'});
        return TextValue(fields.string('text'));
      case 'boolean':
        allow({'value'});
        return BooleanValue(fields.boolean('value'));
      case 'integer':
        allow({'digits'});
        return IntegerValue(fields.string('digits'));
      case 'decimal':
        allow({'digits'});
        return DecimalValue(fields.string('digits'));
      case 'rational':
        allow({'numerator', 'denominator'});
        return RationalValue(
          fields.string('numerator'),
          fields.string('denominator'),
        );
      case 'quantity':
        allow({'value', 'unit'});
        return QuantityValue(
          child('value'),
          UnitId.parse(fields.string('unit')),
        );
      case 'range':
        allow({'lower', 'upper', 'lower_inclusive', 'upper_inclusive', 'unit'});
        final unit = fields.optionalString('unit');
        return RangeValue(
          lower: child('lower'),
          upper: child('upper'),
          lowerInclusive: fields.boolean('lower_inclusive'),
          upperInclusive: fields.boolean('upper_inclusive'),
          unit: unit == null ? null : UnitId.parse(unit),
        );
      case 'entity_ref':
      case 'record_ref':
      case 'proposition_ref':
        allow({'ref'});
        return ReferenceValue(
          ValueReferenceKind.parse(kind),
          RecordRef.fromCanonical(fields.require('ref')),
        );
      case 'temporal':
        allow({'temporal'});
        return TemporalValue(
          TemporalExpression.fromWire(
            fields.require('temporal'),
            depth: depth + 1,
          ),
        );
      case 'spatial':
        allow({'spatial'});
        return SpatialValue(
          SpatialExpression.fromWire(
            fields.require('spatial'),
            depth: depth + 1,
          ),
        );
      case 'enum':
        allow({'definition', 'key'});
        return EnumValue(
          ValueDefinitionId.parse(fields.string('definition')),
          fields.string('key'),
        );
      case 'sequence':
      case 'set':
        allow({'items'});
        final items = fields
            .array('items')
            .map((v) => fromWire(v, depth: depth + 1));
        return kind == 'sequence' ? SequenceValue(items) : SetValue(items);
      case 'structured':
        allow({'definition', 'fields'});
        final values = Fields(fields.require('fields')).values;
        return StructuredValue(
          ValueDefinitionId.parse(fields.string('definition')),
          {
            for (final entry in values.entries)
              entry.key: fromWire(entry.value, depth: depth + 1),
          },
        );
      default:
        throw FormatException('Unknown value kind: $kind');
    }
  }
}

final class TextValue extends DomainValue {
  const TextValue(this.text);
  final String text;
  @override
  CanonicalObject toWire() =>
      tagged('text', [MapEntry('text', CanonicalString(text))]);
}

final class BooleanValue extends DomainValue {
  const BooleanValue(this.value);
  final bool value;
  @override
  CanonicalObject toWire() =>
      tagged('boolean', [MapEntry('value', CanonicalBool(value))]);
}

final class IntegerValue extends DomainValue {
  const IntegerValue(this.digits);
  final String digits;
  @override
  CanonicalObject toWire() =>
      tagged('integer', [MapEntry('digits', CanonicalString(digits))]);
  @override
  void validate() {
    if (!isExactDigits(digits, allowFraction: false)) {
      throw const FormatException('Not exact integer digits');
    }
  }
}

final class DecimalValue extends DomainValue {
  const DecimalValue(this.digits);
  final String digits;
  @override
  CanonicalObject toWire() =>
      tagged('decimal', [MapEntry('digits', CanonicalString(digits))]);
  @override
  void validate() {
    if (!isExactDigits(digits, allowFraction: true)) {
      throw const FormatException('Not a finite decimal');
    }
  }
}

final class RationalValue extends DomainValue {
  const RationalValue(this.numerator, this.denominator);
  final String numerator;
  final String denominator;
  @override
  CanonicalObject toWire() => tagged('rational', [
    MapEntry('numerator', CanonicalString(numerator)),
    MapEntry('denominator', CanonicalString(denominator)),
  ]);
  @override
  void validate() {
    if (!isExactDigits(numerator, allowFraction: false) ||
        !isExactDigits(denominator, allowFraction: false) ||
        BigInt.parse(denominator) == BigInt.zero) {
      throw const FormatException(
        'Rational requires exact digits and a nonzero denominator',
      );
    }
  }
}

final class QuantityValue extends DomainValue {
  const QuantityValue(this.value, this.unit);
  final DomainValue value;
  final UnitId unit;
  @override
  CanonicalObject toWire() => tagged('quantity', [
    MapEntry('value', value.toWire()),
    MapEntry('unit', CanonicalString(unit.value)),
  ]);
  @override
  CanonicalObject toCanonical() => tagged('quantity', [
    MapEntry('value', value.toCanonical()),
    MapEntry('unit', CanonicalString(unit.value)),
  ]);
  @override
  void validate() {
    value.validate();
    if (value is! IntegerValue &&
        value is! DecimalValue &&
        value is! RationalValue) {
      throw const FormatException('Quantity inner value must be numeric');
    }
  }
}

final class RangeValue extends DomainValue {
  const RangeValue({
    required this.lower,
    required this.upper,
    required this.lowerInclusive,
    required this.upperInclusive,
    this.unit,
  });
  final DomainValue lower;
  final DomainValue upper;
  final bool lowerInclusive;
  final bool upperInclusive;
  final UnitId? unit;
  @override
  CanonicalObject toWire() => _encode(false);
  @override
  CanonicalObject toCanonical() => _encode(true);
  CanonicalObject _encode(bool canonical) => tagged('range', [
    MapEntry('lower', canonical ? lower.toCanonical() : lower.toWire()),
    MapEntry('upper', canonical ? upper.toCanonical() : upper.toWire()),
    MapEntry(
      canonical ? 'lowerInclusive' : 'lower_inclusive',
      CanonicalBool(lowerInclusive),
    ),
    MapEntry(
      canonical ? 'upperInclusive' : 'upper_inclusive',
      CanonicalBool(upperInclusive),
    ),
    if (unit != null) MapEntry('unit', CanonicalString(unit!.value)),
  ]);
  @override
  void validate() {
    if (lower case IntegerValue(:final digits)) {
      if (upper case IntegerValue(digits: final other)) {
        if ((compareExactDigits(digits, other) ?? 0) > 0) {
          throw const FormatException('Range lower exceeds upper');
        }
      }
    }
    lower.validate();
    upper.validate();
  }
}

enum ValueReferenceKind {
  entity('entity_ref'),
  record('record_ref'),
  proposition('proposition_ref');

  const ValueReferenceKind(this.wireName);
  final String wireName;
  static ValueReferenceKind parse(String name) =>
      values.firstWhere((v) => v.wireName == name);
}

final class ReferenceValue extends DomainValue {
  const ReferenceValue(this.kind, this.record);
  final ValueReferenceKind kind;
  final RecordRef record;
  @override
  CanonicalObject toWire() =>
      tagged(kind.wireName, [MapEntry('ref', record.toCanonical())]);
}

final class TemporalValue extends DomainValue {
  const TemporalValue(this.temporal);
  final TemporalExpression temporal;
  @override
  CanonicalObject toWire() => tagged('temporal', [
    MapEntry('temporal', temporal.encode(canonical: false)),
  ]);
  @override
  CanonicalObject toCanonical() => tagged('temporal', [
    MapEntry('temporal', temporal.encode(canonical: true)),
  ]);
  @override
  void validate() => temporal.validate();
}

final class SpatialValue extends DomainValue {
  const SpatialValue(this.spatial);
  final SpatialExpression spatial;
  @override
  CanonicalObject toWire() => tagged('spatial', [
    MapEntry('spatial', spatial.encode(canonical: false)),
  ]);
  @override
  CanonicalObject toCanonical() =>
      tagged('spatial', [MapEntry('spatial', spatial.encode(canonical: true))]);
}

final class EnumValue extends DomainValue {
  const EnumValue(this.definition, this.key);
  final ValueDefinitionId definition;
  final String key;
  @override
  CanonicalObject toWire() => tagged('enum', [
    MapEntry('definition', CanonicalString(definition.value)),
    MapEntry('key', CanonicalString(key)),
  ]);
}

final class SequenceValue extends DomainValue {
  SequenceValue(Iterable<DomainValue> items) : items = List.unmodifiable(items);
  final List<DomainValue> items;
  @override
  CanonicalObject toWire() => tagged('sequence', [
    MapEntry('items', CanonicalArray(items.map((v) => v.toWire()))),
  ]);
  @override
  CanonicalObject toCanonical() => tagged('sequence', [
    MapEntry('items', CanonicalArray(items.map((v) => v.toCanonical()))),
  ]);
  @override
  void validate() => _validateItems(items);
}

final class SetValue extends DomainValue {
  SetValue(Iterable<DomainValue> items) : items = List.unmodifiable(items);
  final List<DomainValue> items;
  @override
  CanonicalObject toWire() => tagged('set', [
    MapEntry('items', CanonicalArray(items.map((v) => v.toWire()))),
  ]);
  @override
  CanonicalObject toCanonical() {
    final normalized = items.map((v) => v.toCanonical()).toList()
      ..sort((a, b) => compareBytes(a.toBytes(), b.toBytes()));
    return tagged('set', [MapEntry('items', CanonicalArray(normalized))]);
  }

  @override
  void validate() => _validateItems(items);
}

final class StructuredValue extends DomainValue {
  StructuredValue(this.definition, Map<String, DomainValue> fields)
    : fields = Map.unmodifiable(fields);
  final ValueDefinitionId definition;
  final Map<String, DomainValue> fields;
  @override
  CanonicalObject toWire() => _encode(false);
  @override
  CanonicalObject toCanonical() => _encode(true);
  CanonicalObject _encode(bool canonical) => tagged('structured', [
    MapEntry('definition', CanonicalString(definition.value)),
    MapEntry(
      'fields',
      CanonicalObject([
        for (final entry in fields.entries)
          MapEntry(
            entry.key,
            canonical ? entry.value.toCanonical() : entry.value.toWire(),
          ),
      ]),
    ),
  ]);
  @override
  void validate() {
    if (fields.length > maxStructuredFields) {
      throw const FormatException('Structured field bound exceeded');
    }
    for (final value in fields.values) {
      value.validate();
    }
  }
}

void _validateItems(List<DomainValue> items) {
  if (items.length > maxSequenceItems) {
    throw const FormatException('Sequence item bound exceeded');
  }
  for (final item in items) {
    item.validate();
  }
}

bool isExactDigits(String text, {required bool allowFraction}) {
  if (text.isEmpty || text.length > maxDigitRun) return false;
  var digit = false;
  var fraction = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 48 && c <= 57) {
      digit = true;
    } else if (c == 43 || c == 45) {
      if (i != 0) return false;
    } else if (c == 46 && allowFraction) {
      if (fraction) return false;
      fraction = true;
    } else {
      return false;
    }
  }
  return digit;
}

/// Existing integer ordering: explicit '+' is not a comparison token, and
/// authored negative zero keeps the signed-zero ordering. Display is untouched.
int? compareExactDigits(String a, String b) {
  String? magnitude(String text) {
    final unsigned = text.startsWith('-') ? text.substring(1) : text;
    if (unsigned.isEmpty || unsigned.codeUnits.any((c) => c < 48 || c > 57)) {
      return null;
    }
    final normalized = unsigned.replaceFirst(RegExp(r'^0+'), '');
    return normalized.isEmpty ? '0' : normalized;
  }

  final left = magnitude(a), right = magnitude(b);
  if (left == null || right == null) return null;
  final negativeA = a.startsWith('-'), negativeB = b.startsWith('-');
  if (negativeA != negativeB) return negativeA ? -1 : 1;
  final order = left.length == right.length
      ? left.compareTo(right)
      : left.length.compareTo(right.length);
  return (negativeA ? -order : order).sign;
}

int compareBytes(List<int> left, List<int> right) {
  for (var i = 0; i < left.length && i < right.length; i++) {
    final order = left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}
