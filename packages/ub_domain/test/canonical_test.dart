import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('ordered metadata keeps exact numbers and Unicode without changing ordinary domain ordering', () {
    const text =
        r'{"z":18446744073709551615,"a":{"y":"\u00e9","b":340282366920938463463374607431768211455}}';
    expect(
      CanonicalValue.parseWireJson(text, preserveObjectOrder: true).toText(),
      '{"z":18446744073709551615,"a":{"y":"é","b":340282366920938463463374607431768211455}}',
    );
    expect(
      CanonicalValue.parseWireJson(text).toText(),
      '{"a":{"b":340282366920938463463374607431768211455,"y":"é"},"z":18446744073709551615}',
    );
    expect(
      () => CanonicalValue.parseWireJson(
        r'{"a":1,"\u0061":2}',
        preserveObjectOrder: true,
      ),
      throwsFormatException,
    );
  });
  test(
    'exact UTF-8 retains authored BOMs and rejects malformed byte sequences',
    () {
      for (final text in [
        '',
        'café 世界\r\n',
        '\uFEFFcafé',
        '\uFEFF\uFEFF世界',
        'a\uFEFFb',
      ]) {
        expect(decodeExactUtf8(utf8.encode(text)), text);
      }
      expect(() => decodeExactUtf8([255]), throwsFormatException);
      expect(() => decodeExactUtf8([0xef, 0xbb]), throwsFormatException);
    },
  );
  test(
    'canonical ordering uses Unicode scalars and preserves authored text',
    () {
      final value = CanonicalObject([
        MapEntry('🌲', CanonicalString('é e\u0301 ßẞſ')),
        const MapEntry('\ue000', CanonicalNumber('007')),
      ]);
      expect(value.toText(), '{"\ue000":007,"🌲":"é e\u0301 ßẞſ"}');
      expect(CanonicalValue.parse(value.toBytes()).toBytes(), value.toBytes());
    },
  );

  test('wire decoding keeps exact integers above browser precision', () {
    expect(
      CanonicalValue.parseJson(
        '[9007199254740993,18446744073709551615,-9223372036854775808,'
        '18446744073709551616,-9223372036854775809,30.00,1E3,1e-03,-0]',
      ).toText(),
      '[9007199254740993,18446744073709551615,-9223372036854775808,'
      '"18446744073709551616","-9223372036854775809","30.00",'
      '"1e+3","1e-03",0]',
    );
  });

  test(
    'typed wire numbers retain decimal and arbitrary precision numeric kinds',
    () {
      final value = CanonicalValue.parseWireJson(
        '[30.00,1E3,1e-03,18446744073709551616,-9223372036854775809,-0]',
      ) as CanonicalArray;
      expect(value.items.every((v) => v is CanonicalNumber), isTrue);
      expect(
        value.toText(),
        '[30.00,1E3,1e-03,18446744073709551616,-9223372036854775809,0]',
      );
      final text = CanonicalValue.parseWireJson('"30.00"');
      expect(text, isA<CanonicalString>());
      expect(
        () => CanonicalValue.parseWireJson(r'{"a":1,"\u0061":2}'),
        throwsFormatException,
      );
    },
  );

  test('wire strings decode escapes before duplicate-key detection', () {
    expect(CanonicalValue.parseJson(r'"\u00e9\ud83c\udf32"').toText(), '"é🌲"');
    expect(
      () => CanonicalValue.parseJson(r'{"a":1,"\u0061":2}'),
      throwsFormatException,
    );
  });

  test(
    'canonical parser preserves existing raw-token and ordering behavior',
    () {
      final value = CanonicalValue.parse(utf8.encode('{"z":007,"a":30.00}'));
      expect(value.toText(), '{"z":007,"a":30.00}');
      expect(
        () => CanonicalValue.parse(utf8.encode(r'"\u00e9"')),
        throwsFormatException,
      );
      expect(CanonicalString('\u0000').toText(), r'"\u0000"');
    },
  );

  test('minimal escapes and sequence order remain stable', () {
    expect(
      CanonicalArray([
        CanonicalString('"\\\n\r\t\b\f/'),
        const CanonicalBool(true),
        const CanonicalNull(),
      ]).toText(),
      r'["\"\\\n\r\t\b\f/",true,null]',
    );
  });

  test('malformed JSON cannot become a canonical payload', () {
    for (final text in [
      '01',
      '-01',
      '1.',
      '1e',
      'NaN',
      'Infinity',
      '{"a":0,"a":1}',
      '{"a":1,}',
      '[1,]',
      '[1] trailing',
      '"\n"',
      r'"\ud800"',
      r'"\udc00"',
    ]) {
      expect(
        () => CanonicalValue.parseJson(text),
        throwsFormatException,
        reason: text,
      );
    }
    expect(() => CanonicalValue.parse([0xff]), throwsFormatException);
    expect(
      () => CanonicalString(String.fromCharCode(0xd800)),
      throwsFormatException,
    );
  });

  test('digest binds the discriminator and exact canonical bytes', () {
    final value = CanonicalValue.parseJson('{"a":1}');
    expect(
      payloadDigest('entity', value),
      isNot(payloadDigest('world', value)),
    );
    expect(payloadDigest('entity', value), hasLength(64));
  });
}
