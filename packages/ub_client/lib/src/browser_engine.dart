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

  /// A file adapter streams selected content; this connection retains the same
  /// session, single-flight and unknown-outcome rules as ordinary calls.
  Future<CanonicalValue> reviewArchiveFile({
    required Future<BrowserEngineResponse> Function(String csrf) upload,
  }) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    _busy = true;
    _broken = true;
    late EngineResult result;
    try {
      final response = await upload(csrf);
      if (response.status != 200 ||
          response.bytes.length > maxFrameBytes ||
          _closed) {
        throw const FormatException('Upload response unavailable');
      }
      result = EngineResult.fromWire(
        CanonicalValue.parseWireJson(utf8.decode(response.bytes)),
      );
    } on Object {
      _abort();
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      _busy = false;
    }
    _broken = false;
    return switch (result) {
      EngineSuccess(:final value) => value,
      EngineFailure(:final error) => throw error,
    };
  }

  /// Prepare a pinned, complete-history archive for a browser-native download.
  /// The one-use URL contains no filesystem path or durable credential.
  Future<PreparedBrowserArchive> prepareArchiveDownload(
    Selector universe,
  ) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    late Uint8List input;
    try {
      input = CanonicalObject([MapEntry('universe', universe.toWire())])
          .toBytes();
      if (input.length > maxFrameBytes) {
        throw const FormatException('Frame too large');
      }
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    _busy = true;
    _broken = true;
    try {
      final response = await _request(
        '/engine/browser/prepare-download',
        input,
        csrf,
      );
      final prepared = PreparedBrowserArchive.fromWire(
        CanonicalValue.parseWireJson(utf8.decode(response)),
      );
      if (_closed) throw const FormatException('Connection closed');
      _broken = false;
      return prepared;
    } on Object {
      _abort();
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      _busy = false;
    }
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

/// Metadata from the service's pinned relational archive snapshot.
final class PreparedBrowserArchive {
  const PreparedBrowserArchive({
    required this.path,
    required this.digest,
    required this.bytes,
    required this.manifest,
  });
  final String path, digest;
  final int bytes;
  final CanonicalObject manifest;
  factory PreparedBrowserArchive.fromWire(CanonicalValue value) {
    final fields = WireFields(value, {'path', 'digest', 'bytes', 'manifest'});
    final path = fields.string('path'), digest = fields.string('digest');
    final bytes = fields.u64('bytes');
    final manifest = fields.require('manifest');
    if (!RegExp(r'^/engine/browser/download/[A-Za-z0-9_-]{43}$')
            .hasMatch(path) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        bytes < BigInt.one ||
        bytes >
            BigInt.from(
              ReadMoveChunkEngineRequest.chunkBytes *
                  ReadMoveChunkEngineRequest.maxChunks,
            ) ||
        manifest is! CanonicalObject) {
      throw const FormatException('Invalid prepared archive');
    }
    return PreparedBrowserArchive(
      path: path,
      digest: digest,
      bytes: bytes.toInt(),
      manifest: manifest,
    );
  }
}
