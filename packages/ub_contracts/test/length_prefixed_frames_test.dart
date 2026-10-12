import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';

void main() {
  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
  Stream<Uint8List> stream(List<Uint8List> chunks) =>
      Stream.fromIterable(chunks);
  test(
    'matches the maintained big-endian header and retains exact UTF-8 bytes',
    () async {
      final body = bytes('{"text":"é😀","integer":18446744073709551615}');
      final encoded = encodeLengthPrefixedFrame(body);
      expect(encoded.sublist(0, 4), [0, 0, 0, body.length]);
      final decoded = await decodeLengthPrefixedFrames(stream([encoded]))
          .single;
      expect(decoded, orderedEquals(body));
      final empty = await decodeLengthPrefixedFrames(stream([Uint8List(4)]))
          .single;
      expect(empty, isEmpty);
    },
  );
  test(
    'handles every fragmentation boundary and multiple coalesced frames',
    () async {
      final bodies = [bytes('{"text":"é😀"}'), bytes('{}'), Uint8List(0)];
      final combined = Uint8List.fromList([
        for (final body in bodies) ...encodeLengthPrefixedFrame(body),
      ]);
      for (var split = 0; split <= combined.length; split++) {
        final actual = await decodeLengthPrefixedFrames(
          stream([
            Uint8List.sublistView(combined, 0, split),
            Uint8List(0),
            Uint8List.sublistView(combined, split),
          ]),
        ).toList();
        expect(actual.length, bodies.length);
        for (var i = 0; i < bodies.length; i++) {
          expect(actual[i], orderedEquals(bodies[i]));
        }
      }
      final individualBytes = await decodeLengthPrefixedFrames(
        stream([
          for (final value in combined) Uint8List.fromList([value]),
        ]),
      ).toList();
      expect(individualBytes.length, 3);
    },
  );
  test('checks the declared limit before consuming payload and accepts the exact boundary', () async {
    for (final length in [maxFrameBytes + 1, 0xffffffff]) {
      var consumedPayload = false;
      Stream<Uint8List> hostile() async* {
        final header = Uint8List(4);
        ByteData.sublistView(header).setUint32(0, length);
        yield header;
        consumedPayload = true;
        yield bytes('Never read this payload');
      }

      await expectLater(
        decodeLengthPrefixedFrames(hostile()).toList(),
        throwsFormatException,
      );
      expect(consumedPayload, isFalse);
    }
    final body = Uint8List(maxFrameBytes)..fillRange(0, maxFrameBytes, 97);
    final decoded = await decodeLengthPrefixedFrames(
      stream([encodeLengthPrefixedFrame(body)]),
    ).single;
    expect(decoded, orderedEquals(body));
    expect(
      () => encodeLengthPrefixedFrame(Uint8List(maxFrameBytes + 1)),
      throwsFormatException,
    );
  });
  test(
    'refuses every incomplete header and payload after a valid frame',
    () async {
      final full = encodeLengthPrefixedFrame(bytes('Retained bytes'));
      for (var length = 1; length < full.length; length++) {
        await expectLater(
          decodeLengthPrefixedFrames(
            stream([
              encodeLengthPrefixedFrame(bytes('{}')),
              Uint8List.sublistView(full, 0, length),
            ]),
          ).toList(),
          throwsFormatException,
        );
      }
      expect(await decodeLengthPrefixedFrames(stream([])).toList(), isEmpty);
    },
  );
  test(
    'preserves stream failures and stops upstream consumption on cancellation',
    () async {
      var consumedSecond = false, closed = false;
      Stream<Uint8List> upstream() async* {
        try {
          yield encodeLengthPrefixedFrame(bytes('{}'));
          consumedSecond = true;
          yield encodeLengthPrefixedFrame(bytes('{}'));
        } finally {
          closed = true;
        }
      }

      expect(
        await decodeLengthPrefixedFrames(upstream()).first,
        orderedEquals(bytes('{}')),
      );
      expect(consumedSecond, isFalse);
      expect(closed, isTrue);
      final failure = StateError('Transport stopped');
      await expectLater(
        decodeLengthPrefixedFrames(Stream<Uint8List>.error(failure)).toList(),
        throwsA(same(failure)),
      );
    },
  );
  test(
    'framing leaves strict DTO validation and maximum request IDs intact',
    () async {
      final id = BigInt.parse('18446744073709551615');
      final call = EngineCall(id: id, request: const StatusEngineRequest());
      final body = await decodeLengthPrefixedFrames(
        stream([encodeLengthPrefixedFrame(call.toWire().toBytes())]),
      ).single;
      expect(EngineCall.decode(body).id, id);
      final invalid = await decodeLengthPrefixedFrames(
        stream([
          encodeLengthPrefixedFrame(
            bytes('{"id":1,"id":2,"request":{"kind":"status"}}'),
          ),
        ]),
      ).single;
      expect(() => EngineCall.decode(invalid), throwsFormatException);
      expect(
        () => EngineCall.decode(Uint8List.fromList([0xff])),
        throwsFormatException,
      );
    },
  );
}
