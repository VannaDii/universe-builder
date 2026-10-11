@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final rows = (CanonicalValue.parseJson(
    File('../../fixtures/dart-domain/expressions.json').readAsStringSync(),
  ) as CanonicalArray).items;
  for (final row in rows) {
    final fields = {
      for (final e in (row as CanonicalObject).fields) e.key: e.value,
    };
    test(
      'Rust expression wire/comparison parity: ${(fields['name'] as CanonicalString).value}',
      () {
        final expected = fields['value']!;
        final expr = Expr.fromWire(expected);
        expect(expr.toWire().toText(), expected.toText());
        expect(
          expr.toCanonical().toText(),
          (fields['canonical'] as CanonicalString).value,
        );
      },
    );
  }
}
