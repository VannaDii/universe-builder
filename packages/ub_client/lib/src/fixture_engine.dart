import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_store/local_socket.dart';

/// One correlated call at a time. Never starts a server or replays a mutation.
final class FixtureEngineClient {
  FixtureEngineClient._(this._socket, this._frames);
  final Socket _socket;
  final StreamIterator<Uint8List> _frames;
  var _next = BigInt.zero;
  bool _busy = false, _closed = false;
  static Future<FixtureEngineClient> connect(String path) async {
    Socket? socket;
    StreamIterator<Uint8List>? frames;
    try {
      checkLocalSocketEndpoint(path);
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 5),
      );
      validateLocalSocketPeer(socket);
      frames = StreamIterator(decodeLengthPrefixedFrames(socket));
      socket.add(
        encodeLengthPrefixedFrame(
          const Hello(
            protocolVersion: protocolVersion,
            fixture: true,
          ).toWire().toBytes(),
        ),
      );
      await socket.flush().timeout(const Duration(seconds: 5));
      if (!await frames.moveNext().timeout(const Duration(seconds: 5))) {
        throw const FormatException('Fixture handshake rejected');
      }
      final hello = HelloReply.decode(frames.current);
      if (hello.protocolVersion != protocolVersion ||
          !hello.fixture ||
          hello.maxFrameBytes != BigInt.from(maxFrameBytes) ||
          hello.maxInFlight != BigInt.from(16)) {
        throw const FormatException('Incompatible fixture handshake');
      }
      return FixtureEngineClient._(socket, frames);
    } on Object {
      socket?.destroy();
      try {
        await frames?.cancel();
      } on Object {
        /* closed transport */
      }
      rethrow;
    }
  }

  Future<Response> call(Request request) async {
    if (_closed || _busy) throw StateError('Fixture connection unavailable');
    request.validate();
    _busy = true;
    final id = _next += BigInt.one;
    try {
      _socket.add(
        encodeLengthPrefixedFrame(
          ClientRequestMessage(id: id, request: request).toWire().toBytes(),
        ),
      );
      await _socket.flush().timeout(const Duration(seconds: 5));
      if (!await _frames.moveNext().timeout(const Duration(seconds: 60))) {
        throw const FormatException('Fixture connection closed');
      }
      final reply = ServerMessage.decode(_frames.current);
      if (reply.id != id) {
        throw const FormatException('Fixture correlation mismatch');
      }
      switch (reply.result) {
        case ResponseSuccess(:final response):
          return response;
        case ResponseFailure(:final error):
          throw error;
      }
    } on ProtocolError {
      rethrow;
    } on Object {
      await close();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    try {
      await _frames.cancel();
    } on Object {
      /* closed transport */
    }
  }
}
