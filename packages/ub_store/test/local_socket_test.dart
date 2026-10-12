@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:ub_store/local_socket.dart';
import 'package:ub_store/src/native_ownership.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late String path;
  late List<Socket> sockets;
  late List<ServerSocket> servers;
  late List<StreamSubscription<Socket>> subscriptions;
  setUp(() {
    root = Directory('/tmp').createTempSync('ub-socket-');
    privateDirectory(root.path);
    path = '${root.path}/engine.sock';
    sockets = [];
    servers = [];
    subscriptions = [];
  });
  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final server in servers) {
      await server.close();
    }
    root.deleteSync(recursive: true);
  });
  Future<(Socket, Socket)> connected({bool tcp = false}) async {
    final address = tcp
        ? InternetAddress.loopbackIPv4
        : InternetAddress(path, type: InternetAddressType.unix);
    final server = await ServerSocket.bind(address, 0);
    servers.add(server);
    final accepted = Completer<Socket>();
    subscriptions.add(
      server.listen((socket) {
        if (!accepted.isCompleted) {
          accepted.complete(socket);
        } else {
          socket.destroy();
        }
      }),
    );
    final client = await Socket.connect(address, server.port);
    sockets.add(client);
    final peer = await accepted.future;
    sockets.add(peer);
    return (client, peer);
  }

  test('private Unix endpoint checks real OS peer identity on both sides before transmitting credentials', () async {
    final (client, server) = await connected();
    protectLocalSocketEndpoint(path);
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    checkLocalSocketEndpoint(path);
    validateLocalSocketPeer(client);
    validateLocalSocketPeer(server);
  });

  test(
    'TCP connections cannot substitute for the private local peer boundary',
    () async {
      final (client, server) = await connected(tcp: true);
      expect(() => validateLocalSocketPeer(client), throwsFormatException);
      expect(() => validateLocalSocketPeer(server), throwsFormatException);
    },
  );

  test('endpoint helpers never follow links or alter regular files', () {
    final retained = '${root.path}/retained';
    File(retained).writeAsStringSync('Retain authored data');
    final before = File(retained).statSync().mode;
    Link(path).createSync(retained);
    for (final action in [
      checkLocalSocketEndpoint,
      protectLocalSocketEndpoint,
      removeLocalSocketEndpoint,
    ]) {
      expect(() => action(path), throwsA(isA<FileSystemException>()));
      expect(File(retained).readAsStringSync(), 'Retain authored data');
      expect(File(retained).statSync().mode, before);
      expect(Link(path).targetSync(), retained);
    }
    Link(path).deleteSync();
    File(path).writeAsStringSync('Retained regular endpoint');
    for (final action in [
      checkLocalSocketEndpoint,
      protectLocalSocketEndpoint,
      removeLocalSocketEndpoint,
    ]) {
      expect(() => action(path), throwsA(isA<FileSystemException>()));
      expect(File(path).readAsStringSync(), 'Retained regular endpoint');
    }
  });

  test('endpoint checks refuse permissive socket paths until the new owned socket is protected', () async {
    await connected();
    expect(Process.runSync('chmod', ['666', path]).exitCode, 0);
    expect(
      () => checkLocalSocketEndpoint(path),
      throwsA(isA<FileSystemException>()),
    );
    protectLocalSocketEndpoint(path);
    checkLocalSocketEndpoint(path);
    final hard = '${root.path}/hard';
    expect(Process.runSync('ln', [path, hard]).exitCode, 0);
    expect(
      () => checkLocalSocketEndpoint(path),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => removeLocalSocketEndpoint(path),
      throwsA(isA<FileSystemException>()),
    );
    File(hard).deleteSync();
    checkLocalSocketEndpoint(path);
  });

  test('stale cleanup removes only an owned socket after service ownership is held', () async {
    // Abrupt process termination leaves a real stale endpoint; ordinary Dart
    // listener shutdown removes its own endpoint automatically.
    final fixture = File('${root.path}/bind.dart')
      ..writeAsStringSync('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final server = await ServerSocket.bind(InternetAddress(args.single, type: InternetAddressType.unix), 0);
  stdout.writeln('bound');
  await stdin.drain<void>();
  await server.close();
}
''');
    final child = await Process.start(Platform.resolvedExecutable, [
      fixture.path,
      path,
    ]);
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10)),
        'bound',
      );
      expect(child.kill(ProcessSignal.sigkill), isTrue);
      await child.exitCode.timeout(const Duration(seconds: 10));
    } finally {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    protectLocalSocketEndpoint(path);
    final lock = OwnedFileLock.acquire('${root.path}/service.lock');
    try {
      removeLocalSocketEndpoint(path);
    } finally {
      lock.close();
    }
    expect(
      FileSystemEntity.typeSync(path, followLinks: false),
      FileSystemEntityType.notFound,
    );
    expect(File('${root.path}/service.lock').existsSync(), isTrue);
  });

  test('missing directories and malformed peer buffers fail closed', () {
    expect(
      () => checkLocalSocketEndpoint('${root.path}/absent/engine.sock'),
      throwsFormatException,
    );
    expect(Directory('${root.path}/absent').existsSync(), isFalse);
    expect(() => checkLocalSocketEndpoint('\u0000'), throwsFormatException);
    using((arena) {
      final level = arena<Int32>(),
          option = arena<Int32>(),
          size = arena<Int32>();
      expect(nativePeerOptions(level, option, size), 0);
      expect(size.value, inInclusiveRange(1, 256));
      final bytes = arena<Uint8>(size.value + 1);
      expect(nativePeerMatches(bytes, 0), isNot(0));
      expect(nativePeerMatches(bytes, size.value + 1), isNot(0));
    });
  });
}
