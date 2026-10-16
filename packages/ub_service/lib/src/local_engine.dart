import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_socket.dart';
import 'package:ub_store/local_http_endpoint.dart';

import 'hosted_providers.dart';
import 'installation_authority.dart';
import 'sqlite_runtime.dart';
import 'loopback_engine.dart';

enum LocalEngineServerFailure { unavailable, shutdownFailed }

/// Fixed diagnostics never retain driver, socket, credential or authored content.
final class LocalEngineServerException implements Exception {
  const LocalEngineServerException(this.failure);
  final LocalEngineServerFailure failure;
  @override
  String toString() => 'LocalEngineServerException(${failure.name})';
}

/// Owns the installation lock, runtime and endpoint for its entire lifetime.
/// Opening is explicit: it never initializes profiles or converts old data.
final class LocalSqliteEngineServer {
  LocalSqliteEngineServer._(
    this._store,
    this._runtime,
    this._listener,
    this._http,
    this._https,
  );
  final SqliteInstallationStore _store;
  final NativeSqliteRuntime _runtime;
  final ServerSocket? _listener;
  final LoopbackEngineServer _http;
  final LoopbackEngineServer? _https;
  StreamSubscription<Socket>? _subscription;
  late final Timer _idle;
  final _clients = <Socket, Future<void>>{};
  final _done = Completer<void>();
  DateTime _lastActive = DateTime.now();
  bool _stopping = false;
  Future<void>? _shutdown;

  Future<void> get done => _done.future;
  Uri get httpEndpoint => _http.endpoint;
  Uri? get httpsEndpoint => _https?.endpoint;

  static Future<LocalSqliteEngineServer> start(
    String root, {
    bool compatibilitySocket = true,
    DateTime Function()? httpNow,
    String? webAssets,
    Uri? httpsOrigin,
    SecurityContext? tlsContext,
    InternetAddress? bindAddress,
    HostedAccountAccess? hostedAccount,
  }) async {
    SqliteInstallationStore? store;
    ServerSocket? listener;
    NativeSqliteRuntime? runtime;
    LoopbackEngineServer? http;
    LoopbackEngineServer? https;
    var publishedHttp = false;
    try {
      store = SqliteInstallationStore.openExisting(root);
      if (compatibilitySocket) {
        final endpoint = '${store.root}/engine.sock';
        if (FileSystemEntity.typeSync(endpoint, followLinks: false) !=
            FileSystemEntityType.notFound) {
          // openExisting owns service.lock before any stale endpoint is removed.
          removeLocalSocketEndpoint(endpoint);
        }
        listener = await ServerSocket.bind(
          InternetAddress(endpoint, type: InternetAddressType.unix),
          0,
        );
        protectLocalSocketEndpoint(endpoint);
      }
      runtime = NativeSqliteRuntime(authority: InstallationAuthority(store));
      http = await LoopbackEngineServer.sqlite(
        runtime,
        now: httpNow,
        webAssets: webAssets,
        hostedAccount: hostedAccount,
      );
      if (httpsOrigin != null || tlsContext != null || bindAddress != null) {
        https = await LoopbackEngineServer.sqlite(
          runtime,
          now: httpNow,
          webAssets: webAssets,
          hostedAccount: hostedAccount,
          httpsOrigin: httpsOrigin,
          tlsContext: tlsContext,
          bindAddress: bindAddress,
        );
      }
      final server = LocalSqliteEngineServer._(
        store,
        runtime,
        listener,
        http,
        https,
      );
      writeLocalHttpEndpoint(store.root, http.endpoint);
      publishedHttp = true;
      http.done.then((_) => server.close().ignore());
      https?.done.then((_) => server.close().ignore());
      server._subscription = listener?.listen(
        server._accept,
        onError: (Object _) => server.close().ignore(),
      );
      server._idle = Timer.periodic(const Duration(seconds: 60), (_) {
        if (server._https == null &&
            server._clients.isEmpty &&
            server._http.isIdle &&
            DateTime.now().difference(server._http.lastActive) >=
                const Duration(minutes: 15) &&
            DateTime.now().difference(server._lastActive) >=
                const Duration(minutes: 15)) {
          server.close().ignore();
        }
      });
      return server;
    } on Object {
      try {
        try {
          await listener?.close();
        } finally {
          try {
            await https?.close();
          } finally {
            try {
              await http?.close();
            } finally {
              await runtime?.close();
            }
          }
        }
      } on Object {
        // Startup diagnostics remain redacted even if cleanup also fails.
      } finally {
        try {
          if (publishedHttp && store != null) {
            removeLocalHttpEndpoint(store.root);
          }
          store?.close();
        } on Object {
          // Never retain a raw storage cleanup exception.
        }
      }
      throw const LocalEngineServerException(
        LocalEngineServerFailure.unavailable,
      );
    }
  }

