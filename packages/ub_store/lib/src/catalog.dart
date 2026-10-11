import 'package:ub_domain/ub_domain.dart';

import 'schema.g.dart';

const maxBodyDepth = 128;

Map<String, CanonicalValue> objectFields(CanonicalValue value) {
  if (value is! CanonicalObject) throw const FormatException('Expected object');
  return {for (final field in value.fields) field.key: field.value};
}

String _string(CanonicalValue? value) {
  if (value is! CanonicalString) {
    throw const FormatException('Expected catalog string');
  }
  return value.value;
}

final class FieldModel {
  FieldModel(CanonicalValue value) {
    final fields = objectFields(value);
    model = _string(fields['model']);
    required = (fields['required'] as CanonicalBool).value;
  }
  late final String model;
  late final bool required;
}

final class BodyModel {
  BodyModel(CanonicalValue value) {
    final data = objectFields(value);
    table = _string(data['table']);
    kind = _string(data['kind']);
    fields = {
      for (final entry in objectFields(
        data['fields'] ?? CanonicalObject([]),
      ).entries)
        entry.key: FieldModel(entry.value),
    };
    variants = [
      for (final item
          in (data['variants'] as CanonicalArray?)?.items ?? <CanonicalValue>[])
        _string(item),
    ];
    item = data['item'] == null ? null : _string(data['item']);
    constant = data['const'];
    enumeration = (data['enum'] as CanonicalArray?)?.items;
    pattern = data['pattern'] == null ? null : _string(data['pattern']);
    minimum = _bound(data['minimum']);
    maximum = _bound(data['maximum']);
  }
  late final String table;
  late final String kind;
  late final Map<String, FieldModel> fields;
  late final List<String> variants;
  late final String? item;
  late final CanonicalValue? constant;
  late final List<CanonicalValue>? enumeration;
  late final String? pattern;
  late final BigInt? minimum;
  late final BigInt? maximum;
  bool get scalar => {'string', 'integer', 'boolean', 'null'}.contains(kind);

  static BigInt? _bound(CanonicalValue? value) =>
      value == null ? null : BigInt.parse((value as CanonicalNumber).digits);
}

/// Software metadata only. Persisted author records must satisfy these closed
/// models and are stored in their fixed tables, not serialized documents.
final class BodyCatalog {
  BodyCatalog() {
    final root = objectFields(CanonicalValue.parseJson(relationalCatalog));
    models = {
      for (final entry in objectFields(root['models']!).entries)
        entry.key: BodyModel(entry.value),
    };
  }
  late final Map<String, BodyModel> models;
  static final instance = BodyCatalog();
  static final _minInteger = BigInt.parse('-9223372036854775808');
  static final _maxInteger = BigInt.parse('18446744073709551615');

  BodyModel model(String name) =>
      models[name] ??
      (throw FormatException('Unknown relational model: $name'));

  bool fits(String name, CanonicalValue value, [int depth = 0]) {
    if (depth > maxBodyDepth) throw const FormatException('Body nesting limit');
    final m = model(name);
    final bool valid;
    switch (m.kind) {
      case 'union':
        valid = m.variants.any((v) => fits(v, value, depth + 1));
      case 'object':
        if (value is! CanonicalObject) return false;
        final fields = objectFields(value);
        valid =
            fields.keys.every(m.fields.containsKey) &&
            m.fields.entries.every(
              (entry) => fields.containsKey(entry.key)
                  ? fits(entry.value.model, fields[entry.key]!, depth + 1)
                  : !entry.value.required,
            );
      case 'tuple':
        valid =
            value is CanonicalArray &&
            value.items.length == m.fields.length &&
            m.fields.entries.every(
              (entry) => fits(
                entry.value.model,
                value.items[int.parse(entry.key)],
                depth + 1,
              ),
            );
      case 'array':
        valid =
            value is CanonicalArray &&
            value.items.every((v) => fits(m.item!, v, depth + 1));
      case 'map':
        valid =
            value is CanonicalObject &&
            value.fields.every((v) => fits(m.item!, v.value, depth + 1));
      case 'null':
        valid = value is CanonicalNull;
      case 'boolean':
        valid = value is CanonicalBool;
      case 'string':
        valid =
            value is CanonicalString &&
            (m.pattern == null || _patternMatches(m.pattern!, value.value));
      case 'integer':
        final integer = value is CanonicalNumber
            ? BigInt.tryParse(value.digits)
            : null;
        valid =
            integer != null &&
            integer.toString() == (value as CanonicalNumber).digits &&
            integer >= _minInteger &&
            integer <= _maxInteger &&
            (m.minimum == null || integer >= m.minimum!) &&
            (m.maximum == null || integer <= m.maximum!);
      default:
        throw FormatException('Unsupported relational model kind: ${m.kind}');
    }
    return valid &&
        (m.constant == null || m.constant!.toText() == value.toText()) &&
        (m.enumeration == null ||
            m.enumeration!.any((v) => v.toText() == value.toText()));
  }

  bool _patternMatches(String pattern, String text) {
    if (pattern == r'^(0|-?[1-9][0-9]{0,38}|-?(0|[1-9][0-9]*)\.[0-9]+)$') {
      return ExactAmount.isConsequenceDecimal(text);
    }
    if (pattern == r'^(0|-?[1-9][0-9]{0,38})$') {
      return RegExp(pattern).hasMatch(text) &&
          !text.contains('\n') &&
          !text.contains('\r');
    }
    if (pattern == r'^[0-9a-f]{64}$') {
      return text.length == 64 && RegExp(pattern).hasMatch(text);
    }
    final prefix = RegExp(r'^\^([a-z]+_)\[0-9a-f\]\{24\}\$$')
        .firstMatch(pattern)?[1];
    return prefix != null &&
        text.length == prefix.length + 24 &&
        RegExp(pattern).hasMatch(text);
  }
}
