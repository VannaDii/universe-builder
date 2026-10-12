import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final max = BigInt.parse('18446744073709551615');
CanonicalValue wire(String raw) => CanonicalValue.parseWireJson(raw);
Uint8List bytes(String raw) => Uint8List.fromList(utf8.encode(raw));
void main() {
  test('handshake declarations preserve fixture mode limits and unknown versions without admission', () {
    expect(protocolVersion, '3');
    expect(maxFrameBytes, 1048576);
    expect(maxInFlight, 16);
    final hello = Hello.decode(
      bytes('{"protocol_version":"future","fixture":false}'),
    );
    expect(hello.protocolVersion, 'future');
    expect(hello.fixture, isFalse);
    final reply = HelloReply(
      protocolVersion: '3',
      fixture: true,
      maxFrameBytes: max,
      maxInFlight: max,
    );
    final back = HelloReply.decode(reply.toWire().toBytes());
    expect(back.maxFrameBytes, max);
    expect(back.maxInFlight, max);
    expect(back.fixture, isTrue);
    expect(
      () => Hello.fromWire(
        wire('{"protocol_version":"3","fixture":false,"approved":true}'),
      ),
      throwsFormatException,
    );
  });
  test('nested request ids preserve exact identity independently of semantic validation', () {
    final request = DescribeSummaryRequest(universe: const Selector('*'));
    final message = ClientRequestMessage(id: max, request: request);
    final back = ClientMessage.decode(
      message.toWire().toBytes(),
    ) as ClientRequestMessage;
    expect(back.id, max);
    expect(back.request.universe.value, '*');
    expect(back.request.validate, throwsA(isA<InvalidArgumentError>()));
    expect(back.request.toWire().toText(), request.toWire().toText());
  });
  test('cancel identifies in-flight request and does not imply durable cancellation or receipt', () {
    final message = ClientMessage.decode(
      ClientCancelMessage(id: max).toWire().toBytes(),
    ) as ClientCancelMessage;
    expect(message.id, max);
    expect(
      message.toWire().toText(),
      '{"id":18446744073709551615,"kind":"cancel"}',
    );
    expect(
      () =>
          ClientMessage.fromWire(wire('{"kind":"cancel","id":1,"request":{}}')),
      throwsFormatException,
    );
    expect(
      () => ClientMessage.fromWire(
        wire(
          '{"kind":"cancel","id":1,"operation_id":"op_000000000000000000000001"}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('server success retains outer correlation and inner envelope request ids separately', () {
    final response = ReadContractsResponse(
      Envelope(
        contractVersion: '3',
        requestId: BigInt.zero,
        universeId: UniverseId.parse('unv_000000000000000000000001'),
        universe: const Selector('Cycle'),
        aliasMatched: false,
        authorizationScope: 'visible',
        delivery: Delivery(complete: true),
        result: wire('{"amount":9007199254740993.00}'),
      ),
    );
    final server = ServerMessage(id: max, result: ResponseSuccess(response));
    final back = ServerMessage.decode(server.toWire().toBytes());
    final nested =
        (back.result as ResponseSuccess).response as ReadContractsResponse;
    expect(back.id, max);
    expect(nested.body.requestId, BigInt.zero);
    expect(nested.body.result.toText(), '{"amount":9007199254740993.00}');
    expect(back.toWire().toText(), contains('"Ok":'));
  });
  test('typed error replies preserve exact code classification and do not become successes', () {
    for (final error in [
      const ApprovalRequiredError(message: 'Exact approval required'),
      const DomainError(message: 'Unsupported domain input'),
    ]) {
      final server = ServerMessage(id: max, result: ResponseFailure(error));
      final back = ServerMessage.decode(server.toWire().toBytes());
      final returned = (back.result as ResponseFailure).error;
      expect(returned, error);
      expect(returned.isProtocolFailure, error.isProtocolFailure);
      expect(back.toWire().toText(), contains('"Err":'));
    }
    for (final value in [
      '{}',
      '{"ok":{}}',
      '{"Ok":null,"Err":null}',
      '{"Err":null}',
    ]) {
      expect(() => ResponseResult.fromWire(wire(value)), throwsFormatException);
    }
  });
  test('all unsigned fields reject quoted fractional negative and overflow values', () {
    for (final raw in ['-1', '1.0', '1e2', '18446744073709551616', '"1"']) {
      expect(
        () => ClientMessage.fromWire(wire('{"kind":"cancel","id":$raw}')),
        throwsFormatException,
      );
      expect(
        () => ServerMessage.fromWire(
          wire(
            '{"id":$raw,"result":{"Err":{"code":"POLICY_DENIED","message":"denied"}}}',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => HelloReply.fromWire(
          wire(
            '{"protocol_version":"3","fixture":false,"max_frame_bytes":$raw,"max_in_flight":16}',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => HelloReply.fromWire(
          wire(
            '{"protocol_version":"3","fixture":false,"max_frame_bytes":1048576,"max_in_flight":$raw}',
          ),
        ),
        throwsFormatException,
      );
    }
    expect(() => ClientCancelMessage(id: -BigInt.one), throwsFormatException);
    expect(
      () => ServerMessage(
        id: max + BigInt.one,
        result: const ResponseFailure(PolicyDeniedError(message: 'denied')),
      ),
      throwsFormatException,
    );
  });
  test('strict frame decoding rejects invalid utf8 duplicates unknown fields and oversized frames', () {
    final decoders = <Object Function(Uint8List)>[
      Hello.decode,
      HelloReply.decode,
      ClientMessage.decode,
      ServerMessage.decode,
    ];
    for (final decode in decoders) {
      expect(() => decode(Uint8List.fromList([0xff])), throwsFormatException);
      expect(() => decode(bytes('{"id":1,"id":2}')), throwsFormatException);
      expect(() => decode(Uint8List(maxFrameBytes + 1)), throwsFormatException);
    }
    expect(
      () => ClientMessage.decode(
        bytes(
          '{"kind":"request","id":1,"request":{"tool":"universe_describe","args":{"universe":"Cycle","universe":"Other","mode":"summary"}}}',
        ),
      ),
      throwsFormatException,
    );
    final raw = bytes('{"protocol_version":"3","fixture":false}');
    final exactlyBounded = Uint8List(maxFrameBytes)
      ..fillRange(0, maxFrameBytes, 32)
      ..setRange(0, raw.length, raw);
    expect(Hello.decode(exactlyBounded).protocolVersion, '3');
    expect(
      () =>
          HelloReply.fromWire(wire('{"protocol_version":"3","fixture":false}')),
      throwsFormatException,
    );
    expect(
      () => ServerMessage.fromWire(wire('{"id":1,"result":null}')),
      throwsFormatException,
    );
  });
}
