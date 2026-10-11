@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final fixtures = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/workflow-requests.json')
        .readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in fixtures.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final input = {
      for (final e in (f['input']! as CanonicalObject).fields) e.key: e.value,
    };
    test('owning Rust workflow request $index', () {
      final request = Request.fromTool(
        (input['tool']! as CanonicalString).value,
        input['args']!,
      );
      expect(
        request.toWire().toText(),
        (f['canonical_utf8']! as CanonicalString).value,
      );
      expect(
        Request.decode(request.toWire().toBytes()).toWire().toText(),
        request.toWire().toText(),
      );
    });
  }
}
