import 'dart:async';
import 'dart:io';

import 'package:ub_store/local_http_endpoint.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/installation.dart'
    show OwnedFileLock, privateDirectory;

import 'configuration.dart';
import 'local_engine.dart';
import 'loopback_engine.dart';
import 'postgres_open.dart';
import 'postgres_runtime.dart';

/// Local PostgreSQL mode owns device endpoint discovery, not a SQLite canon.
/// Startup opens existing database authority; setup and transfer stay explicit.
final class LocalPostgresEngineServer {
  LocalPostgresEngineServer._(
    this.root,
    this._lock,
    this._store,
    this._runtime,
    this._http,
  );
  final String root;
  final OwnedFileLock _lock;
  final PostgresInstallationStore _store;
  final NativePostgresRuntime _runtime;
  final LoopbackEngineServer _http;
  late final Timer _idle;
  final _done = Completer<void>();
  Future<void>? _shutdown;
  Future<void> get done => _done.future;
  Uri get httpEndpoint => _http.endpoint;

  static Future<LocalPostgresEngineServer> start(
    String root,
    PostgresConfiguration configuration,
  ) async {
    OwnedFileLock? lock;
    PostgresInstallationStore? store;
    NativePostgresRuntime? runtime;
    LoopbackEngineServer? http;
    var published = false;
    String? directory;
    try {
      if (!Directory(root).existsSync()) {
        throw const FileSystemException('Local installation unavailable');
      }
      directory = privateDirectory(root);
      lock = OwnedFileLock.acquire('$directory/service.lock');
      store = await openPostgresInstallation(configuration);
      runtime = NativePostgresRuntime(store: store, profileRoot: directory);
      http = await LoopbackEngineServer.postgres(runtime);
      final server = LocalPostgresEngineServer._(
        directory,
        lock,
        store,
        runtime,
        http,
      );
      writeLocalHttpEndpoint(directory, http.endpoint);
      published = true;
      http.done.then((_) => server.close().ignore());
      server._idle = Timer.periodic(const Duration(seconds: 60), (_) {
        if (server._http.isIdle &&
            DateTime.now().difference(server._http.lastActive) >=
                const Duration(minutes: 15)) {
          server.close().ignore();
        }
      });
      return server;
    } on Object {
      try {
        try {
          await http?.close();
        } finally {
          try {
            await runtime?.close();
          } finally {
            await store?.close();
          }
        }
      } on Object {
        // Driver and credential diagnostics remain redacted during cleanup.
      } finally {
        try {
          try {
            if (published && directory != null) {
              removeLocalHttpEndpoint(directory);
            }
          } finally {
            lock?.close();
          }
        } on Object {
          // Cleanup failures cannot expose unredacted startup diagnostics.
        }
      }
      throw const LocalEngineServerException(
        LocalEngineServerFailure.unavailable,
      );
    }
  }

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _idle.cancel();
    try {
      try {
        await _http.close();
      } finally {
        try {
          await _runtime.close();
        } finally {
          try {
            await _store.close();
          } finally {
            try {
              removeLocalHttpEndpoint(root);
            } finally {
              _lock.close();
            }
          }
        }
      }
    } on Object {
      throw const LocalEngineServerException(
        LocalEngineServerFailure.shutdownFailed,
      );
    } finally {
      _done.complete();
    }
  }
}
