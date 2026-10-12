import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

/// Only validated internal universe IDs choose database namespaces. Authored
/// names/selector aliases never enter SQL identifiers or session search paths.
String postgresUniverseSchema(UniverseId universe) => '"ub_${universe.value}"';

/// PostgreSQL text excludes NUL, while the existing domain accepts it. Typed
/// authored string columns therefore use bytea containing strict UTF-8, not a
/// JSON body. Search/selector projections use their separate normalized keys.
Uint8List postgresAuthoredText(String value) {
  CanonicalString(value); // Reject unpaired surrogates before encoding.
  return Uint8List.fromList(utf8.encode(value));
}

String readPostgresAuthoredText(List<int> bytes) => decodeExactUtf8(bytes);
