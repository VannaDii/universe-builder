@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final fixtures = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/read-requests.json').readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in fixtures.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust wire and validation fixture $index ($type)', () {
      if (type == 'read') {
        final tool = (f['tool']! as CanonicalString).value;
        final request = ReadRequest.fromTool(tool, f['args']!);
        expect(
          request.toWire().toText(),
          (f['canonical_utf8']! as CanonicalString).value,
        );
      } else {
        final error = ProtocolError.fromWire(f['input']!);
        expect(
          error.toWire().toText(),
          (f['canonical_utf8']! as CanonicalString).value,
        );
        expect(error.code, (f['public_code']! as CanonicalString).value);
        expect(
          error.isProtocolFailure,
          (f['protocol_failure']! as CanonicalBool).value,
        );
      }
    });
  }
}
