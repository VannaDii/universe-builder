@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/local_socket.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory root;
  late ProfileId profile;
  late ServerSocket server;
  late StreamSubscription<Socket> listener;
  late Completer<Socket> accepted;
  late List<Socket> sockets;
  late List<LocalEngineClient> clients;
  const secret = 'Disposable credential café 世界';

  setUp(() async {
    root = Directory('/tmp').createTempSync('ub-client-');
    profile = ProfileId.generate();
    ProfileCredentialStore.write(
      root: root.path,
      profile: profile,
      credential: secret,
    );
    sockets = [];
    clients = [];
    accepted = Completer<Socket>();
    server = await ServerSocket.bind(
      InternetAddress(
        '${root.path}/engine.sock',
        type: InternetAddressType.unix,
      ),
      0,
    );
    listener = server.listen((socket) {
      sockets.add(socket);
      if (!accepted.isCompleted) accepted.complete(socket);
    });
    protectLocalSocketEndpoint('${root.path}/engine.sock');
  });
  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await listener.cancel();
    await server.close();
    root.deleteSync(recursive: true);
  });
  Matcher failure(LocalEngineFailure value) => throwsA(
    isA<LocalEngineException>().having((e) => e.failure, 'failure', value),
  );
  EngineWelcome welcome({
    String? version,
    ProfileId? principal,
    int? frameSize,
    int? inFlight,
  }) => EngineWelcome(
    protocolVersion: version ?? protocolVersion,
    serviceInstance: 'disposable-boot-instance',
    principal: principal ?? profile,
    author: true,
    maxFrameBytes: BigInt.from(frameSize ?? maxFrameBytes),
    maxInFlight: BigInt.from(inFlight ?? engineMaxInFlight),
  );
  Future<LocalEngineClient> connect({String name = 'client test'}) async {
    final client = await LocalEngineClient.connect(
      root: root.path,
      profile: profile,
      clientName: name,
    );
    clients.add(client);
    return client;
  }

  Future<(Socket, StreamIterator<Uint8List>)> handshake(
    EngineWelcome response,
  ) async {
    final socket = await accepted.future;
    final frames = StreamIterator(decodeLengthPrefixedFrames(socket));
    expect(await frames.moveNext(), isTrue);
    final hello = EngineHello.decode(frames.current);
    expect(hello.profileId, profile);
    expect(hello.credential.expose(), secret);
    expect(hello.protocolVersion, protocolVersion);
    socket.add(encodeLengthPrefixedFrame(response.toWire().toBytes()));
    await socket.flush();
    return (socket, frames);
  }

  void reply(Socket socket, BigInt id, EngineResult result) => socket.add(
    encodeLengthPrefixedFrame(
      EngineReply(id: id, result: result).toWire().toBytes(),
    ),
  );

  test('authenticates and correlates sequential calls; typed errors keep connection usable', () async {
    final peerTask = () async {
      final (socket, frames) = await handshake(welcome());
      for (var i = 1; i <= 3; i++) {
        expect(await frames.moveNext(), isTrue);
        final call = EngineCall.decode(frames.current);
        expect(call.id, BigInt.from(i));
        expect(call.request, isA<StatusEngineRequest>());
        reply(
          socket,
          call.id,
          i == 2
              ? const EngineFailure(
                  ApprovalRequiredError(message: 'Review required'),
                )
              : EngineSuccess(CanonicalString('result $i')),
        );
        await socket.flush();
      }
      await frames.cancel();
    }();
    final client = await connect();
    expect(client.welcome.author, isTrue);
    expect(
      (await client.call(const StatusEngineRequest())).toText(),
      '"result 1"',
    );
    await expectLater(
      client.call(const StatusEngineRequest()),
      throwsA(isA<ApprovalRequiredError>()),
    );
    expect(
      (await client.call(const StatusEngineRequest())).toText(),
      '"result 3"',
    );
    await peerTask;
  });

  for (final response in [
    'version',
    'principal',
    'frame',
    'inflight',
    'malformed',
  ]) {
    test('rejects incompatible welcome: $response', () async {
      final peerTask = () async {
        if (response == 'malformed') {
          final socket = await accepted.future;
          final frames = StreamIterator(decodeLengthPrefixedFrames(socket));
          expect(await frames.moveNext(), isTrue);
          socket.add(encodeLengthPrefixedFrame(Uint8List.fromList([255])));
          await socket.flush();
          await frames.cancel();
        } else {
          final (_, frames) = await handshake(
            welcome(
              version: response == 'version' ? 'wrong' : null,
              principal: response == 'principal' ? ProfileId.generate() : null,
              frameSize: response == 'frame' ? 1 : null,
              inFlight: response == 'inflight' ? 16 : null,
            ),
          );
          await frames.cancel();
        }
      }();
      await expectLater(connect(), failure(LocalEngineFailure.handshakeFailed));
      await peerTask;
    });
  }

  for (final mode in ['drop', 'correlation', 'malformed']) {
    test(
      'interrupted $mode requires reconnect and never replays a request',
      () async {
        final observed = Completer<void>();
        final peerTask = () async {
          final (socket, frames) = await handshake(welcome());
          expect(await frames.moveNext(), isTrue);
          final call = EngineCall.decode(frames.current);
          observed.complete();
          if (mode == 'drop') {
            socket.destroy();
          }
          if (mode == 'correlation') {
            reply(
              socket,
              call.id + BigInt.one,
              EngineSuccess(CanonicalString('wrong')),
            );
            await socket.flush();
          }
          if (mode == 'malformed') {
            socket.add(encodeLengthPrefixedFrame(Uint8List.fromList([255])));
            await socket.flush();
          }
          expect(await frames.moveNext(), isFalse);
          await frames.cancel();
        }();
        final client = await connect();
        await expectLater(
          client.call(const StatusEngineRequest()),
          failure(LocalEngineFailure.interrupted),
        );
        await observed.future;
        await expectLater(
          client.call(const StatusEngineRequest()),
          failure(LocalEngineFailure.reconnectRequired),
        );
        await peerTask;
      },
    );
  }

  test('concurrent call is refused without disrupting admitted call; close is final', () async {
    final received = Completer<void>(), release = Completer<void>();
    final peerTask = () async {
      final (socket, frames) = await handshake(welcome());
      expect(await frames.moveNext(), isTrue);
      final call = EngineCall.decode(frames.current);
      received.complete();
      await release.future;
      reply(socket, call.id, EngineSuccess(CanonicalString('done')));
      await socket.flush();
      await frames.cancel();
    }();
    final client = await connect();
    final pending = client.call(const StatusEngineRequest());
    await received.future;
    await expectLater(
      client.call(const StatusEngineRequest()),
      failure(LocalEngineFailure.busy),
    );
    release.complete();
    expect((await pending).toText(), '"done"');
    await peerTask;
    await client.close();
    await client.close();
    await expectLater(
      client.call(const StatusEngineRequest()),
      failure(LocalEngineFailure.closed),
    );
  });

  test(
    'unsafe endpoint and missing credential fail before transmitting hello',
    () async {
      expect(
        Process.runSync('chmod', ['666', '${root.path}/engine.sock']).exitCode,
        0,
      );
      await expectLater(connect(), failure(LocalEngineFailure.unsafeEndpoint));
      expect(accepted.isCompleted, isFalse);
      protectLocalSocketEndpoint('${root.path}/engine.sock');
      File('${root.path}/profiles/${profile.value}.sqlite').deleteSync();
      await expectLater(
        connect(),
        failure(LocalEngineFailure.credentialUnavailable),
      );
      final socket = await accepted.future;
      expect(await socket.toList(), isEmpty);
    },
  );

  test(
    'client name uses the UTF-8 byte limit before sending a credential',
    () async {
      await expectLater(
        connect(name: List.filled(65, 'é').join()),
        failure(LocalEngineFailure.handshakeFailed),
      );
      final socket = await accepted.future;
      expect(await socket.toList(), isEmpty);
    },
  );

  test('missing installation is unavailable and is never created', () async {
    final absent = '${root.path}/absent';
    await expectLater(
      LocalEngineClient.connect(
        root: absent,
        profile: profile,
        clientName: 'test',
      ),
      failure(LocalEngineFailure.unavailable),
    );
    expect(Directory(absent).existsSync(), isFalse);
  });

  test('request deadline interrupts a silent engine without replay', () async {
    final peerTask = () async {
      final (_, frames) = await handshake(welcome());
      expect(await frames.moveNext(), isTrue);
      expect(EngineCall.decode(frames.current).id, BigInt.one);
      expect(await frames.moveNext(), isFalse);
      await frames.cancel();
    }();
    final client = await connect();
    await expectLater(
      client.call(const StatusEngineRequest()),
      failure(LocalEngineFailure.interrupted),
    );
    await expectLater(
      client.call(const StatusEngineRequest()),
      failure(LocalEngineFailure.reconnectRequired),
    );
    await peerTask;
  });
}
