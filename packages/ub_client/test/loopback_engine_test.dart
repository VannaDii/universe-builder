@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/local_http_endpoint.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('HTTP startup refuses unsafe discovery and releases bootstrap after an invalid helper', () async {
    final root = Directory('/tmp').createTempSync('ub-http-start-');
    final profile = ProfileId.generate();
    ProfileCredentialStore.write(
      root: root.path,
      profile: profile,
      credential: 'Disposable startup credential',
    );
    Future<LoopbackEngineClient> start() => LoopbackEngineClient.ensureRunning(
      root: root.path,
      profile: profile,
      helper: 'universe-engine',
      clientName: 'Startup client',
    );
    Matcher failure(LocalEngineFailure expected) => throwsA(
      isA<LocalEngineException>().having(
        (error) => error.failure,
        'failure',
        expected,
      ),
    );
    try {
      writeLocalHttpEndpoint(root.path, Uri.parse('http://foreign.example'));
      await expectLater(start(), failure(LocalEngineFailure.unsafeEndpoint));
      removeLocalHttpEndpoint(root.path);
      await expectLater(start(), failure(LocalEngineFailure.helperUnavailable));
      final lock = InstallationBootstrapLock.acquireExisting(root.path);
      lock.close();
      File('${root.path}/profiles/${profile.value}.sqlite').deleteSync();
      await expectLater(
        start(),
        failure(LocalEngineFailure.credentialUnavailable),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
  test(
    'HTTP interruption requires explicit reconnect and never replays a call',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      final profile = ProfileId.generate();
      final hello = EngineHello(
        protocolVersion: protocolVersion,
        profileId: profile,
        credential: const Credential('Disposable secret'),
        clientName: 'Disposable client',
      );
      var calls = 0;
      final subscription = server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'UB ${base64Encode(hello.toWire().toBytes())}',
        );
        await request.drain<void>();
        if (request.uri.path == '/engine/hello') {
          request.response.add(
            EngineWelcome(
              protocolVersion: protocolVersion,
              serviceInstance: 'disposable',
              principal: profile,
              author: true,
              maxFrameBytes: BigInt.from(maxFrameBytes),
              maxInFlight: BigInt.from(engineMaxInFlight),
            ).toWire().toBytes(),
          );
          await request.response.close();
        } else {
          calls++;
          (await request.response.detachSocket(writeHeaders: false)).destroy();
        }
      });
      LoopbackEngineClient? client;
      Matcher failure(LocalEngineFailure expected) => throwsA(
        isA<LocalEngineException>().having(
          (error) => error.failure,
          'failure',
          expected,
        ),
      );
      try {
        for (final uri in [
          Uri.parse('https://127.0.0.1:${server.port}'),
          Uri.parse('$endpoint?secret=private'),
          Uri.parse('http://localhost:${server.port}'),
        ]) {
          await expectLater(
            LoopbackEngineClient.connect(endpoint: uri, hello: hello),
            failure(LocalEngineFailure.unsafeEndpoint),
          );
        }
        client = await LoopbackEngineClient.connect(
          endpoint: endpoint,
          hello: hello,
        );
        expect(client.welcome.principal, profile);
        await expectLater(
          client.call(const StatusEngineRequest()),
          failure(LocalEngineFailure.interrupted),
        );
        await expectLater(
          client.call(const StatusEngineRequest()),
          failure(LocalEngineFailure.reconnectRequired),
        );
        expect(calls, 1);
      } finally {
        await client?.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
