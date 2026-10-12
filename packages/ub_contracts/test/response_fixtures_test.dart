@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/responses.json').readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    test('owning Rust response and body dispatch $index', () {
      final response = Response.decode(
        Uint8List.fromList(
          utf8.encode((f['input_raw']! as CanonicalString).value),
        ),
      );
      expect(
        response.toWire().toText(),
        CanonicalValue.parseWireJson(
          (f['expected_wire']! as CanonicalString).value,
        ).toText(),
      );
      expect(
        response.bodyJson().toText(),
        CanonicalValue.parseWireJson(
          (f['expected_body']! as CanonicalString).value,
        ).toText(),
      );
      expect(
        Response.fromTool(
          response.toolName,
          response.bodyJson(),
        ).toWire().toText(),
        response.toWire().toText(),
      );
    });
  }
}
