@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/hosted_providers.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

final class _SignIn implements HostedSignInProvider {
  _SignIn(this.identities);
  final Map<String, HostedIdentity> identities;
  @override
  Future<HostedIdentity> authenticate(String assertion) async =>
      identities[assertion] ??
      (throw const FormatException('Invalid assertion'));
}

final class _Billing implements HostedBillingProvider {
  final accounts = <String>[];
  @override
  Future<HostedBillingStatus> status(String accountId) async {
    accounts.add(accountId);
    return const HostedBillingStatus(
      provider: 'test-provider',
      status: HostedSubscriptionStatus.active,
    );
  }
}

typedef _Reply = ({int status, String body, List<Cookie> cookies});

Future<_Reply> _post(
  HttpClient http,
  Uri endpoint,
  String path, {
  Map<String, Object?>? body,
  Cookie? cookie,
  String? csrf,
  String? origin,
}) async {
  final request = await http.postUrl(endpoint.resolve(path));
  request.headers.set('origin', origin ?? endpoint.origin);
  request.headers.contentType = ContentType.json;
  if (cookie != null) request.cookies.add(cookie);
  if (csrf != null) request.headers.set('x-ub-csrf', csrf);
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  return (
    status: response.statusCode,
    body: await utf8.decoder.bind(response).join(),
    cookies: response.cookies,
  );
}

EngineHello _hello(String root, ProfileId id) => EngineHello(
  protocolVersion: protocolVersion,
  profileId: id,
  credential: Credential(ProfileCredentialStore.read(root: root, profile: id)),
  clientName: 'Hosted provider test',
);

