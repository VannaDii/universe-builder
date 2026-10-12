@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/mcp.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'embedded discovery matches every maintained schema and description',
    () {
      final source = CanonicalValue.parseWireJson(
        File('../../contracts/tools.json').readAsStringSync(),
      );
      expect(mcpToolSchemas(advanced: true).toText(), source.toText());
    },
  );
}
