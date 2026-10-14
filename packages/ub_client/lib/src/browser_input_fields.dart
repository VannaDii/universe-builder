import 'dart:js_interop';

import 'package:ub_domain/ub_domain.dart';

// Entered form fields use named strings, flags and ordered children.
// Clone those structures directly; never route exact entered text through JS numbers.
JSAny? encodeBrowserInput(CanonicalValue value) => switch (value) {
  CanonicalString(:final value) => value.toJS,
  CanonicalBool(:final value) => value.toJS,
  CanonicalNull() => null,
  CanonicalArray(:final items) => items.map(encodeBrowserInput).toList().toJS,
  CanonicalObject(:final fields) => {
    for (final field in fields) field.key: encodeBrowserInput(field.value),
  }.jsify(),
  _ => throw const FormatException('Unexpected numeric input field'),
};
CanonicalValue _field(Object? value) => switch (value) {
  null => CanonicalNull(),
  String text => CanonicalString(text),
  bool flag => CanonicalBool(flag),
  List<Object?> children => CanonicalArray(children.map(_field)),
  Map<Object?, Object?> fields => CanonicalObject(
    fields.entries.map(
      (entry) => MapEntry(entry.key as String, _field(entry.value)),
    ),
  ),
  _ => throw const FormatException('Invalid input field'),
};
CanonicalValue decodeBrowserInput(JSAny value) => _field(value.dartify());
