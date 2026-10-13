import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/local_http_endpoint.dart';

import 'local_engine.dart'
    show LocalEngineClient, LocalEngineException, LocalEngineFailure;

/// One correlated call at a time. Interrupted calls require an explicit new
/// connection and operation recovery; mutations are never replayed implicitly.
final class LoopbackEngineClient {
  LoopbackEngineClient._(this.endpoint, this._authorization, this._http);
  final Uri endpoint;
  final String _authorization;
  final HttpClient _http;
  late final EngineWelcome welcome;
  BigInt _next = BigInt.one;
  bool _busy = false, _broken = false, _closed = false;

  /// Reuse the maintained installed-helper startup path during the IPC
  /// transition, then use HTTP for application calls. Only connection setup is
  /// retried; this never retries an admitted engine command.
  static Future<LoopbackEngineClient> ensureRunning({
    required String root,
    required ProfileId profile,
    required String helper,
    required String clientName,
    Map<String, String>? environment,
  }) async {
    final bootstrap = await LocalEngineClient.ensureRunning(
      root: root,
      profile: profile,
      helper: helper,
      clientName: clientName,
      environment: environment,
    );
    try {
      return await discover(
        root: root,
        profile: profile,
        clientName: clientName,
      );
    } finally {
      await bootstrap.close();
    }
  }

  static Future<LoopbackEngineClient> discover({
    required String root,
    required ProfileId profile,
    required String clientName,
  }) async {
    late Uri endpoint;
    try {
      endpoint = readLocalHttpEndpoint(root);
    } on FileSystemException catch (error) {
      throw LocalEngineException(
        error.osError?.errorCode == 2
            ? LocalEngineFailure.unavailable
            : LocalEngineFailure.unsafeEndpoint,
      );
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.unsafeEndpoint);
    }
    return connectLocal(
      endpoint: endpoint,
      root: root,
      profile: profile,
      clientName: clientName,
    );
  }

  static Future<LoopbackEngineClient> connectLocal({
    required Uri endpoint,
    required String root,
    required ProfileId profile,
    required String clientName,
  }) async {
    late String credential;
    try {
      credential = ProfileCredentialStore.read(root: root, profile: profile);
    } on Object {
      throw const LocalEngineException(
        LocalEngineFailure.credentialUnavailable,
      );
    }
    return connect(
      endpoint: endpoint,
      hello: EngineHello(
        protocolVersion: protocolVersion,
        profileId: profile,
        credential: Credential(credential),
        clientName: clientName,
      ),
    );
  }

  static Future<LoopbackEngineClient> connect({
    required Uri endpoint,
    required EngineHello hello,
  }) async {
    if (endpoint.scheme != 'http' ||
        endpoint.host != '127.0.0.1' ||
        endpoint.port < 1 ||
        endpoint.port > 65535 ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        !{'', '/'}.contains(endpoint.path)) {
      throw const LocalEngineException(LocalEngineFailure.unsafeEndpoint);
    }
    final http = HttpClient()..findProxy = (_) => 'DIRECT';
    final client = LoopbackEngineClient._(
      endpoint,
      'UB ${base64Encode(hello.toWire().toBytes())}',
      http,
    );
    try {
      final bytes = await client
          ._post('/engine/hello', Uint8List(0))
          .timeout(const Duration(seconds: 5));
      final welcome = EngineWelcome.decode(bytes);
      if (welcome.protocolVersion != protocolVersion ||
          welcome.principal != hello.profileId ||
          welcome.maxFrameBytes != BigInt.from(maxFrameBytes) ||
          welcome.maxInFlight != BigInt.from(engineMaxInFlight)) {
        throw const FormatException('Incompatible engine handshake');
      }
      client.welcome = welcome;
      return client;
    } on Object {
      http.close(force: true);
      throw const LocalEngineException(LocalEngineFailure.handshakeFailed);
    }
  }

  Future<Uint8List> _post(String path, Uint8List bytes) async {
    final request = await _http.postUrl(endpoint.resolve(path));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    request.headers.contentType = ContentType.json;
    request.add(bytes);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const FormatException('Engine HTTP request failed');
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (body.length + chunk.length > maxFrameBytes) {
        throw const FormatException('Engine response size limit');
      }
      body.add(chunk);
    }
    return body.takeBytes();
  }

  Future<CanonicalValue> call(EngineRequest request) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    late Uint8List bytes;
    try {
      bytes = EngineCall(id: _next, request: request).toWire().toBytes();
      if (bytes.length > maxFrameBytes) {
        throw const FormatException('Frame too large');
      }
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    final id = _next;
    _next += BigInt.one;
    _busy = true;
    _broken = true;
    late EngineReply reply;
    try {
      reply = EngineReply.decode(
        await _post('/engine/call', bytes).timeout(const Duration(seconds: 15)),
      );
      if (reply.id != id) {
        throw const FormatException('Response correlation mismatch');
      }
    } on Object {
      _http.close(force: true);
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
    _http.close(force: true);
  }
}
