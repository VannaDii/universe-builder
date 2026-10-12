@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/engine-commands.json')
        .readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust private command $index:$type', () {
      final input = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final output = switch (type) {
        'EngineRequest' => EngineRequest.fromWire(input).toWire(),
        'EngineCall' => EngineCall.fromWire(input).toWire(),
        'EngineReply' => EngineReply.fromWire(input).toWire(),
        'UniverseStart' => UniverseStart.fromWire(input).toWire(),
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
