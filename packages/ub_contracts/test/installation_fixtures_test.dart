@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/installation.json').readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust installation contract $index:$type', () {
      final input = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final output = switch (type) {
        'Credential' => Credential.fromWire(input).toWire(),
        'EngineHello' => EngineHello.fromWire(input).toWire(),
        'EngineWelcome' => EngineWelcome.fromWire(input).toWire(),
        'GrantLimits' => GrantLimits.fromWire(input).toWire(),
        'GrantSpec' => GrantSpec.fromWire(input).toWire(),
        'DraftContent' => DraftContent.fromWire(input).toWire(),
        'SavedDraft' => SavedDraft.fromWire(input).toWire(),
        'ImportMode' => CanonicalString(
          ImportMode.fromName((input as CanonicalString).value).name,
        ),
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
