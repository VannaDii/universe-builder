import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/local_socket.dart';
import 'package:ub_store/profile_credentials.dart';

enum LocalEngineFailure {
  unavailable,
  unsafeEndpoint,
  credentialUnavailable,
  handshakeFailed,
  interrupted,
  reconnectRequired,
  busy,
  closed,
  invalidRequest,
}

/// Never retain socket/parser exceptions that could embed credentials or content.
final class LocalEngineException implements Exception {
  const LocalEngineException(this.failure);
  final LocalEngineFailure failure;
  @override
  String toString() => 'LocalEngineException(${failure.name})';
}

/// One correlated request at a time, matching the maintained local client.
/// A failed transport poisons the connection; no mutation is replayed implicitly.
final class LocalEngineClient {
  LocalEngineClient._(this._socket, this._frames, this.welcome);
  final Socket _socket;
  final StreamIterator<Uint8List> _frames;
  final EngineWelcome welcome;
  BigInt _next = BigInt.one;
  bool _busy = false, _broken = false, _closed = false;

  static Future<LocalEngineClient> connect({
    required String root,
    required ProfileId profile,
    required String clientName,
  }) async {
    Socket? socket;
    StreamIterator<Uint8List>? frames;
    var failure = LocalEngineFailure.unsafeEndpoint;
    try {
      if (Directory(root).existsSync() == false ||
          Directory('$root/profiles').existsSync() == false) {
        throw const LocalEngineException(LocalEngineFailure.unavailable);
      }
      final endpoint = '$root/engine.sock';
      checkLocalSocketEndpoint(endpoint);
      failure = LocalEngineFailure.unavailable;
      socket = await Socket.connect(
        InternetAddress(endpoint, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 5),
      );
      failure = LocalEngineFailure.unsafeEndpoint;
      validateLocalSocketPeer(socket);
      failure = LocalEngineFailure.credentialUnavailable;
      final credential = ProfileCredentialStore.read(
        root: root,
        profile: profile,
      );
      failure = LocalEngineFailure.handshakeFailed;
      if (utf8.encode(clientName).length > 128) {
        throw const FormatException('Client name too long');
      }
      final hello = EngineHello(
        protocolVersion: protocolVersion,
        profileId: profile,
        credential: Credential(credential),
        clientName: clientName,
      );
      frames = StreamIterator(decodeLengthPrefixedFrames(socket));
      socket.add(encodeLengthPrefixedFrame(hello.toWire().toBytes()));
      await socket.flush().timeout(const Duration(seconds: 5));
      if (!await frames.moveNext().timeout(const Duration(seconds: 5))) {
        throw const FormatException('Handshake rejected');
      }
      final welcome = EngineWelcome.decode(frames.current);
      if (welcome.protocolVersion != protocolVersion ||
          welcome.principal != profile ||
          welcome.maxFrameBytes != BigInt.from(maxFrameBytes) ||
          welcome.maxInFlight != BigInt.from(engineMaxInFlight)) {
        throw const FormatException('Incompatible engine handshake');
      }
      return LocalEngineClient._(socket, frames, welcome);
    } on Object catch (error) {
      socket?.destroy();
      if (frames != null) await _cancel(frames);
      if (error is LocalEngineException) rethrow;
      if (error is FileSystemException && error.osError?.errorCode == 2) {
        failure = LocalEngineFailure.unavailable;
      }
      throw LocalEngineException(failure);
    }
  }

  Future<CanonicalValue> call(EngineRequest request) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    late Uint8List message;
    try {
      message = encodeLengthPrefixedFrame(
        EngineCall(id: _next, request: request).toWire().toBytes(),
      );
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    final id = _next;
    _next += BigInt.one;
    _busy = true;
    _broken = true;
    late EngineReply reply;
    try {
      reply = await (() async {
        _socket.add(message);
        await _socket.flush();
        if (!await _frames.moveNext()) {
          throw const FormatException('Engine disconnected');
        }
        final received = EngineReply.decode(_frames.current);
        if (received.id != id) {
          throw const FormatException('Response correlation mismatch');
        }
        return received;
      })().timeout(const Duration(seconds: 15));
    } on Object {
      _socket.destroy();
      await _cancel(_frames);
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      _busy = false;
    }
    _broken = false;
    return switch (reply.result) {
      EngineSuccess(:final value) => value,
      EngineFailure(:final error) => throw error,
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    await _cancel(_frames);
  }

  static Future<void> _cancel(StreamIterator<Uint8List> frames) async {
    try {
      await frames.cancel();
    } on Object {
      // Cleanup must not replace a redacted transport failure with raw content.
    }
  }
}
