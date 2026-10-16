@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  test('bundled web assets share the loopback origin without exposing installation files', () async {
    final temporary = Directory('/tmp').createTempSync('ub-web-assets-');
    final root = '${temporary.path}/installation';
    final store = SqliteInstallationStore.create(root);
    InstallationAuthority(store).initializeAuthor();
    store.close();
    final assets = Directory('${temporary.path}/web')..createSync();
    File('${assets.path}/index.html')
        .writeAsStringSync('<html>Universe Builder é</html>');
    File('${assets.path}/main.dart.js')
        .writeAsStringSync('console.log("bundled");');
    File('${assets.path}/engine.wasm').writeAsBytesSync([0, 97, 115, 109]);
    Directory('${assets.path}/assets').createSync();
    File('${assets.path}/assets/font.ttf').writeAsBytesSync([1, 2, 3]);
    Link('${assets.path}/private').createSync(root);
    Link('${assets.path}/secret.json').createSync('$root/engine-http.json');
    final server = await LocalSqliteEngineServer.start(
      root,
      compatibilitySocket: false,
      webAssets: assets.path,
    );
    final http = HttpClient();
    Future<
      ({
        int status,
        List<int> bytes,
        String? type,
        int length,
        String? policy,
        String? cache,
      })
    >
    fetch(
      String path, {
      String method = 'GET',
      String? host,
      String? origin,
    }) async {
      final request = await http.openUrl(
        method,
        server.httpEndpoint.resolve(path),
      );
      if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
      if (origin != null) request.headers.set('origin', origin);
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return (
        status: response.statusCode,
        bytes: bytes,
        type: response.headers.contentType?.mimeType,
        length: response.contentLength,
        policy: response.headers.value('content-security-policy'),
        cache: response.headers.value(HttpHeaders.cacheControlHeader),
      );
    }

    try {
      final index = await fetch('/');
      expect(index.status, HttpStatus.ok);
      expect(utf8.decode(index.bytes), '<html>Universe Builder é</html>');
      expect(index.type, 'text/html');
      expect(index.cache, 'no-store');
      expect(index.policy, contains("script-src 'self' 'wasm-unsafe-eval'"));
      expect(index.policy, contains("frame-ancestors 'none'"));
      expect(index.policy, contains("object-src 'none'"));
      expect(index.policy, isNot(contains("'unsafe-eval'")));
      final script = await fetch('/main.dart.js?v=1');
      expect(script.type, 'text/javascript');
      expect(script.policy, index.policy);
      expect(script.cache, 'no-store');
      final wasm = await fetch('/engine.wasm');
      expect(wasm.type, 'application/wasm');
      expect(wasm.bytes, [0, 97, 115, 109]);
      expect((await fetch('/assets/font.ttf')).bytes, [1, 2, 3]);
      final head = await fetch('/index.html', method: 'HEAD');
      expect(head.status, HttpStatus.ok);
      expect(head.bytes, isEmpty);
      expect(head.length, index.bytes.length);
      expect(head.policy, index.policy);
      for (final path in [
        '/engine/hello',
        '/engine-http.json',
        '/secret.json',
        '/private/engine-http.json',
        '/assets/%2e%2e%2fengine-http.json',
        '/missing.js',
      ]) {
        expect((await fetch(path)).status, HttpStatus.notFound, reason: path);
      }
      expect((await fetch('/', method: 'POST')).status, HttpStatus.notFound);
      expect(
        (await fetch('/', host: 'foreign.example')).status,
        HttpStatus.forbidden,
      );
      expect(
        (await fetch('/', origin: 'https://foreign.example')).status,
        HttpStatus.forbidden,
      );
    } finally {
      http.close(force: true);
      await server.close();
      temporary.deleteSync(recursive: true);
    }
  });

  test('loopback HTTP authenticates current profiles, dispatches exact calls and rejects foreign hosts/origins', () async {
    final root = Directory('/tmp').createTempSync('ub-http-');
    final store = SqliteInstallationStore.create(root.path);
    final authority = InstallationAuthority(store);
    final author = authority.initializeAuthor();
    EngineHello hello(ProfileId profile) => EngineHello(
      protocolVersion: protocolVersion,
      profileId: profile,
      credential: Credential(
        ProfileCredentialStore.read(root: root.path, profile: profile),
      ),
      clientName: 'Disposable HTTP client',
    );
    final writer = authority.enroll(authority.authenticateHello(hello(author)));
    final universeName = 'Memoir / Family \\ * "Zoë" %2F ? # & + ${'界' * 100}';
    store.close();
    final server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
    );
    final http = HttpClient();
    LoopbackEngineClient? native;
    var next = BigInt.one;
    Future<(int, Uint8List)> request({
      EngineHello? principal,
      EngineCall? call,
      String? origin,
      String? host,
    }) async {
      final request = await http.postUrl(
        server.httpEndpoint.resolve(
          call == null ? '/engine/hello' : '/engine/call',
        ),
      );
      if (principal != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'UB ${base64Encode(principal.toWire().toBytes())}',
        );
      }
      if (origin != null) request.headers.set('origin', origin);
      if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
      if (call != null) request.add(call.toWire().toBytes());
      final response = await request.close();
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return (response.statusCode, bytes.takeBytes());
    }

    Future<EngineResult> call(ProfileId profile, EngineRequest command) async {
      final id = next;
      next += BigInt.one;
      final (status, bytes) = await request(
        principal: hello(profile),
        call: EngineCall(id: id, request: command),
      );
      expect(status, HttpStatus.ok);
      final reply = EngineReply.decode(bytes);
      expect(reply.id, id);
      return reply.result;
    }

    CanonicalValue value(EngineResult result) =>
        (result as EngineSuccess).value;
    CanonicalValue field(CanonicalValue body, String key) =>
        (body as CanonicalObject).fields
            .singleWhere((field) => field.key == key)
            .value;
    try {
      expect((await request()).$1, HttpStatus.unauthorized);
      expect(
        (await request(
          principal: hello(author),
          origin: 'https://foreign.example',
        )).$1,
        HttpStatus.forbidden,
      );
      expect(
        (await request(principal: hello(author), host: 'foreign.example')).$1,
        HttpStatus.forbidden,
      );
      final (status, bytes) = await request(
        principal: hello(author),
        origin: server.httpEndpoint.origin,
      );
      expect(status, HttpStatus.ok);
      expect(EngineWelcome.decode(bytes).principal, author);
      native = await LoopbackEngineClient.ensureRunning(
        root: root.path,
        profile: author,
        helper: '${root.path}/missing/universe-engine',
        clientName: 'Native HTTP client',
      );
      expect(
        FileSystemEntity.typeSync(
          '${root.path}/engine.sock',
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
      expect(native.welcome.principal, author);
      final created = await native.call(
        CreateUniverseEngineRequest(
          realWorld: false,
          name: universeName,
          start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      final universe = UniverseId.parse(
        wireString(field(created, 'universe_id')),
      );
      expect(
        await call(
          writer,
          CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Denied',
            start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        isA<EngineFailure>(),
      );
      expect(
        await call(
          author,
          StageSourceEngineRequest(
            universe: Selector(universeName),
            label: 'Exact source',
            text: 'é😀\r\n',
          ),
        ),
        isA<EngineSuccess>(),
      );
      final summary = value(
        await call(
          author,
          ToolEngineRequest(
            request: DescribeSummaryRequest(universe: Selector(universeName)),
          ),
        ),
      );
      expect(wireString(field(summary, 'universe')), universeName);
      expect(
        (field(summary, 'request_id') as CanonicalNumber).digits,
        '${next - BigInt.one}',
      );
      expect(
        await call(
          author,
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writer,
              universeId: universe,
              propose: true,
              edit: false,
              protected: false,
            ),
          ),
        ),
        isA<EngineSuccess>(),
      );
      final visible = value(await call(writer, const StatusEngineRequest()));
      expect(
        (field(visible, 'universes') as CanonicalArray).items,
        hasLength(1),
      );
      expect(
        await call(author, RevokeEngineRequest(profileId: writer)),
        isA<EngineSuccess>(),
      );
      expect(
        (await request(principal: hello(writer))).$1,
        HttpStatus.unauthorized,
      );
      expect(
        await call(author, const ShutdownEngineRequest()),
        isA<EngineSuccess>(),
      );
      await server.done.timeout(const Duration(seconds: 5));
      expect(File('${root.path}/engine-http.json').existsSync(), isFalse);
      final reopened = SqliteInstallationStore.openExisting(root.path);
      reopened.close();
    } finally {
      await native?.close();
      http.close(force: true);
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
