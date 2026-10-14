@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/loopback_engine.dart';
import 'package:ub_service/sqlite_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import 'fixtures/tls_fixture.dart';

void main() {
  test('HTTPS uses verified TLS and existing profile rights, with secure origin-bound browser exchange', () async {
    final temporary = Directory.systemTemp.createTempSync('ub-https-test-');
    final fixture = await generateTlsFixture(temporary);
    final cert = fixture.certificate, key = fixture.privateKey, ca = fixture.ca;
    final root = '${temporary.path}/installation';
    final store = SqliteInstallationStore.create(root);
    final authority = InstallationAuthority(store);
    final owner = authority.initializeAuthor();
    EngineHello hello(ProfileId profile) => EngineHello(
      protocolVersion: protocolVersion,
      profileId: profile,
      credential: Credential(
        ProfileCredentialStore.read(root: root, profile: profile),
      ),
      clientName: 'Disposable HTTPS client',
    );
    final writer = authority.enroll(authority.authenticateHello(hello(owner)));
    final runtime = NativeSqliteRuntime(authority: authority);
    final tls = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    final trust = SecurityContext()..setTrustedCertificates(ca);
    LoopbackEngineServer? server;
    final clients = <LoopbackEngineClient>[];
    final http = HttpClient(context: trust);
    try {
      await expectLater(
        LoopbackEngineServer.sqlite(
          runtime,
          httpsOrigin: Uri.parse('http://localhost:0'),
          tlsContext: tls,
          bindAddress: InternetAddress.loopbackIPv4,
        ),
        throwsFormatException,
      );
      server = await LoopbackEngineServer.sqlite(
        runtime,
        httpsOrigin: Uri.parse('https://localhost:0'),
        tlsContext: tls,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      final endpoint = server.endpoint;
      expect(endpoint.scheme, 'https');
      final probe = await http.postUrl(endpoint.resolve('/engine/hello'));
      final probeResponse = await probe.close();
      expect(probeResponse.statusCode, HttpStatus.unauthorized);
      await probeResponse.drain<void>();
      await expectLater(
        LoopbackEngineClient.connectHttps(
          endpoint: endpoint,
          hello: hello(owner),
        ),
        throwsA(isA<LocalEngineException>()),
      );
      await expectLater(
        LoopbackEngineClient.connectHttps(
          endpoint: endpoint.replace(host: '127.0.0.1'),
          hello: hello(owner),
          context: trust,
        ),
        throwsA(isA<LocalEngineException>()),
      );
      for (final unsafe in [
        endpoint.replace(scheme: 'http'),
        endpoint.replace(userInfo: 'user:secret'),
        endpoint.replace(path: '/other'),
        endpoint.replace(query: 'secret=value'),
      ]) {
        expect(
          () => LoopbackEngineClient.connectHttps(
            endpoint: unsafe,
            hello: hello(owner),
            context: trust,
          ),
          throwsA(isA<LocalEngineException>()),
        );
      }
      final native = await LoopbackEngineClient.connectHttps(
        endpoint: endpoint,
        hello: hello(owner),
        context: trust,
      );
      clients.add(native);
      final created = await native.call(
        const CreateUniverseEngineRequest(
          name: 'Hosted campaign',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      expect(
        wireString(
          Map.fromEntries((created as CanonicalObject).fields)['name']!,
        ),
        'Hosted campaign',
      );
      final contributor = await LoopbackEngineClient.connectHttps(
        endpoint: endpoint,
        hello: hello(writer),
        context: trust,
      );
      clients.add(contributor);
      final uploadDenied = await LoopbackEngineClient.connectHttps(
        endpoint: endpoint,
        hello: hello(writer),
        context: trust,
      );
      clients.add(uploadDenied);
      final deniedFile = File('${temporary.path}/denied.png')
        ..writeAsBytesSync([1]);
      await expectLater(
        uploadDenied.stageImageFile(
          source: deniedFile.path,
          universe: const Selector('Hosted campaign'),
        ),
        throwsA(isA<LocalEngineException>()),
      );
      final library = await contributor.call(const StatusEngineRequest());
      expect(
        (Map.fromEntries((library as CanonicalObject).fields)['universes']
                as CanonicalArray)
            .items,
        isEmpty,
      );
      await expectLater(
        contributor.call(
          const CreateUniverseEngineRequest(
            name: 'Unapproved',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
      authority.revoke(authority.authenticateHello(hello(owner)), writer);
      await expectLater(
        contributor.call(const StatusEngineRequest()),
        throwsA(isA<LocalEngineException>()),
      );
      final grant = WireFields(await native.createBrowserSession(), {
        'enrollment_token',
        'expires_at',
      });
      final exchange = await http.postUrl(
        endpoint.resolve('/engine/browser/exchange'),
      );
      exchange.headers.set('origin', endpoint.origin);
      exchange.headers.contentType = ContentType.json;
      exchange.write(
        CanonicalObject([
          MapEntry('token', CanonicalString(grant.string('enrollment_token'))),
        ]).toText(),
      );
      final response = await exchange.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.cookies.single.secure, isTrue);
      expect(response.cookies.single.httpOnly, isTrue);
      await response.drain<void>();
      final foreign = await http.postUrl(endpoint.resolve('/engine/hello'));
      foreign.headers.set('origin', 'https://other.example');
      final refused = await foreign.close();
      expect(refused.statusCode, HttpStatus.forbidden);
      await refused.drain<void>();
      final sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirect = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        tls,
      );
      var leakedRequests = 0;
      sink.listen((request) {
        leakedRequests++;
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      });
      redirect.listen((request) {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${sink.port}/engine/hello',
        );
        request.response.close();
      });
      try {
        await expectLater(
          LoopbackEngineClient.connectHttps(
            endpoint: Uri.parse('https://localhost:${redirect.port}'),
            hello: hello(owner),
            context: trust,
          ),
          throwsA(isA<LocalEngineException>()),
        );
        expect(leakedRequests, 0);
      } finally {
        await redirect.close(force: true);
        await sink.close(force: true);
      }
    } finally {
      http.close(force: true);
      for (final client in clients) {
        await client.close();
      }
      await server?.close();
      await runtime.close();
      store.close();
      temporary.deleteSync(recursive: true);
    }
  });
}
