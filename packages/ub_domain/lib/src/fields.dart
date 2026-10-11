import 'canonical.dart';

/// Closed DTO decoding. Transport decoding must already reject duplicate keys
/// and preserve numeric tokens before a typed DTO consumes its fields.
final class Fields {
  Fields(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected object');
    }
    values = {for (final field in value.fields) field.key: field.value};
  }
  late final Map<String, CanonicalValue> values;
  void allow(Set<String> names) {
    if (values.keys.any((name) => !names.contains(name))) {
      throw const FormatException('Unknown DTO field');
    }
  }

  CanonicalValue require(String key) =>
      values[key] ?? (throw FormatException('Missing field: $key'));
  String string(String key) => switch (require(key)) {
    CanonicalString(:final value) => value,
    _ => throw FormatException('Expected string: $key'),
  };
  bool boolean(String key) => switch (require(key)) {
    CanonicalBool(:final value) => value,
    _ => throw FormatException('Expected boolean: $key'),
  };
  List<CanonicalValue> array(String key) => switch (require(key)) {
    CanonicalArray(:final items) => items,
    _ => throw FormatException('Expected array: $key'),
  };
  String? optionalString(String key) =>
      values[key] == null || values[key] is CanonicalNull ? null : string(key);
}

CanonicalObject tagged(
  String kind,
  Iterable<MapEntry<String, CanonicalValue>> fields,
) => CanonicalObject([MapEntry('kind', CanonicalString(kind)), ...fields]);