  void _accept(Socket socket) {
    _lastActive = DateTime.now();
    if (_stopping || _clients.length >= 32) {
      socket.destroy();
      return;
    }
    final task = _serve(socket);
    _clients[socket] = task;
    task.whenComplete(() {
      _clients.remove(socket);
      _lastActive = DateTime.now();
    }).ignore();
  }

  Future<void> _serve(Socket socket) async {
    StreamIterator<Uint8List>? frames;
    NativeSqliteConnection? connection;
    try {
      validateLocalSocketPeer(socket);
      frames = StreamIterator(decodeLengthPrefixedFrames(socket));
      if (!await frames.moveNext().timeout(const Duration(seconds: 5))) return;
      connection = _runtime.connect(EngineHello.decode(frames.current));
      await _send(socket, connection.welcome.toWire());
      final seen = <BigInt>{};
      while (!_stopping) {
        if (!await frames.moveNext().timeout(const Duration(seconds: 60))) {
          break;
        }
        if (_stopping) break;
        final call = EngineCall.decode(frames.current);
        if (seen.length >= 8192 || !seen.add(call.id)) break;
        EngineResult result;
        try {
          var value = await connection.execute(call.request);
          // Public envelopes carry the transport correlation, preserving their
          // exact other fields and the maintained engine response convention.
          if (value is CanonicalObject &&
              value.fields.any((f) => f.key == 'contract_version')) {
            value = CanonicalObject([
              for (final field in value.fields)
                if (field.key != 'request_id') field,
              MapEntry('request_id', CanonicalNumber(call.id.toString())),
            ]);
          }
          result = EngineSuccess(value);
        } on ProtocolError catch (error) {
          result = EngineFailure(error);
        } on Object {
          result = const EngineFailure(
            PolicyDeniedError(
              message: 'operation unavailable; verify current profile, grant, or package state',
            ),
          );
        }
        var reply = EngineReply(id: call.id, result: result).toWire();
        if (reply.toBytes().length > maxFrameBytes) {
          reply = EngineReply(
            id: call.id,
            result: const EngineFailure(
              EvaluationLimitReachedError(message: 'response size limit'),
            ),
          ).toWire();
        }
        await _send(socket, reply);
        if (call.request is ShutdownEngineRequest && result is EngineSuccess) {
          close().ignore();
          break;
        }
      }
    } on Object {
      // Invalid/authentication-failed transports close without disclosing state.
      // Admitted execution above is awaited even when its client disconnects.
    } finally {
      connection?.close();
      socket.destroy();
      try {
        await frames?.cancel();
      } on Object {
        // Never expose untrusted parser/socket errors during cleanup.
      }
    }
  }

  static Future<void> _send(Socket socket, CanonicalValue value) async {
    socket.add(encodeLengthPrefixedFrame(value.toBytes()));
    await socket.flush().timeout(const Duration(seconds: 5));
  }

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _stopping = true;
    _idle.cancel();
    try {
      try {
        await _subscription?.cancel();
        await _listener?.close();
      } finally {
        for (final socket in _clients.keys.toList()) {
          socket.destroy();
        }
        try {
          await Future.wait(_clients.values.toList());
        } finally {
          try {
            try {
              try {
                await _https?.close();
              } finally {
                await _http.close();
              }
            } finally {
              await _runtime.close();
            }
          } finally {
            try {
              try {
                removeLocalHttpEndpoint(_store.root);
              } finally {
                _store.close();
              }
            } finally {
              _done.complete();
            }
          }
        }
      }
    } on Object {
      throw const LocalEngineServerException(
        LocalEngineServerFailure.shutdownFailed,
      );
    }
  }
}
