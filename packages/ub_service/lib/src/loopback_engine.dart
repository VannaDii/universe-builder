import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'postgres_runtime.dart';
import 'sqlite_runtime.dart';

typedef _HttpConnection = ({
  EngineWelcome welcome,
  Future<CanonicalValue> Function(EngineRequest) execute,
  void Function() close,
});

/// Transport ownership is separate from runtime/storage ownership. Closing the
/// listener drains admitted calls; the caller then closes its runtime/store.
/// Each HTTP request authenticates using the existing profile hello. There is
/// no cookie session, automatic request replay, or database access in this layer.
final class LoopbackEngineServer {
  LoopbackEngineServer._(this._server, this._connect);
  final HttpServer _server;
  final Future<_HttpConnection> Function(EngineHello) _connect;
  late final StreamSubscription<HttpRequest> _subscription;
  final _active = <Future<void>>{};
  final _done = Completer<void>();
  bool _stopping = false;
  Future<void>? _shutdown;
  DateTime _lastActive = DateTime.now();
  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');
  Future<void> get done => _done.future;
  bool get isIdle => _active.isEmpty;
  DateTime get lastActive => _lastActive;

  static Future<LoopbackEngineServer> sqlite(NativeSqliteRuntime runtime) =>
      _bind((hello) async {
        final connection = runtime.connect(hello);
        return (
          welcome: connection.welcome,
          execute: connection.execute,
          close: connection.close,
        );
      });

  static Future<LoopbackEngineServer> postgres(NativePostgresRuntime runtime) =>
      _bind((hello) async {
        final connection = await runtime.connect(hello);
        return (
          welcome: connection.welcome,
          execute: connection.execute,
          close: connection.close,
        );
      });

  static Future<LoopbackEngineServer> _bind(
    Future<_HttpConnection> Function(EngineHello) connect,
  ) async {
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener.idleTimeout = const Duration(seconds: 60);
    final server = LoopbackEngineServer._(listener, connect);
    server._subscription = listener.listen(server._accept);
    return server;
  }

  void _accept(HttpRequest request) {
    _lastActive = DateTime.now();
    if (_stopping || _active.length >= 32) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.close().ignore();
      return;
    }
    final task = _serve(request);
    _active.add(task);
    task.whenComplete(() {
      _active.remove(task);
      _lastActive = DateTime.now();
    }).ignore();
  }

  Future<void> _serve(HttpRequest request) async {
    _HttpConnection? connection;
    var shutdown = false;
    try {
      final response = request.response;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final origin = request.headers.value('origin');
      if (request.headers.value(HttpHeaders.hostHeader) != endpoint.authority ||
          origin != null && origin != endpoint.origin) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.method != 'POST' ||
          request.uri.hasQuery ||
          !{'/engine/hello', '/engine/call'}.contains(request.uri.path)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (authorization == null ||
          !authorization.startsWith('UB ') ||
          authorization.length > 8192) {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      try {
        connection = await _connect(
          EngineHello.decode(base64Decode(authorization.substring(3))),
        );
      } on Object {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      final input = BytesBuilder(copy: false);
      await for (final bytes in request.timeout(const Duration(seconds: 5))) {
        if (input.length + bytes.length > maxFrameBytes) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        input.add(bytes);
      }
      CanonicalValue value;
      if (request.uri.path == '/engine/hello') {
        if (input.length != 0) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        value = connection.welcome.toWire();
      } else {
        final call = EngineCall.decode(input.takeBytes());
        EngineResult result;
        try {
          var body = await connection.execute(call.request);
          if (body is CanonicalObject &&
              body.fields.any((field) => field.key == 'contract_version')) {
            body = CanonicalObject([
              for (final field in body.fields)
                if (field.key != 'request_id') field,
              MapEntry('request_id', CanonicalNumber('${call.id}')),
            ]);
          }
          result = EngineSuccess(body);
        } on ProtocolError catch (error) {
          result = EngineFailure(error);
        } on Object {
          result = const EngineFailure(
            PolicyDeniedError(
              message: 'operation unavailable; verify current profile, grant, or package state',
            ),
          );
        }
        shutdown =
            call.request is ShutdownEngineRequest && result is EngineSuccess;
        value = EngineReply(id: call.id, result: result).toWire();
        if (value.toBytes().length > maxFrameBytes) {
          value = EngineReply(
            id: call.id,
            result: const EngineFailure(
              EvaluationLimitReachedError(message: 'response size limit'),
            ),
          ).toWire();
        }
      }
      response.headers.contentType = ContentType.json;
      response.add(value.toBytes());
    } on Object {
      // Parser/transport exceptions can contain authored text or credentials.
      request.response.statusCode = HttpStatus.badRequest;
    } finally {
      connection?.close();
      try {
        await request.response.close();
      } on Object {
        /* disconnected client */
      }
      if (shutdown) close().ignore();
    }
  }

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _stopping = true;
    try {
      await _subscription.cancel();
      await Future.wait(_active.toList());
      await _server.close(force: true);
    } finally {
      _done.complete();
    }
  }
}
