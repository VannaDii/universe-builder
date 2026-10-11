@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-domain/frames.json').readAsStringSync(),
  ) as CanonicalArray;
  for (var i = 0; i < cases.items.length; i++) {
    final f = {
      for (final e in (cases.items[i] as CanonicalObject).fields)
        e.key: e.value,
    };
    test('Rust frame wire and comparison parity:$i', () {
      final frame = Frame.fromWire(f['input']!);
      expect(frame.toWire().toText(), (f['wire'] as CanonicalString).value);
      expect(
        frame.toCanonical().toText(),
        (f['comparison'] as CanonicalString).value,
      );
    });
  }
}
