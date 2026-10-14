@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_cli/universe_cli.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_client/browser_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  test('browser sessions are explicitly enrolled, expire, enforce current rights and survive no restart', () async {
    final root = Directory('/tmp').createTempSync('ub-browser-session-');
    final store = SqliteInstallationStore.create(root.path);
    final authority = InstallationAuthority(store),
        author = InstallationAuthority(store).initializeAuthor();
    EngineHello hello(ProfileId profile) => EngineHello(
      protocolVersion: protocolVersion,
      profileId: profile,
      credential: Credential(
        ProfileCredentialStore.read(root: root.path, profile: profile),
      ),
      clientName: 'Disposable browser enrollment',
    );
    final writer = authority.enroll(authority.authenticateHello(hello(author)));
    store.close();
    var now = DateTime.utc(2040);
    var server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
      httpNow: () => now,
    );
    final http = HttpClient();
    LoopbackEngineClient? native, contributor;
    var next = BigInt.one;
    Future<
      ({int status, Uint8List bytes, List<Cookie> cookies, String? setCookie})
    >
    post(
      String path, {
      CanonicalValue? body,
      String? cookie,
      String? csrf,
      String? origin,
      bool omitOrigin = false,
      String? auth,
    }) async {
      final request = await http.postUrl(server.httpEndpoint.resolve(path));
      request.headers.contentType = ContentType.json;
      if (!omitOrigin) {
        request.headers.set('origin', origin ?? server.httpEndpoint.origin);
      }
      if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
      if (csrf != null) request.headers.set('x-ub-csrf', csrf);
      if (auth != null) {
        request.headers.set(HttpHeaders.authorizationHeader, auth);
      }
      if (body != null) request.add(body.toBytes());
      final response = await request.close(), data = BytesBuilder(copy: false);
      final cookies = response.cookies,
          setCookie = response.headers.value(HttpHeaders.setCookieHeader);
      await for (final chunk in response) {
        data.add(chunk);
      }
      return (
        status: response.statusCode,
        bytes: data.takeBytes(),
        cookies: cookies,
        setCookie: setCookie,
      );
    }

    String field(CanonicalObject object, String name) =>
        wireString(Map.fromEntries(object.fields)[name]!);
    Future<({String cookie, String csrf})> exchange(
      CanonicalObject grant,
    ) async {
      final response = await post(
        '/engine/browser/exchange',
        body: CanonicalObject([
          MapEntry('token', CanonicalString(field(grant, 'enrollment_token'))),
        ]),
      );
      expect(response.status, HttpStatus.ok);
      final value = CanonicalValue.parseWireJson(
        utf8.decode(response.bytes),
      ) as CanonicalObject;
      expect(
        EngineWelcome.fromWire(Map.fromEntries(value.fields)['welcome']!)
            .principal,
        isNotNull,
      );
      expect(response.cookies.single.httpOnly, isTrue);
      expect(response.cookies.single.path, '/engine/browser');
      expect(response.setCookie!.toLowerCase(), contains('samesite=strict'));
      expect(response.setCookie!.toLowerCase(), contains('max-age=900'));
      return (
        cookie:
            '${response.cookies.single.name}=${response.cookies.single.value}',
        csrf: field(value, 'csrf'),
      );
    }

    Future<EngineResult> call(
      ({String cookie, String csrf}) session,
      EngineRequest command,
    ) async {
      final id = next;
      next += BigInt.one;
      final response = await post(
        '/engine/browser/call',
        cookie: session.cookie,
        csrf: session.csrf,
        body: EngineCall(id: id, request: command).toWire(),
      );
      expect(response.status, HttpStatus.ok);
      final reply = EngineReply.decode(response.bytes);
      expect(reply.id, id);
      return reply.result;
    }

    try {
      expect(
        (await post('/engine/browser-grant')).status,
        HttpStatus.unauthorized,
      );
      native = await LoopbackEngineClient.connect(
        endpoint: server.httpEndpoint,
        hello: hello(author),
      );
      contributor = await LoopbackEngineClient.connect(
        endpoint: server.httpEndpoint,
        hello: hello(writer),
      );
      final output = <String>[], errors = <String>[];
      expect(
        await runUniverseCli(
          [
            '--installation',
            root.path,
            '--profile',
            author.value,
            'browser-session',
          ],
          output: output.add,
          error: errors.add,
          engineHelper: () async => '${root.path}/missing/universe-engine',
        ),
        0,
      );
      expect(errors, isEmpty);
      final grant =
          CanonicalValue.parseWireJson(output.single) as CanonicalObject;
      expect(field(grant, 'endpoint'), server.httpEndpoint.toString());
      final enrollmentBody = CanonicalObject([
        MapEntry('token', CanonicalString(field(grant, 'enrollment_token'))),
      ]);
      expect(
        (await post(
          '/engine/browser/exchange',
          body: enrollmentBody,
          origin: 'https://foreign.example',
        )).status,
        HttpStatus.forbidden,
      );
      expect(
        (await post(
          '/engine/browser/exchange',
          body: enrollmentBody,
          omitOrigin: true,
        )).status,
        HttpStatus.forbidden,
      );
      final session = await exchange(grant);
      expect(
        (await post('/engine/browser/exchange', body: enrollmentBody)).status,
        HttpStatus.unauthorized,
      );
      expect(
        (await post('/engine/browser/hello', cookie: session.cookie)).status,
        HttpStatus.forbidden,
      );
      expect(
        (await post(
          '/engine/browser/hello',
          cookie: session.cookie,
          csrf: 'wrong',
        )).status,
        HttpStatus.forbidden,
      );
      expect(
        (await post('/engine/browser/hello', csrf: session.csrf)).status,
        HttpStatus.unauthorized,
      );
      expect(
        (await post(
          '/engine/hello',
          cookie: session.cookie,
          csrf: session.csrf,
        )).status,
        HttpStatus.unauthorized,
      );
      final browserHello = await post(
        '/engine/browser/hello',
        cookie: session.cookie,
        csrf: session.csrf,
      );
      expect(EngineWelcome.decode(browserHello.bytes).principal, author);
      final created = await call(
        session,
        const CreateUniverseEngineRequest(
          name: 'Browser universe',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      final createdFields = Map.fromEntries(
        ((created as EngineSuccess).value as CanonicalObject).fields,
      );
      final universe = UniverseId.parse(
        wireString(createdFields['universe_id']!),
      );
      String? clientCookie;
      final clientGrant = await native.createBrowserSession();
      final browserClient = await BrowserEngineClient.connect(
        enrollmentToken: field(clientGrant, 'enrollment_token'),
        abort: () {},
        post: (path, bytes, csrf) async {
          final response = await post(
            path,
            body: bytes.isEmpty
                ? null
                : CanonicalValue.parseWireJson(utf8.decode(bytes)),
            cookie: clientCookie,
            csrf: csrf,
          );
          if (response.cookies.isNotEmpty) {
            clientCookie =
                '${response.cookies.single.name}=${response.cookies.single.value}';
          }
          return BrowserEngineResponse(
            status: response.status,
            bytes: response.bytes,
          );
        },
      );
      try {
        expect(browserClient.welcome.principal, author);
        final source = await browserClient.call(
          StageSourceEngineRequest(
            universe: Selector('Browser universe'),
            label: 'Mémoire 😀',
            text: 'é😀\r\n',
          ),
        );
        expect(source, isA<CanonicalObject>());
        final exact = await browserClient.call(
          CreateUniverseEngineRequest(
            name: 'Exact browser time',
            start: FictionalUniverseStart(
              calendarName: 'Author calendar',
              initialTick: '9007199254740993123456789',
              tickLabel: 'tick',
            ),
          ),
        );
        final identity = Map.fromEntries((exact as CanonicalObject).fields);
        final context = RecordId.parse(wireString(identity['context_id']!));
        final opened = Envelope<OpenedContext>.fromWire(
          await browserClient.call(
            ToolEngineRequest(
              request: OpenContextRequest(
                universe: Selector('Exact browser time'),
                continuityId: ContinuityId.parse(
                  wireString(identity['continuity_id']!),
                ),
                revision: HeadRevisionSelector(),
                representedContext: ContextIdSelector(context),
                temporalQuery: TimelessFrameTime(),
                temporalSystems: [],
                perspective: AuthorPerspective(),
              ),
            ),
          ),
          OpenedContext.fromWire,
        );
        final records = Envelope<Records>.fromWire(
          await browserClient.call(
            ToolEngineRequest(
              request: GetRequest(
                universe: Selector('Exact browser time'),
                contextId: opened.result.contextId,
                recordIds: [context],
                fieldGroups: [FieldGroup.payload],
              ),
            ),
          ),
          Records.fromWire,
        );
        expect(
          (records.result.records.single.payload as RepresentedContextRecord)
              .chronology!
              .toWire()
              .toText(),
          contains('9007199254740993123456789'),
        );
        await browserClient.logout();
      } finally {
        await browserClient.close();
      }
      final writerSession = await exchange(
        await contributor.createBrowserSession(),
      );
      expect(
        await call(
          writerSession,
          const CreateUniverseEngineRequest(
            name: 'Denied',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        isA<EngineFailure>(),
      );
      final empty =
          (await call(
                writerSession,
                const StatusEngineRequest(),
              ) as EngineSuccess).value
              as CanonicalObject;
      expect(
        (Map.fromEntries(empty.fields)['universes'] as CanonicalArray).items,
        isEmpty,
      );
      await native.call(
        GrantEngineRequest(
          grant: GrantSpec(
            profileId: writer,
            universeId: universe,
            propose: true,
            edit: false,
            protected: false,
          ),
        ),
      );
      final visible =
          (await call(
                writerSession,
                const StatusEngineRequest(),
              ) as EngineSuccess).value
              as CanonicalObject;
      expect(
        (Map.fromEntries(visible.fields)['universes'] as CanonicalArray).items,
        hasLength(1),
      );
      await native.call(RevokeEngineRequest(profileId: writer));
      expect(
        (await post(
          '/engine/browser/hello',
          cookie: writerSession.cookie,
          csrf: writerSession.csrf,
        )).status,
        HttpStatus.unauthorized,
      );
      expect(
        (await post(
          '/engine/browser/logout',
          cookie: session.cookie,
          csrf: session.csrf,
        )).status,
        HttpStatus.ok,
      );
      expect(
        (await post(
          '/engine/browser/hello',
          cookie: session.cookie,
          csrf: session.csrf,
        )).status,
        HttpStatus.unauthorized,
      );
      final expiredGrant = await native.createBrowserSession();
      now = now.add(const Duration(minutes: 1));
      expect(
        (await post(
          '/engine/browser/exchange',
          body: CanonicalObject([
            MapEntry(
              'token',
              CanonicalString(field(expiredGrant, 'enrollment_token')),
            ),
          ]),
        )).status,
        HttpStatus.unauthorized,
      );
      final expiringSession = await exchange(
        await native.createBrowserSession(),
      );
      now = now.add(const Duration(minutes: 15));
      expect(
        (await post(
          '/engine/browser/hello',
          cookie: expiringSession.cookie,
          csrf: expiringSession.csrf,
        )).status,
        HttpStatus.unauthorized,
      );
      final beforeRestart = await exchange(await native.createBrowserSession());
      expect(
        (await post(
          '/engine/browser/hello',
          cookie: beforeRestart.cookie,
          csrf: beforeRestart.csrf,
        )).status,
        HttpStatus.ok,
      );
      await native.close();
      await contributor.close();
      await server.close();
      server = await LocalSqliteEngineServer.start(
        root.path,
        compatibilitySocket: false,
        httpNow: () => now,
      );
      expect(
        (await post(
          '/engine/browser/hello',
          cookie:
              'ub_browser_${server.httpEndpoint.port}=${beforeRestart.cookie.split('=').last}',
          csrf: beforeRestart.csrf,
        )).status,
        HttpStatus.unauthorized,
      );
    } finally {
      await native?.close();
      await contributor?.close();
      http.close(force: true);
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
