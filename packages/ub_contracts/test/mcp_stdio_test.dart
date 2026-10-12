import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  Stream<List<int>> input(String text) => Stream.value(utf8.encode(text));

  test(
    'accepts fragmented UTF-8, coalesced frames, CRLF and final EOF',
    () async {
      const text = '{"text":"é😀"}\r\n{}\n{"last":true}';
      final bytes = utf8.encode(text);
      for (var split = 0; split <= bytes.length; split++) {
        final result = await decodeMcpStdio(
          Stream.fromIterable([
            bytes.sublist(0, split),
            <int>[],
            bytes.sublist(split),
          ]),
        ).toList();
        expect(result.map((v) => v.toText()), [
          '{"text":"é😀"}',
          '{}',
          '{"last":true}',
        ]);
      }
      expect(
        await decodeMcpStdio(
          Stream.fromIterable([
            for (final byte in bytes) [byte],
          ]),
        ).length,
        3,
      );
    },
  );

  test('preserves maximum u64 and exact decimal tokens', () async {
    final value = await decodeMcpStdio(
      input('{"id":18446744073709551615,"amount":1.00000000000000000001}\n'),
    ).single;
    expect(
      value.toText(),
      '{"amount":1.00000000000000000001,"id":18446744073709551615}',
    );
  });

  test('rejects duplicate keys, nonobjects and blank newline frames', () async {
    for (final text in [
      '{"id":1,"id":2}\n',
      r'{"id":1,"\u0069d":2}',
      '[]\n',
      'null\n',
      '1\n',
      '\n',
      '\r\n',
      '{}\n\n',
    ]) {
      await expectLater(
        decodeMcpStdio(input(text)).toList(),
        throwsFormatException,
        reason: text,
      );
    }
    for (final text in ['', '\r']) {
      expect(await decodeMcpStdio(input(text)).toList(), isEmpty);
    }
  });

  test('rejects malformed UTF-8 and a leading JSON BOM', () async {
    for (final bytes in [
      [0xff, 10],
      [123, 34, 97, 34, 58, 34, 0xc3, 34, 125, 10],
      [0xef, 0xbb, 0xbf, 123, 125, 10],
    ]) {
      await expectLater(
        decodeMcpStdio(Stream.value(bytes)).toList(),
        throwsFormatException,
      );
    }
  });

  test(
    'accepts exact raw line boundary and rejects excess before more input',
    () async {
      final exact = '{"text":"${'a' * (maxFrameBytes - 11)}"}';
      expect(utf8.encode(exact).length, maxFrameBytes);
      expect(
        (await decodeMcpStdio(input('$exact\n')).single).toBytes().length,
        maxFrameBytes,
      );
      // CR is part of the raw line limit, before CRLF removal.
      await expectLater(
        decodeMcpStdio(input('$exact\r\n')).toList(),
        throwsFormatException,
      );
      var readNext = false;
      Stream<List<int>> oversized() async* {
        yield utf8.encode(exact);
        yield [32];
        readNext = true;
        yield [10];
      }

      await expectLater(
        decodeMcpStdio(oversized()).toList(),
        throwsFormatException,
      );
      expect(readNext, isFalse);
    },
  );

  test('cancellation closes upstream without reading another chunk', () async {
    var next = false, closed = false;
    Stream<List<int>> source() async* {
      try {
        yield utf8.encode('{}\n');
        next = true;
        yield utf8.encode('{}\n');
      } finally {
        closed = true;
      }
    }

    expect((await decodeMcpStdio(source()).first).toText(), '{}');
    expect(next, isFalse);
    expect(closed, isTrue);
    final error = StateError('upstream');
    await expectLater(
      decodeMcpStdio(Stream.error(error)).toList(),
      throwsA(same(error)),
    );
  });

  test('output is canonical protocol JSON plus one LF without engine cap', () {
    final value = CanonicalValue.parseWireJson(
      '{"id":18446744073709551615,"text":"é😀"}',
    ) as CanonicalObject;
    expect(encodeMcpStdio(value), [...value.toBytes(), 10]);
    final large = CanonicalObject([
      MapEntry('tools', mcpToolSchemas(advanced: true)),
    ]);
    expect(encodeMcpStdio(large).length, greaterThan(maxFrameBytes));
    expect(decodeExactUtf8(encodeMcpStdio(large)), '${large.toText()}\n');
  });

  test(
    'discovery retains order and ordinary filtering excludes exactly five',
    () {
      String name(CanonicalValue value) =>
          ((value as CanonicalObject).fields
                      .singleWhere((f) => f.key == 'name')
                      .value
                  as CanonicalString)
              .value;
      final all = mcpToolSchemas(advanced: true).items.map(name).toList();
      final ordinary = mcpToolSchemas().items.map(name).toList();
      expect(all.length, 16);
      expect(ordinary.length, 11);
      expect(all.where((n) => !ordinary.contains(n)), [
        'universe_get',
        'universe_get_state',
        'universe_get_context',
        'universe_validate',
        'universe_propose',
      ]);
      expect(ordinary, all.where((n) => ordinary.contains(n)));
    },
  );

  test(
    'initialization guidance distinguishes fixture and persistent authority',
    () {
      for (final advanced in [false, true]) {
        final fixture = mcpInstructions(fixture: true, advanced: advanced);
        final persistent = mcpInstructions(advanced: advanced);
        expect(
          fixture,
          startsWith('Explicit universe required on every tool call.'),
        );
        expect(fixture, contains('canonical commit are unavailable.'));
        expect(persistent, contains('enforces current grants'));
        expect(
          fixture.substring(fixture.indexOf('\n\n')),
          persistent.substring(persistent.indexOf('\n\n')),
        );
        expect(persistent, contains('exact author approval'));
      }
      expect(
        mcpInstructions(advanced: true),
        contains('Purpose and input boundaries:'),
      );
      expect(
        mcpInstructions(),
        isNot(contains('Purpose and input boundaries:')),
      );
    },
  );
}
