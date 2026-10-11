import 'package:ub_domain/ub_domain.dart';

/// Internal closed DTO boundary; parsing retains exact numeric tokens.
final class WireFields {
  WireFields(CanonicalValue value, Set<String> allowed) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected contract object');
    }
    values = {for (final e in value.fields) e.key: e.value};
    if (values.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unknown contract field');
    }
  }
  late final Map<String, CanonicalValue> values;
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
  List<CanonicalValue> array(String key, {bool defaultEmpty = false}) =>
      defaultEmpty && !values.containsKey(key)
      ? const []
      : switch (require(key)) {
          CanonicalArray(:final items) => items,
          _ => throw FormatException('Expected array: $key'),
        };
  T? optional<T>(String key, T Function(CanonicalValue) parse) =>
      !values.containsKey(key) || values[key] is CanonicalNull
      ? null
      : parse(require(key));
  BigInt u64(String key) {
    final value = require(key);
    if (value is! CanonicalNumber ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value.digits)) {
      throw FormatException('Expected u64: $key');
    }
    return checkedU64(BigInt.parse(value.digits));
  }
}

BigInt checkedU64(BigInt value) {
  if (value < BigInt.zero || value > BigInt.parse('18446744073709551615')) {
    throw const FormatException('Integer outside u64');
  }
  return value;
}

String wireString(CanonicalValue value) => switch (value) {
  CanonicalString(:final value) => value,
  _ => throw const FormatException('Expected contract string'),
};
