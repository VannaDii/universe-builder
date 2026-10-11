import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('selector identity uses pinned full non-Turkic case folding', () {
    expect(selectorNormalizationVersion, 'nfc-0.1.22-casefold-0.2.0-v1');
    expect(selectorKey(' Straße '), selectorKey('STRASSE'));
    expect(selectorKey('ẞſΣςσ'), 'sssσσσ');
    expect(selectorKey('Iıİi'), 'iıi\u0307i');
    expect(selectorKey('ﬃ'), 'ffi');
    // Mtavruli was added after the original case-folding table version.
    expect(selectorKey('\u1c90'), '\u1c90');
    expect(selectorKey('\u1c90'), isNot(selectorKey('\u10d0')));
  });
  test('NFC composes, reorders and respects composition exclusions', () {
    expect(selectorKey('café'), selectorKey('cafe\u0301'));
    expect(selectorKey('A\u0315\u0300'), 'à\u0315');
    expect(selectorKey('\u0344'), '\u0308\u0301');
    expect(selectorKey('Å'), 'å');
    expect(selectorKey('\u1100\u1161\u11a8'), '각');
    expect(selectorKey('가\u11a8'), '각');
    expect(selectorKey('\u{11099}\u{110ba}'), '\u{1109a}');
    // An equal-class intervening mark blocks composition with the starter.
    expect(selectorKey('a\u0305\u0301'), 'a\u0305\u0301');
    expect(selectorKey('\u0301\u0323a'), '\u0323\u0301a');
  });
  test('trim follows Rust White_Space and preserves interior spacing', () {
    expect(selectorKey('\u00a0\u1680\u2003 Earth \u3000'), 'earth');
    expect(selectorKey('\ufeffEarth\ufeff'), '\ufeffearth\ufeff');
    expect(selectorKey('A B'), isNot(selectorKey('A  B')));
    for (final name in ['', ' ', '*', '.', ' ALL ']) {
      expect(() => selectorKey(name), throwsFormatException);
    }
  });
  test(
    'controls and bidi controls fail even at surrounding trim positions',
    () {
      for (final c in [
        0,
        9,
        10,
        13,
        0x7f,
        0x85,
        0x9f,
        0x61c,
        0x200e,
        0x200f,
        0x202a,
        0x202b,
        0x202c,
        0x202d,
        0x202e,
        0x2066,
        0x2067,
        0x2068,
        0x2069,
      ]) {
        expect(
          () => selectorKey('${String.fromCharCode(c)}Earth'),
          throwsFormatException,
        );
      }
      expect(
        () => selectorKey(String.fromCharCode(0xd800)),
        throwsFormatException,
      );
      expect(
        () => selectorKey(String.fromCharCode(0xdc00)),
        throwsFormatException,
      );
    },
  );
  test('bounds apply to authored UTF-8 bytes and Unicode scalar count', () {
    expect(selectorKey('A' * 160), 'a' * 160);
    expect(selectorKey('😀' * 160), '😀' * 160);
    expect(() => selectorKey('A' * 161), throwsFormatException);
    expect(() => selectorKey('😀' * 161), throwsFormatException);
    // Full folding may expand beyond the authored scalar bound.
    expect(selectorKey('ﬃ' * 160), 'ffi' * 160);
    expect(() => selectorKey(' ${'A' * 160}'), throwsFormatException);
  });
}
