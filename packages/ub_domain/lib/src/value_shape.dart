import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';

/// A declared property shape is data, never an executable schema expression.
/// Comparison encoding is independent from the containing record's wire bytes.
sealed class ValueShape {
  const ValueShape();
  CanonicalObject toWire();
  CanonicalValue toCanonical();
  @override
  bool operator ==(Object other) =>
      other is ValueShape && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;

  static ValueShape fromWire(CanonicalValue value) {
    final f = Fields(value);
    final kind = f.string('kind');
    switch (kind) {
      case 'text':
      case 'boolean':
      case 'integer':
      case 'decimal':
      case 'rational':
      case 'temporal':
      case 'spatial':
      case 'unspecified':
        f.allow({'kind'});
        return SimpleValueShape(SimpleShapeKind.fromName(kind));
      case 'quantity':
        f.allow({'kind', 'unit'});
        return QuantityShape(UnitId.parse(f.string('unit')));
      case 'range':
        f.allow({'kind', 'unit'});
        final unit = f.optionalString('unit');
        return RangeShape(unit == null ? null : UnitId.parse(unit));
      case 'entity_ref':
        f.allow({'kind', 'subject_types'});
        return EntityRefShape(f.array('subject_types').map(_recordId));
      case 'enum':
        f.allow({'kind', 'definition'});
        return EnumShape(ValueDefinitionId.parse(f.string('definition')));
      case 'structured':
        f.allow({'kind', 'definition'});
        return StructuredShape(ValueDefinitionId.parse(f.string('definition')));
      case 'sequence':
        f.allow({'kind', 'item'});
        return SequenceShape(fromWire(f.require('item')));
      default:
        throw const FormatException('Unknown value shape');
    }
  }
}

enum SimpleShapeKind {
  text,
  boolean,
  integer,
  decimal,
  rational,
  temporal,
  spatial,
  unspecified;

  static SimpleShapeKind fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown simple shape'),
  );
}

final class SimpleValueShape extends ValueShape {
  const SimpleValueShape(this.kind);
  final SimpleShapeKind kind;
  @override
  CanonicalObject toWire() => tagged(kind.name, []);
  @override
  CanonicalString toCanonical() => CanonicalString(kind.name);
}

final class QuantityShape extends ValueShape {
  const QuantityShape(this.unit);
  final UnitId unit;
  @override
  CanonicalObject toWire() =>
      tagged('quantity', [MapEntry('unit', CanonicalString(unit.value))]);
  @override
  CanonicalObject toCanonical() => toWire();
}

final class RangeShape extends ValueShape {
  const RangeShape(this.unit);
  final UnitId? unit;
  @override
  CanonicalObject toWire() => tagged('range', [
    MapEntry(
      'unit',
      unit == null ? const CanonicalNull() : CanonicalString(unit!.value),
    ),
  ]);
  @override
  CanonicalObject toCanonical() => tagged('range', [
    if (unit != null) MapEntry('unit', CanonicalString(unit!.value)),
  ]);
}

final class EntityRefShape extends ValueShape {
  EntityRefShape(Iterable<RecordId> types)
    : subjectTypes = List.unmodifiable(types);
  final List<RecordId> subjectTypes;
  CanonicalObject _encode(String key) => tagged('entity_ref', [
    MapEntry(
      key,
      CanonicalArray(subjectTypes.map((id) => CanonicalString(id.value))),
    ),
  ]);
  @override
  CanonicalObject toWire() => _encode('subject_types');
  @override
  CanonicalObject toCanonical() => _encode('subjectTypes');
}

final class EnumShape extends ValueShape {
  const EnumShape(this.definition);
  final ValueDefinitionId definition;
  @override
  CanonicalObject toWire() => tagged('enum', [
    MapEntry('definition', CanonicalString(definition.value)),
  ]);
  @override
  CanonicalObject toCanonical() => toWire();
}

final class StructuredShape extends ValueShape {
  const StructuredShape(this.definition);
  final ValueDefinitionId definition;
  @override
  CanonicalObject toWire() => tagged('structured', [
    MapEntry('definition', CanonicalString(definition.value)),
  ]);
  @override
  CanonicalObject toCanonical() => toWire();
}

final class SequenceShape extends ValueShape {
  const SequenceShape(this.item);
  final ValueShape item;
  @override
  CanonicalObject toWire() =>
      tagged('sequence', [MapEntry('item', item.toWire())]);
  @override
  CanonicalObject toCanonical() =>
      tagged('sequence', [MapEntry('item', item.toCanonical())]);
}

RecordId _recordId(CanonicalValue value) {
  if (value is! CanonicalString) {
    throw const FormatException('Expected shape type ID');
  }
  return RecordId.parse(value.value);
}
