import 'dart:convert';
import 'dart:io';

import 'package:ub_domain/ub_domain.dart';

/// Software metadata retains its declaration order and exact numeric tokens.
/// These helpers never read or write application stores.
dynamic readSoftwareJson(File file) => _decode(
  CanonicalValue.parseWireJson(
    file.readAsStringSync(),
    preserveObjectOrder: true,
  ),
);

dynamic _decode(CanonicalValue value) => switch (value) {
  CanonicalObject(:final fields) => <String, dynamic>{
    for (final f in fields) f.key: _decode(f.value),
  },
  CanonicalArray(:final items) => items.map(_decode).toList(),
  CanonicalString(:final value) => value,
  CanonicalBool(:final value) => value,
  CanonicalNull() => null,
  CanonicalNumber() => value,
};

String prettySoftwareJson(dynamic value, [int depth = 0]) {
  final indent = '  ' * depth, childIndent = '  ' * (depth + 1);
  if (value is Map<String, dynamic>) {
    if (value.isEmpty) return '{}';
    return '{\n${value.entries.map((e) => '$childIndent${jsonEncode(e.key)}: ${prettySoftwareJson(e.value, depth + 1)}').join(',\n')}\n$indent}';
  }
  if (value is List<dynamic>) {
    if (value.isEmpty) return '[]';
    return '[\n${value.map((e) => '$childIndent${prettySoftwareJson(e, depth + 1)}').join(',\n')}\n$indent]';
  }
  return value is CanonicalNumber ? value.digits : jsonEncode(value);
}
