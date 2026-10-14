import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'engine_failure.dart';

typedef BrowserEnginePost = Future<BrowserEngineResponse> Function(
  String path,
  Uint8List bytes,
  String? csrf,
);

final class BrowserEngineResponse {
  const BrowserEngineResponse({required this.status, required this.bytes});
  final int status;
  final Uint8List bytes;
}

/// Uses canonical bytes rather than JavaScript JSON numbers. The adapter must
/// send only to its page's origin and keep the HttpOnly session cookie opaque.
/// Transport failure requires explicit reconnect; no application call is replayed.
final class BrowserEngineClient {
  BrowserEngineClient._(this._post, this._abort);
  final BrowserEnginePost _post;
  final void Function() _abort;
  late final EngineWelcome welcome;
  late final String csrf;
  BigInt _next = BigInt.one;
  bool _busy = false, _broken = false, _closed = false;

  static Future<BrowserEngineClient> connect({
    required BrowserEnginePost post,
    required void Function() abort,
    String? enrollmentToken,
    String? resumeCsrf,
  }) async {
    final client = BrowserEngineClient._(post, abort);
    try {
      if ((enrollmentToken == null) == (resumeCsrf == null)) {
        throw const FormatException('One session action required');
      }
      if (enrollmentToken != null) {
        if (enrollmentToken.length != 43) {
          throw const FormatException('Invalid enrollment');
        }
        final value = CanonicalValue.parseWireJson(
          utf8.decode(
            await client._request(
              '/engine/browser/exchange',
              CanonicalObject([
                MapEntry('token', CanonicalString(enrollmentToken)),
              ]).toBytes(),
              null,
            ),
          ),
        );
        final fields = WireFields(value, {'welcome', 'csrf', 'expires_at'});
        client.welcome = EngineWelcome.fromWire(fields.require('welcome'));
        client.csrf = fields.string('csrf');
        if (fields.require('expires_at') is! CanonicalNumber) {
          throw const FormatException('Invalid expiry');
        }
      } else {
        client.csrf = resumeCsrf!;
        client.welcome = EngineWelcome.decode(
          await client._request(
            '/engine/browser/hello',
            Uint8List(0),
            client.csrf,
          ),
        );
      }
      if (client.csrf.length != 43 ||
          client.welcome.protocolVersion != protocolVersion ||
          client.welcome.maxFrameBytes != BigInt.from(maxFrameBytes) ||
          client.welcome.maxInFlight != BigInt.from(engineMaxInFlight)) {
        throw const FormatException('Incompatible session handshake');
      }
      return client;
    } on Object {
      abort();
      throw const LocalEngineException(LocalEngineFailure.handshakeFailed);
    }
  }

  Future<Uint8List> _request(String path, Uint8List bytes, String? csrf) async {
    final response = await _post(
      path,
      bytes,
      csrf,
    ).timeout(const Duration(seconds: 15));
    if (response.status != 200 || response.bytes.length > maxFrameBytes) {
      throw const FormatException('Browser session unavailable');
    }
    return response.bytes;
  }

  Future<CanonicalValue> call(EngineRequest request) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    final id = _next;
    late Uint8List bytes;
    try {
      bytes = EngineCall(id: id, request: request).toWire().toBytes();
      if (bytes.length > maxFrameBytes) {
        throw const FormatException('Frame too large');
      }
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    _next += BigInt.one;
    _busy = true;
    _broken = true;
    late EngineReply reply;
    try {
      reply = EngineReply.decode(
        await _request('/engine/browser/call', bytes, csrf),
      );
      if (reply.id != id || _closed) {
        throw const FormatException('Response correlation mismatch');
      }
    } on Object {
      _abort();
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

  /// Ending the local connection leaves the browser session available on reload.
  /// Only an explicit logout revokes its server cookie/session.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _abort();
  }

  Future<void> logout() async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    _busy = true;
    try {
      final fields = WireFields(
        CanonicalValue.parseWireJson(
          utf8.decode(
            await _request('/engine/browser/logout', Uint8List(0), csrf),
          ),
        ),
        {'closed'},
      );
      if (!fields.boolean('closed')) {
        throw const FormatException('Session not closed');
      }
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      _busy = false;
      await close();
    }
  }
}
