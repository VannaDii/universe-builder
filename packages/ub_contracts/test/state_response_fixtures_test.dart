@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/state-responses.json')
        .readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust state response $index:$type', () {
      final input = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final output = switch (type) {
        'InitializationReceipt' => InitializationReceipt.fromWire(
          input,
        ).toWire(),
        'DerivedFact' => DerivedFact.fromWire(input).toWire(),
        'ObjectEvidence' => ObjectEvidence.fromWire(input).toWire(),
        'ObjectConflict' => ObjectConflict.fromWire(input).toWire(),
        'ContextualNameEvidence' => ContextualNameEvidence.fromWire(
          input,
        ).toWire(),
        'EffectiveObject' => EffectiveObject.fromWire(input).toWire(),
        'State' => State.fromWire(input).toWire(),
        _ => throw StateError('Unknown fixture'),
      };
      expect(output.toText(), (f['canonical_utf8']! as CanonicalString).value);
    });
  }
}
