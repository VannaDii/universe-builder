import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

QualifierInput qualifierInput(String key, DomainValue value) {
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
    if (row.kind == 'retain') {
      final value = original[row.originalKey];
      if (value == null) {
        throw const FormatException(
          'The original qualifier is unavailable. Reopen current fields.',
        );
      }
      result[row.key] = value;
      continue;
    }
    final amount = switch (row.kind) {
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
    result[row.key] = value;
  }
  return result;
}
