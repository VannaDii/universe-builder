import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

QualifierInput qualifierInput(String key, DomainValue value) {
  if (value is ReferenceValue) {
    return QualifierInput(
      key: key,
      kind: value.kind.wireName,
      value: value.record.record.value,
      universe: value.record.universe?.value ?? '',
      originalKey: key,
    );
  }
  if (value is EnumValue) {
    return QualifierInput(
      key: key,
      kind: 'enum',
      definition: value.definition.value,
      value: value.key,
      originalKey: key,
    );
  }
  if (value is SequenceValue || value is SetValue || value is StructuredValue) {
    return QualifierInput(
      key: key,
      kind: value is SequenceValue
          ? 'sequence'
          : value is SetValue
          ? 'set'
          : 'structured',
      definition: value is StructuredValue ? value.definition.value : '',
      originalKey: key,
      children: [
        for (final entry in qualifierChildren(value).entries)
          qualifierInput(entry.key, entry.value),
      ],
    );
  }
  final unit = value is QuantityValue ? value.unit.value : '';
  final amount = value is QuantityValue ? value.value : value;
  final (kind, text, denominator) = switch (amount) {
    TextValue(:final text) => ('text', text, '1'),
    BooleanValue(:final value) => ('boolean', value.toString(), '1'),
    IntegerValue(:final digits) => ('integer', digits, '1'),
    DecimalValue(:final digits) => ('decimal', digits, '1'),
    RationalValue(:final numerator, :final denominator) => (
      'rational',
      numerator,
      denominator,
    ),
    _ => ('retain', '', '1'),
  };
  return QualifierInput(
    key: key,
    kind: kind,
    value: text,
    denominator: denominator,
    unit: unit,
    originalKey: key,
  );
}

Map<String, DomainValue> buildQualifiers(
  List<QualifierInput> input,
  Map<String, DomainValue> original,
) {
  final result = <String, DomainValue>{};
  for (final row in input) {
    if (row.key.trim().isEmpty) {
      throw const FormatException('Enter each qualifier’s name.');
    }
    if (result.containsKey(row.key)) {
      throw const FormatException('Qualifier names must be distinct.');
    }
    result[row.key] = buildQualifierValue(row, original[row.originalKey]);
  }
  return result;
}

Map<String, DomainValue> qualifierChildren(DomainValue? value) =>
    switch (value) {
      SequenceValue(:final items) || SetValue(:final items) => {
        for (var i = 0; i < items.length; i++) i.toString(): items[i],
      },
      StructuredValue(:final fields) => fields,
      _ => {},
    };

DomainValue buildQualifierValue(QualifierInput row, DomainValue? original) {
  if (row.kind == 'retain') {
    final value = original;
    if (value == null) {
      throw const FormatException(
        'The original qualifier is unavailable. Reopen current fields.',
      );
    }
    return value;
  }
  final sources = qualifierChildren(original);
  final amount = switch (row.kind) {
    'sequence' => SequenceValue(
      row.children.map((c) => buildQualifierValue(c, sources[c.originalKey])),
    ),
    'set' => SetValue(
      row.children.map((c) => buildQualifierValue(c, sources[c.originalKey])),
    ),
    'structured' => StructuredValue(
      ValueDefinitionId.parse(row.definition),
      buildQualifiers(row.children, sources),
    ),
    'entity_ref' || 'record_ref' || 'proposition_ref' => ReferenceValue(
      ValueReferenceKind.parse(row.kind),
      RecordRef(
        universe: row.universe.isEmpty ? null : UniverseId.parse(row.universe),
        record: RecordId.parse(row.value),
      ),
    ),
    'enum' => EnumValue(ValueDefinitionId.parse(row.definition), row.value),
    'text' => TextValue(row.value),
    'boolean' => BooleanValue(switch (row.value) {
      'true' => true,
      'false' => false,
      _ => throw const FormatException(
        'Choose true or false for each boolean qualifier.',
      ),
    }),
    'integer' => IntegerValue(row.value),
    'decimal' => DecimalValue(row.value),
    'rational' => RationalValue(row.value, row.denominator),
    _ => throw const FormatException('Choose a qualifier value type.'),
  };
  final value = row.unit.isEmpty
      ? amount
      : QuantityValue(amount, UnitId.parse(row.unit));
  value.validate();
  return value;
}
