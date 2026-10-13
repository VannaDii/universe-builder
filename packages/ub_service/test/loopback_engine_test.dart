@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
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
    store.close();
    final server = await LocalSqliteEngineServer.start(root.path);
    final http = HttpClient();
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
      final created = value(
        await call(
          author,
          CreateUniverseEngineRequest(
            name: 'HTTP universe',
            start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
      );
      final universe = UniverseId.parse(
        wireString(field(created, 'universe_id')),
      );
      expect(
        await call(
          writer,
          CreateUniverseEngineRequest(
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
            universe: const Selector('HTTP universe'),
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
            request: DescribeSummaryRequest(
              universe: const Selector('HTTP universe'),
            ),
          ),
        ),
      );
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
      final reopened = SqliteInstallationStore.openExisting(root.path);
      reopened.close();
    } finally {
      http.close(force: true);
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
