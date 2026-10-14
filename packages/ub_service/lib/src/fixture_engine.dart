import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_socket.dart';

import 'disposable_fixture.dart';

final class FixtureEngineServer {
  FixtureEngineServer._(this._listener, this._endpoint, this._staging);
  final ServerSocket _listener;
  final Directory _staging;
  final OwnedLocalSocketEndpoint _endpoint;
  final _fixture = DisposableFixture();
  final _clients = <Socket, Future<void>>{};
  final _done = Completer<void>();
  StreamSubscription<Socket>? _subscription;
  Future<void>? _closing;
  Future<void> get done => _done.future;

  static Future<FixtureEngineServer> start(String path) async {
    // Existing private parent only. Never create/repair an endpoint directory.
    final parent = File(path).absolute.parent;
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException(
        'Existing private fixture directory required',
      );
    }
    privateDirectory(parent.path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FormatException('Fixture endpoint occupied');
    }
    // Dart unlinks its bind pathname on close. Publish a second pathname so
    // automatic cleanup cannot remove a caller's replacement at the endpoint.
    final staging = parent.createTempSync('.fx-');
    privateDirectory(staging.path);
    ServerSocket listener;
    try {
      listener = await ServerSocket.bind(
        InternetAddress('${staging.path}/s', type: InternetAddressType.unix),
        0,
      );
    } on Object {
      staging.deleteSync();
      rethrow;
    }
    OwnedLocalSocketEndpoint? endpoint;
    try {
      protectLocalSocketEndpoint('${staging.path}/s');
      publishLocalSocketEndpoint('${staging.path}/s', path);
      endpoint = OwnedLocalSocketEndpoint.capture(path);
      final server = FixtureEngineServer._(listener, endpoint, staging);
      server._subscription = listener.listen(
        server._accept,
        onError: (Object _) => server.close().ignore(),
      );
      return server;
    } on Object {
      await listener.close();
      endpoint?.remove();
      staging.deleteSync();
      rethrow;
    }
  }

  void _accept(Socket socket) {
    if (_closing != null || _clients.length >= 16) {
      socket.destroy();
      return;
    }
    final task = _serve(socket);
    _clients[socket] = task;
    task.whenComplete(() => _clients.remove(socket)).ignore();
  }

  Future<void> _serve(Socket socket) async {
    StreamIterator<Uint8List>? frames;
    final active = <BigInt, Timer>{};
    var alive = true;
    Future<void> sending = Future.value();
    Future<void> send(BigInt id, ResponseResult result) {
      var reply = ServerMessage(id: id, result: result).toWire();
      if (reply.toBytes().length > maxFrameBytes) {
        reply = ServerMessage(
          id: id,
          result: const ResponseFailure(
            EvaluationLimitReachedError(
              message: 'response exceeds frame limit',
            ),
          ),
        ).toWire();
      }
      final bytes = encodeLengthPrefixedFrame(reply.toBytes());
      sending = sending
          .then((_) async {
            if (!alive) return;
            socket.add(bytes);
            await socket.flush().timeout(const Duration(seconds: 5));
          })
          .catchError((Object _) {
            alive = false;
            socket.destroy();
          });
      return sending;
    }

    try {
      validateLocalSocketPeer(socket);
      frames = StreamIterator(decodeLengthPrefixedFrames(socket));
      if (!await frames.moveNext().timeout(const Duration(seconds: 5))) return;
      final hello = Hello.decode(frames.current);
      if (hello.protocolVersion != protocolVersion || !hello.fixture) return;
      socket.add(
        encodeLengthPrefixedFrame(
          HelloReply(
            protocolVersion: protocolVersion,
            fixture: true,
            maxFrameBytes: BigInt.from(maxFrameBytes),
            maxInFlight: BigInt.from(16),
          ).toWire().toBytes(),
        ),
      );
      await socket.flush().timeout(const Duration(seconds: 5));
      final seen = <BigInt>{};
      while (alive &&
          _closing == null &&
          await frames.moveNext().timeout(const Duration(seconds: 60))) {
        final message = ClientMessage.decode(frames.current);
        if (message is ClientCancelMessage) {
          final pending = active[message.id];
          if (pending?.isActive ?? false) {
            active.remove(message.id)?.cancel();
          }
          continue;
        }
        if (seen.length >= 8192 || !seen.add(message.id)) break;
        final call = message as ClientRequestMessage;
        if (active.length >= 16) {
          send(
            call.id,
            const ResponseFailure(
              EvaluationLimitReachedError(message: 'too many requests'),
            ),
          );
          continue;
        }
        // Admission is a queued event: a preceding cancellation can remove it.
        // Once admitted, synchronous fixture mutations complete atomically.
        active[call.id] = Timer(Duration.zero, () {
          if (!alive || _closing != null) return;
          try {
            send(
              call.id,
              ResponseSuccess(_fixture.handle(call.id, call.request)),
            ).whenComplete(() => active.remove(call.id)).ignore();
          } on ProtocolError catch (error) {
            send(
              call.id,
              ResponseFailure(error),
            ).whenComplete(() => active.remove(call.id)).ignore();
          } on Object {
            alive = false;
            socket.destroy();
          }
        });
      }
    } on Object {
      // Invalid peers, framing or handshakes close without disclosing state.
    } finally {
      alive = false;
      for (final timer in active.values) {
        timer.cancel();
      }
      socket.destroy();
      try {
        await frames?.cancel();
      } on Object {
        /* closed transport */
      }
      await sending;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      await _subscription?.cancel();
      await _listener.close();
      for (final client in _clients.keys.toList()) {
        client.destroy();
      }
      await Future.wait(_clients.values.toList());
      _endpoint.remove();
    } finally {
      try {
        _staging.deleteSync();
      } finally {
        _done.complete();
      }
    }
  }
}
