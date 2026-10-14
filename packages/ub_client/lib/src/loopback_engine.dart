import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/local_http_endpoint.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/ub_store.dart' show maxImageBytes;

import 'local_engine.dart' show LocalEngineException, LocalEngineFailure;

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

  /// Start only for missing/refused discovery, under the installation's existing
  /// bootstrap lock. Authentication/safety failures never launch a helper, and
  /// readiness retries never replay an application command.
  static Future<LoopbackEngineClient> ensureRunning({
    required String root,
    required ProfileId profile,
    required String helper,
    required String clientName,
    Map<String, String>? environment,
    bool compatibilitySocket = true,
  }) async {
    Future<LoopbackEngineClient?> attempt(String directory) async {
      try {
        return await discover(
          root: directory,
          profile: profile,
          clientName: clientName,
        );
      } on LocalEngineException catch (error) {
        if (error.failure != LocalEngineFailure.unavailable) rethrow;
        return null;
      }
    }

    final existing = await attempt(root);
    if (existing != null) return existing;
    try {
      ProfileCredentialStore.read(root: root, profile: profile);
    } on Object {
      throw const LocalEngineException(
        LocalEngineFailure.credentialUnavailable,
      );
    }
    try {
      CanonicalString(clientName);
      if (utf8.encode(clientName).length > 128) {
        throw const FormatException('Client name too long');
      }
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.handshakeFailed);
    }
    final elapsed = Stopwatch()..start();
    InstallationBootstrapLock? bootstrap;
    while (bootstrap == null) {
      try {
        bootstrap = InstallationBootstrapLock.acquireExisting(root);
      } on Object {
        if (elapsed.elapsed >= const Duration(seconds: 10)) {
          throw const LocalEngineException(LocalEngineFailure.startupTimeout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    try {
      final ready = await attempt(bootstrap.root);
      if (ready != null) return ready;
      try {
        final original = File(helper);
        if (!original.isAbsolute) {
          throw const FormatException('Absolute helper required');
        }
        final executable = File(original.resolveSymbolicLinksSync());
        if (executable.uri.pathSegments.last != 'universe-engine' ||
            FileSystemEntity.typeSync(executable.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw const FormatException('Installed engine helper required');
        }
        await Process.start(
          executable.path,
          [
            '--installation',
            bootstrap.root,
            if (!compatibilitySocket) '--http-only',
          ],
          environment: environment,
          mode: ProcessStartMode.detached,
        );
      } on Object {
        throw const LocalEngineException(LocalEngineFailure.helperUnavailable);
      }
      while (true) {
        final launched = await attempt(bootstrap.root);
        if (launched != null) return launched;
        if (elapsed.elapsed >= const Duration(seconds: 10)) {
          throw const LocalEngineException(LocalEngineFailure.startupTimeout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      bootstrap.close();
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
    return _connect(endpoint, hello, HttpClient()..findProxy = (_) => 'DIRECT');
  }

  /// A hosted instance receives scoped profile identity over verified TLS.
  /// No local discovery, helper launch or plaintext fallback occurs. An explicit
  /// context can trust a private deployment's CA; certificate checks remain on.
  static Future<LoopbackEngineClient> connectHttps({
    required Uri endpoint,
    required EngineHello hello,
    SecurityContext? context,
  }) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.port < 1 ||
        endpoint.port > 65535 ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        !{'', '/'}.contains(endpoint.path)) {
      throw const LocalEngineException(LocalEngineFailure.unsafeEndpoint);
    }
    return _connect(endpoint, hello, HttpClient(context: context));
  }

  static Future<LoopbackEngineClient> _connect(
    Uri endpoint,
    EngineHello hello,
    HttpClient http,
  ) async {
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
    } on Object catch (error) {
      http.close(force: true);
      if (error is SocketException &&
          {2, 61, 111}.contains(error.osError?.errorCode)) {
        throw const LocalEngineException(LocalEngineFailure.unavailable);
      }
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

  /// An explicit local action returns a one-use enrollment token, never the
  /// durable profile credential. The browser session must be exchanged separately.
  Future<CanonicalObject> createBrowserSession() async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    _busy = true;
    try {
      final bytes = await _post(
        '/engine/browser-grant',
        Uint8List(0),
      ).timeout(const Duration(seconds: 5));
      final value = CanonicalValue.parseWireJson(utf8.decode(bytes));
      final fields = WireFields(value, {'enrollment_token', 'expires_at'});
      if (fields.string('enrollment_token').length != 43 ||
          fields.require('expires_at') is! CanonicalNumber) {
        throw const FormatException('Invalid browser enrollment');
      }
      return value as CanonicalObject;
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      _busy = false;
    }
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

  Future<CanonicalObject> downloadArchive({
    required Selector universe,
    required String destination,
  }) async {
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
        throw const FormatException('Download request bound');
      }
      protectedFile(destination, createNew: true);
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    _busy = true;
    _broken = true;
    try {
      final request = await _http
          .postUrl(endpoint.resolve('/engine/archive-file'))
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, _authorization);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.contentType = ContentType.json;
      request.add(input);
      final response = await request.close();
      final length = response.contentLength;
      final encoded = response.headers.value('x-ub-archive-manifest');
      if (response.statusCode != HttpStatus.ok ||
          response.headers.contentType?.mimeType !=
              'application/octet-stream' ||
          length < 1 ||
          length >
              ReadMoveChunkEngineRequest.chunkBytes *
                  ReadMoveChunkEngineRequest.maxChunks ||
          encoded == null ||
          encoded.length > 8192) {
        throw const FormatException('Archive download unavailable');
      }
      final manifest = CanonicalValue.parseWireJson(
        utf8.decode(base64Decode(encoded)),
      ) as CanonicalObject;
      final output = File(destination).openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          bytes += chunk.length;
          if (bytes > length) {
            throw const FormatException('Archive response bound');
          }
          output.add(chunk);
          await output.flush();
        }
      } finally {
        await output.close();
      }
      if (_closed || bytes != length) {
        throw const FormatException('Incomplete archive download');
      }
      _broken = false;
      return manifest;
    } on Object {
      _http.close(force: true);
      try {
        if (File(destination).existsSync()) File(destination).deleteSync();
      } on Object {
        // Preserve fixed diagnostics; the app also owns the staging directory.
      }
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      _busy = false;
    }
  }

  Future<CanonicalValue> stageImageFile({
    required String source,
    required Selector universe,
  }) => _uploadFile(
    source,
    '/engine/image-file',
    'x-ub-image',
    maxImageBytes,
    CanonicalObject([
      MapEntry('universe', universe.toWire()),
      MapEntry(
        'original_name',
        CanonicalString(File(source).uri.pathSegments.last),
      ),
    ]),
  );

  Future<CanonicalValue> reviewArchiveFile({
    required String source,
    required OperationId previewId,
    required String name,
    required ImportMode mode,
  }) => _uploadFile(
    source,
    '/engine/import-file',
    'x-ub-import',
    ReadMoveChunkEngineRequest.chunkBytes *
        ReadMoveChunkEngineRequest.maxChunks,
    CanonicalObject([
      MapEntry('preview_id', CanonicalString(previewId.value)),
      MapEntry('name', CanonicalString(name)),
      MapEntry('mode', CanonicalString(mode.name)),
    ]),
  );

  Future<CanonicalValue> _uploadFile(
    String source,
    String path,
    String header,
    int limit,
    CanonicalObject metadata,
  ) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_busy) throw const LocalEngineException(LocalEngineFailure.busy);
    if (_broken) {
      throw const LocalEngineException(LocalEngineFailure.reconnectRequired);
    }
    final String encoded;
    final int length;
    try {
      encoded = base64Encode(metadata.toBytes());
      if (FileSystemEntity.typeSync(source, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Selected regular file required');
      }
      length = File(source).lengthSync();
      if (length < 1 || length > limit || encoded.length > 8192) {
        throw const FormatException('Selected file exceeds input bound');
      }
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    _busy = true;
    _broken = true;
    final EngineResult result;
    try {
      result = await _sendFile(
        source,
        path,
        header,
        encoded,
        length,
      ).timeout(const Duration(minutes: 5));
    } on Object {
      _http.close(force: true);
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

  Future<EngineResult> _sendFile(
    String source,
    String path,
    String header,
    String metadata,
    int length,
  ) async {
    final request = await _http.postUrl(endpoint.resolve(path));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    request.headers.contentType = ContentType.binary;
    request.headers.set(header, metadata);
    request.contentLength = length;
    await request.addStream(File(source).openRead());
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const FormatException('Upload unavailable');
    }
    final output = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (output.length + chunk.length > maxFrameBytes) {
        throw const FormatException('Upload response bound');
      }
      output.add(chunk);
    }
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    return EngineResult.fromWire(
      CanonicalValue.parseWireJson(utf8.decode(output.takeBytes())),
    );
  }
}
