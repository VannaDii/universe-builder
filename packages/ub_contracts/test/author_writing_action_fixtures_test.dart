@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/author-writing-actions.json')
        .readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    test('owning Rust private author action $index', () {
      final input = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final output = AuthorWritingAction.fromWire(input).toWire();
      expect(
        output.toText(),
        CanonicalValue.parseWireJson(
          (f['expected_wire']! as CanonicalString).value,
        ).toText(),
      );
    });
  }
}
