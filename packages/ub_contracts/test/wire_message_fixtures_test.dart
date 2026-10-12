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
    File('../../fixtures/dart-contracts/wire-messages.json').readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust IPC $index:$type', () {
      final input = Uint8List.fromList(
        utf8.encode((f['input_raw']! as CanonicalString).value),
      );
      final output = switch (type) {
        'Hello' => Hello.decode(input).toWire(),
        'HelloReply' => HelloReply.decode(input).toWire(),
        'ClientMessage' => ClientMessage.decode(input).toWire(),
        'ServerMessage' => ServerMessage.decode(input).toWire(),
        _ => throw StateError('Unknown fixture'),
      };
      expect(
        output.toText(),
        CanonicalValue.parseWireJson(
          (f['expected_wire']! as CanonicalString).value,
        ).toText(),
      );
    });
  }
}