void main() {
  test('default hosted sign-in is unavailable and issues no session', () async {
    final root = Directory('/tmp').createTempSync('ub-hosted-stub-');
    final store = SqliteInstallationStore.create(root.path);
    final owner = InstallationAuthority(store).initializeAuthor();
    final ownerHello = _hello(root.path, owner);
    store.close();
    final server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
      hostedAccount: HostedAccountAccess(accountId: 'account-a', profiles: {}),
    );
    final http = HttpClient();
    final native = await LoopbackEngineClient.connect(
      endpoint: server.httpEndpoint,
      hello: ownerHello,
    );
    try {
      final reply = await _post(
        http,
        server.httpEndpoint,
        '/engine/browser/sign-in',
        body: {'assertion': 'unverified'},
      );
      expect(reply.status, HttpStatus.serviceUnavailable);
      expect(reply.cookies, isEmpty);
      final grant = WireFields(await native.createBrowserSession(), {
        'enrollment_token',
        'expires_at',
      });
      final session = await _post(
        http,
        server.httpEndpoint,
        '/engine/browser/exchange',
        body: {'token': grant.string('enrollment_token')},
      );
      expect(session.status, HttpStatus.ok);
      final billing = await _post(
        http,
        server.httpEndpoint,
        '/engine/browser/billing',
        cookie: session.cookies.single,
        csrf: (jsonDecode(session.body) as Map)['csrf'] as String,
      );
      expect(billing.status, HttpStatus.ok);
      expect(jsonDecode(billing.body), {
        'provider': 'stub',
        'status': 'not_configured',
      });
    } finally {
      await native.close();
      http.close(force: true);
      await server.close();
      root.deleteSync(recursive: true);
    }
  });

  test(
    'hosted sign-in stays within installation profiles and current grants',
    () async {
      final root = Directory('/tmp').createTempSync('ub-hosted-access-');
      final otherRoot = Directory('/tmp').createTempSync('ub-hosted-other-');
      final store = SqliteInstallationStore.create(root.path);
      final authority = InstallationAuthority(store);
      final owner = authority.initializeAuthor();
      final ownerHello = _hello(root.path, owner);
      final writer = authority.enroll(authority.authenticateHello(ownerHello));
      final writerHello = _hello(root.path, writer);
      final otherStore = SqliteInstallationStore.create(otherRoot.path);
      final otherOwner = InstallationAuthority(otherStore).initializeAuthor();
      final otherHello = _hello(otherRoot.path, otherOwner);
      otherStore.close();
      store.close();
      final ownerIdentity = HostedIdentity(
        issuer: 'issuer-a',
        subject: 'owner',
      );
      final writerIdentity = HostedIdentity(
        issuer: 'issuer-a',
        subject: 'writer',
      );
      final otherIdentity = HostedIdentity(
        issuer: 'issuer-a',
        subject: 'other',
      );
      final billing = _Billing();
      final server = await LocalSqliteEngineServer.start(
        root.path,
        compatibilitySocket: false,
        hostedAccount: HostedAccountAccess(
          accountId: 'account-a',
          signIn: _SignIn({
            'owner-assertion': ownerIdentity,
            'writer-assertion': writerIdentity,
            'wrong-issuer': HostedIdentity(
              issuer: 'issuer-b',
              subject: 'owner',
            ),
            'other-installation': otherIdentity,
          }),
          billing: billing,
          profiles: {
            ownerIdentity: ownerHello,
            writerIdentity: writerHello,
            otherIdentity: otherHello,
          },
        ),
      );
      final http = HttpClient();
      final native = await LoopbackEngineClient.connect(
        endpoint: server.httpEndpoint,
        hello: ownerHello,
      );
      Future<_Reply> signIn(String assertion, {String? origin}) => _post(
        http,
        server.httpEndpoint,
        '/engine/browser/sign-in',
        body: {'assertion': assertion},
        origin: origin,
      );
      try {
        for (final assertion in [
          'unknown',
          'wrong-issuer',
          'other-installation',
        ]) {
          final reply = await signIn(assertion);
          expect(reply.status, HttpStatus.unauthorized, reason: assertion);
          expect(reply.cookies, isEmpty);
        }
        expect(
          (await signIn(
            'owner-assertion',
            origin: 'https://foreign.example',
          )).status,
          HttpStatus.forbidden,
        );
        final ownerSession = await signIn('owner-assertion');
        expect(ownerSession.status, HttpStatus.ok);
        expect(
          ownerSession.body,
          isNot(contains(ownerHello.credential.expose())),
        );
        final ownerCsrf =
            (jsonDecode(ownerSession.body) as Map)['csrf'] as String;
        final ownerCookie = ownerSession.cookies.single;
        expect(ownerCookie.httpOnly, isTrue);
        expect(
          (await _post(
            http,
            server.httpEndpoint,
            '/engine/browser/billing',
            cookie: ownerCookie,
          )).status,
          HttpStatus.forbidden,
        );
        final status = await _post(
          http,
          server.httpEndpoint,
          '/engine/browser/billing',
          cookie: ownerCookie,
          csrf: ownerCsrf,
        );
        expect(status.status, HttpStatus.ok);
        expect(jsonDecode(status.body), {
          'provider': 'test-provider',
          'status': 'active',
        });
        expect(billing.accounts, ['account-a']);
        final writerSession = await signIn('writer-assertion');
        expect(writerSession.status, HttpStatus.ok);
        final writerCookie = writerSession.cookies.single;
        final writerCsrf =
            (jsonDecode(writerSession.body) as Map)['csrf'] as String;
        expect(
          (await _post(
            http,
            server.httpEndpoint,
            '/engine/browser/billing',
            cookie: writerCookie,
            csrf: writerCsrf,
          )).status,
          HttpStatus.forbidden,
        );
        await native.call(RevokeEngineRequest(profileId: writer));
        expect(
          (await _post(
            http,
            server.httpEndpoint,
            '/engine/browser/hello',
            cookie: writerCookie,
            csrf: writerCsrf,
          )).status,
          HttpStatus.unauthorized,
        );
        expect(
          (await signIn('writer-assertion')).status,
          HttpStatus.unauthorized,
        );
      } finally {
        await native.close();
        http.close(force: true);
        await server.close();
        root.deleteSync(recursive: true);
        otherRoot.deleteSync(recursive: true);
      }
    },
  );
}
