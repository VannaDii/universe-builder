import 'dart:async';
import 'dart:isolate';

import 'local_engine.dart';

enum EmbeddedEngineFailure { unavailable, workerFailed }

final class EmbeddedEngineException implements Exception {
  const EmbeddedEngineException(this.failure);
  final EmbeddedEngineFailure failure;
  @override
  String toString() => 'EmbeddedEngineException(${failure.name})';
}

/// Runs the existing service in an application-owned worker. Storage, validation
/// and transport work remain off the rendering isolate. Opening never initializes
/// authority, converts data, or selects a different backend.
final class EmbeddedSqliteEngine {
  EmbeddedSqliteEngine._(this.endpoint, this._stop, this._exit, this._failure);
  final Uri endpoint;
  final SendPort _stop;
  final Future<void> _exit;
  final _WorkerFailure _failure;
  Future<void>? _closing;

  /// Worker termination is a lifecycle notification, not proof that an operation
  /// completed. Recover uncertain requests through the normal service contract.
  Future<void> get done => _exit;
  bool get isClosed => _failure.exited;
  EmbeddedEngineFailure? get failure => _failure.value;

  static Future<EmbeddedSqliteEngine> start(String root) async {
    final events = ReceivePort();
    final ready = Completer<(Uri, SendPort)?>();
    final exit = Completer<void>();
    final failure = _WorkerFailure();
    events.listen((Object? message) {
      if (message == null) {
        failure.exited = true;
        if (!ready.isCompleted) {
          ready.complete(null);
        }
        exit.complete();
        events.close();
      } else if (message case (
        'ready',
        final String endpoint,
        final SendPort stop,
      )) {
        if (!ready.isCompleted) ready.complete((Uri.parse(endpoint), stop));
      } else if (message == 'unavailable') {
        failure.value = EmbeddedEngineFailure.unavailable;
        if (!ready.isCompleted) {
          ready.complete(null);
        }
      } else {
        // Isolate error messages may contain paths, credentials or authored text.
        // Never retain or forward their contents to application diagnostics.
        failure.value = EmbeddedEngineFailure.workerFailed;
        if (!ready.isCompleted) {
          ready.complete(null);
        }
      }
    });
    try {
      await Isolate.spawn(
        _runEmbedded,
        (root, events.sendPort),
        onExit: events.sendPort,
        onError: events.sendPort,
        errorsAreFatal: true,
        debugName: 'Universe Builder local service',
      );
    } on Object {
      events.close();
      throw const EmbeddedEngineException(EmbeddedEngineFailure.unavailable);
    }
    final result = await ready.future;
    if (result == null) {
      await exit.future;
      throw EmbeddedEngineException(
        failure.value ?? EmbeddedEngineFailure.unavailable,
      );
    }
    return EmbeddedSqliteEngine._(result.$1, result.$2, exit.future, failure);
  }

  /// Idempotent graceful shutdown; does not delete author data or credentials.
  Future<void> close() => _closing ??= () async {
    if (!isClosed) _stop.send('stop');
    await _exit;
    if (failure != null) throw EmbeddedEngineException(failure!);
  }();
}

final class _WorkerFailure {
  bool exited = false;
  EmbeddedEngineFailure? value;
}

Future<void> _runEmbedded((String, SendPort) input) async {
  final (root, events) = input;
  final stop = ReceivePort();
  LocalSqliteEngineServer? server;
  try {
    server = await LocalSqliteEngineServer.start(
      root,
      compatibilitySocket: false,
      shutdownWhenIdle: false,
    );
    events.send(('ready', server.httpEndpoint.toString(), stop.sendPort));
    // A graceful close drains admitted work. The app owns this worker until
    // close; desktop idle shutdown must not invalidate its retained connection.
    await Future.any([stop.first, server.done]);
    await server.close();
  } on Object {
    events.send('unavailable');
    try {
      await server?.close();
    } on Object {
      /* Fixed diagnostics only. */
    }
  } finally {
    stop.close();
  }
}
