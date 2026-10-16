import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_mcp/http.dart';
import 'package:ub_mcp/session.dart';
import 'package:ub_mcp/local_backend.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

import 'session_test.dart' show initialize, call;

typedef Reply = ({int status, Map<String, String> headers, String body});

void main() {
  late HttpServer server;
  late HttpClient client;
  late McpHttpHandler handler;
  late Uri resource;
  late DateTime now;
  late McpToolBackend backend;
  var authenticated = 0, calls = 0, revoked = false;
  setUp(() async {
    authenticated = calls = 0;
    revoked = false;
    now = DateTime.utc(2040);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = Uri.parse('http://127.0.0.1:${server.port}/mcp');
    client = HttpClient()..maxConnectionsPerHost = 32;
    backend = (request, cancelled) async {
      calls++;
      return CanonicalObject([
        MapEntry('universe', CanonicalString(request.universe.value)),
      ]);
    };
    handler = McpHttpHandler(
      resource: resource,
      serverVersion: '0.1.0',
      authorizationServers: [Uri.parse('https://identity.example.invalid')],
      allowedOrigins: [resource.origin],
      now: () => now,
      authenticate: (token, audience) async {
        authenticated++;
        expect(audience, resource);
        if (revoked || !{'author-A', 'author-B'}.contains(token)) {
          return null;
        }
        return McpHttpPrincipal(key: 'installation/$token', backend: backend);
      },
    );
    server.listen((request) async {
      if (!await handler.handle(request)) {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
  });
  tearDown(() async {
    handler.close();
    client.close(force: true);
    await server.close(force: true);
  });
  Future<Reply> send({
    String method = 'POST',
    String? session,
    String? token = 'author-A',
    String? body,
    List<int>? bytes,
    Uri? uri,
    String? origin,
    String? host,
    String? version = '2025-11-25',
    String accept = 'application/json, text/event-stream',
    String type = 'application/json',
    Map<String, List<String>> repeatedHeaders = const {},
  }) async {
    final request = await client.openUrl(method, uri ?? resource);
    request.headers.set('Accept', accept);
    request.headers.set('Content-Type', type);
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (session != null) request.headers.set('MCP-Session-Id', session);
    if (version != null) request.headers.set('MCP-Protocol-Version', version);
    if (origin != null) request.headers.set('Origin', origin);
    if (host != null) request.headers.set('Host', host);
    for (final entry in repeatedHeaders.entries) {
      request.headers.removeAll(entry.key);
      for (final value in entry.value) {
        request.headers.add(entry.key, value);
      }
    }
    if (bytes != null || body != null) request.add(bytes ?? utf8.encode(body!));
    final response = await request.close();
    final headers = <String, String>{};
    response.headers.forEach(
      (name, values) => headers[name.toLowerCase()] = values.join(', '),
    );
    return (
      status: response.statusCode,
      headers: headers,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  Future<String> init() async {
    final response = await send(body: initialize.toText());
    expect(response.status, 200);
    return response.headers['mcp-session-id']!;
  }

  String ping() => '{"jsonrpc":"2.0","id":"ping","method":"ping"}';

  test(
    'HTTP tool dispatch reaches the existing authenticated SQLite service',
    () async {
      final root = Directory.systemTemp.createTempSync('ub-mcp-http-');
      final catalog = SqliteInstallationStore.create(root.path);
      final profile = InstallationAuthority(catalog).initializeAuthor();
      catalog.close();
      final engine = await LocalSqliteEngineServer.start(
        root.path,
        compatibilitySocket: false,
      );
      try {
        final owner = await LoopbackEngineClient.discover(
          root: root.path,
          profile: profile,
          clientName: 'disposable-http-setup',
        );
        try {
          await owner.call(
            const CreateUniverseEngineRequest(
              name: 'Test',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          );
        } finally {
          await owner.close();
        }
        backend = (request, cancelled) => callLocalMcpTool(
          root: root.path,
          profile: profile,
          request: request,
          cancelled: cancelled,
        );
        final id = await init();
        final result = await send(session: id, body: call('7').toText());
        expect(result.status, 200);
        final rpc = jsonDecode(result.body) as Map<String, dynamic>;
        final tool = rpc['result'] as Map<String, dynamic>;
        expect(tool['isError'], isNot(true));
        expect(tool['structuredContent'], isA<Map<String, dynamic>>());
        expect(result.body, contains('Test'));
        expect(result.body, contains('represented_contexts'));
      } finally {
        handler.close();
        await engine.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'protected-resource metadata, challenge and origin checks precede dispatch',
    () async {
      final metadata = await send(
        method: 'GET',
        uri: handler.metadata,
        token: null,
      );
      expect(metadata.status, 200);
      final data = jsonDecode(metadata.body) as Map<String, dynamic>;
      expect(data['resource'], resource.toString());
      expect(data['authorization_servers'], [
        'https://identity.example.invalid',
      ]);
      expect(data['bearer_methods_supported'], ['header']);
      expect(authenticated, 0);
      final denied = await send(token: null, body: initialize.toText());
      expect(denied.status, 401);
      expect(
        denied.headers['www-authenticate'],
        contains(handler.metadata.toString()),
      );
      expect(denied.headers['cache-control'], 'no-store');
      expect(
        (await send(
          body: initialize.toText(),
          origin: 'https://evil.invalid',
        )).status,
        403,
      );
      expect(
        (await send(body: initialize.toText(), host: 'evil.invalid')).status,
        403,
      );
      expect(authenticated, 0);
      expect(calls, 0);
      expect(
        (await send(body: initialize.toText(), origin: resource.origin)).status,
        200,
      );
    },
  );

  test('HTTP negotiation, notification acknowledgement, discovery and no GET stream', () async {
    final unqualified = await send(
      body: initialize.toText().replaceFirst('2025-11-25', '2024-11-05'),
      version: null,
    );
    expect(unqualified.status, 200);
    expect(unqualified.body, contains('2025-11-25'));
    final id = unqualified.headers['mcp-session-id']!;
    expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(
      (await send(
        session: id,
        body: '{"jsonrpc":"2.0","method":"notifications/initialized"}',
      )).status,
      202,
    );
    final notification = await send(
      session: id,
      body: '{"jsonrpc":"2.0","method":"notifications/initialized"}',
    );
    expect(notification.body, isEmpty);
    final listed = await send(
      session: id,
      body: '{"jsonrpc":"2.0","id":1,"method":"tools/list"}',
    );
    expect(listed.status, 200);
    expect(listed.headers['content-type'], contains('application/json'));
    expect(listed.body, contains('universe_check_changes'));
    final listedRpc = jsonDecode(listed.body) as Map<String, dynamic>;
    final tools =
        (listedRpc['result'] as Map<String, dynamic>)['tools'] as List<dynamic>;
    expect(
      tools.map((t) => (t as Map<String, dynamic>)['name']),
      everyElement(isNot(contains('approve'))),
    );
    final get = await send(method: 'GET', session: id);
    expect(get.status, 405);
    expect(get.headers['allow'], 'POST, DELETE');
    expect((await send(session: id, body: ping(), version: null)).status, 200);
    expect(calls, 0);
  });

  test('each POST authenticates afresh, with principal binding, expiry and deletion', () async {
    final id = await init();
    expect(
      (await send(session: id, token: 'author-B', body: ping())).status,
      404,
    );
    revoked = true;
    expect((await send(session: id, body: ping())).status, 401);
    revoked = false;
    var fresh = false;
    backend = (_, _) async {
      fresh = true;
      return CanonicalObject([]);
    };
    expect((await send(session: id, body: call('1').toText())).status, 200);
    expect(fresh, isTrue);
    expect(authenticated, 4);
    expect((await send(method: 'DELETE', session: id)).status, 204);
    expect((await send(session: id, body: ping())).status, 404);
    final expires = await init();
    now = now.add(const Duration(minutes: 15));
    expect((await send(session: expires, body: ping())).status, 404);
  });

  test(
    'malformed, duplicate, batch and oversized input cannot reach tools',
    () async {
      final id = await init();
      for (final body in [
        '[]',
        '{"jsonrpc":"2.0","id":1,"id":2,"method":"ping"}',
        '{',
      ]) {
        expect((await send(session: id, body: body)).status, 400);
      }
      expect((await send(session: id, bytes: [0xff])).status, 400);
      expect(
        (await send(
          session: id,
          bytes: [0xef, 0xbb, 0xbf, ...utf8.encode(ping())],
        )).status,
        400,
      );
      expect(
        (await send(session: id, body: ' ' * (maxFrameBytes + 1))).status,
        413,
      );
      expect(
        (await send(
          session: id,
          body: ping(),
          accept: 'application/json',
        )).status,
        406,
      );
      expect(
        (await send(session: id, body: ping(), type: 'text/plain')).status,
        415,
      );
      expect(
        (await send(session: id, body: ping(), version: 'unsupported')).status,
        400,
      );
      expect((await send(body: ping())).status, 400);
      expect((await send(session: id, body: initialize.toText())).status, 400);
      expect(
        (await send(
          uri: resource.replace(query: 'access_token=untrusted'),
          body: ping(),
        )).status,
        400,
      );
      expect(calls, 0);
      expect((await send(session: id, body: ping())).status, 200);
    },
  );

  test(
    'explicit cancellation remains responsive beside a pending tool',
    () async {
      final started = Completer<void>(), cancelled = Completer<void>();
      backend = (_, stop) async {
        started.complete();
        await stop;
        cancelled.complete();
        return CanonicalObject([]);
      };
      final id = await init();
      final pending = send(session: id, body: call('41').toText());
      await started.future;
      expect((await send(session: id, body: ping())).status, 200);
      expect(
        (await send(
          session: id,
          body: '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":41}}',
        )).status,
        202,
      );
      await cancelled.future;
      final result = await pending;
      expect(result.status, 200);
      expect(result.body, contains('cancelled'));
    },
  );

  test('disconnect does not cancel or replay admitted work', () async {
    final started = Completer<void>(),
        finish = Completer<void>(),
        completed = Completer<void>();
    var cancelled = false;
    backend = (_, stop) async {
      calls++;
      stop.then((_) => cancelled = true);
      started.complete();
      await finish.future;
      completed.complete();
      return CanonicalObject([]);
    };
    final id = await init();
    final broken = HttpClient();
    final request = await broken.postUrl(resource);
    request.headers.set('Authorization', 'Bearer author-A');
    request.headers.set('MCP-Session-Id', id);
    request.headers.set('MCP-Protocol-Version', '2025-11-25');
    request.headers.set('Accept', 'application/json, text/event-stream');
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(call('42').toText()));
    final response = request.close().then<void>((r) async {
      await r.drain<void>();
    }, onError: (_) {});
    await started.future;
    broken.close(force: true);
    await response;
    finish.complete();
    await completed.future;
    expect((await send(session: id, body: ping())).status, 200);
    expect(cancelled, isFalse);
    expect(calls, 1);
  });

  test(
    'parallel initialization is bounded and expired sessions release capacity',
    () async {
      final responses = await Future.wait(
        List.generate(maxInFlight + 1, (_) => send(body: initialize.toText())),
      );
      expect(responses.where((r) => r.status == 200), hasLength(maxInFlight));
      expect(responses.where((r) => r.status == 429), hasLength(1));
      now = now.add(const Duration(minutes: 15));
      expect((await send(body: initialize.toText())).status, 200);
    },
  );
  test('saturated tools keep ping and cancellation available and shutdown releases work', () async {
    final started = Completer<void>();
    var active = 0;
    backend = (_, stop) async {
      if (++active == maxInFlight) started.complete();
      await stop;
      return CanonicalObject([]);
    };
    final id = await init();
    final pending = [
      for (var i = 0; i < maxInFlight; i++)
        send(session: id, body: call('$i').toText()),
    ];
    await started.future;
    expect((await send(session: id, body: call('100').toText())).status, 429);
    expect((await send(session: id, body: ping())).status, 200);
    expect(
      (await send(
        session: id,
        body: '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":0}}',
      )).status,
      202,
    );
    expect((await pending.first).status, 200);
    handler.close();
    for (final response in await Future.wait(pending.skip(1))) {
      expect(response.status, 404);
    }
  });
  test(
    'negotiated HTTP versions and exact numeric correlation survive requests',
    () async {
      for (final version in ['2025-03-26', '2025-06-18', '2025-11-25']) {
        final initialized = await send(
          body: initialize.toText().replaceFirst('2025-11-25', version),
          version: null,
        );
        expect(initialized.body, contains('"protocolVersion":"$version"'));
        final id = initialized.headers['mcp-session-id']!;
        final response = await send(
          session: id,
          version: version,
          body: '{"jsonrpc":"2.0","id":9007199254740993,"method":"ping"}',
        );
        expect(response.status, 200);
        expect(response.body, contains('"id":9007199254740993'));
        expect(
          (await send(session: id, version: '2024-11-05', body: ping())).status,
          400,
        );
      }
    },
  );
  test(
    'advanced HTTP discovery pages retain all tools within the frame bound',
    () async {
      handler.close();
      handler = McpHttpHandler(
        resource: resource,
        serverVersion: '0.1.0',
        authorizationServers: [Uri.parse('https://identity.example.invalid')],
        advanced: true,
        authenticate: (token, audience) async => token == 'author-A'
            ? McpHttpPrincipal(key: 'installation/author-A', backend: backend)
            : null,
      );
      final id = await init();
      String? cursor;
      final names = <String>[];
      var pages = 0;
      do {
        final response = await send(
          session: id,
          body: CanonicalObject([
            MapEntry('jsonrpc', CanonicalString('2.0')),
            MapEntry('id', CanonicalNumber('$pages')),
            MapEntry('method', CanonicalString('tools/list')),
            MapEntry(
              'params',
              CanonicalObject([
                if (cursor != null) MapEntry('cursor', CanonicalString(cursor)),
              ]),
            ),
          ]).toText(),
        );
        expect(response.status, 200);
        expect(
          utf8.encode(response.body).length,
          lessThanOrEqualTo(maxFrameBytes),
        );
        final rpc = jsonDecode(response.body) as Map<String, dynamic>;
        final result = rpc['result'] as Map<String, dynamic>;
        for (final tool in result['tools'] as List<dynamic>) {
          names.add((tool as Map<String, dynamic>)['name'] as String);
        }
        cursor = result['nextCursor'] as String?;
        pages++;
      } while (cursor != null);
      expect(pages, greaterThan(1));
      expect(names, hasLength(16));
      expect(names.toSet(), hasLength(16));
    },
  );
  test('ambiguous authorization and origins are rejected while Accept may span headers', () async {
    expect(
      (await send(
        body: initialize.toText(),
        repeatedHeaders: {
          'Origin': [resource.origin, 'https://other.invalid'],
        },
      )).status,
      403,
    );
    expect(authenticated, 0);
    expect(
      (await send(
        body: initialize.toText(),
        repeatedHeaders: {
          'Authorization': ['Bearer author-A', 'Bearer author-B'],
        },
      )).status,
      401,
    );
    expect(authenticated, 0);
    final response = await send(
      body: initialize.toText(),
      repeatedHeaders: {
        'Accept': ['application/json', 'text/event-stream'],
      },
    );
    expect(response.status, 200);
  });
}
