@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_store/sqlite.dart' as local;
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

    Future<({int status, Uint8List bytes, String? disposition})> download(
      String path, {
      String? cookie,
      String? origin,
    }) async {
      final request = await http.getUrl(server.httpEndpoint.resolve(path));
      if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
      if (origin != null) request.headers.set('origin', origin);
      final response = await request.close();
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return (
        status: response.statusCode,
        bytes: bytes.takeBytes(),
        disposition: response.headers.value('content-disposition'),
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
      // Browser sessions use content transfer rather than arbitrary server paths.
      final deniedPath = '${root.path}/browser-path-output';
      for (final command in <EngineRequest>[
        BackupEngineRequest(
          universe: Selector('Browser universe'),
          destination: deniedPath,
        ),
        RestoreEngineRequest(source: deniedPath, name: 'Restored'),
        ConvertLegacyEngineRequest(source: deniedPath, destination: deniedPath),
        ExportLogicalEngineRequest(
          universe: Selector('Browser universe'),
          destination: deniedPath,
          recordIds: [],
        ),
        PreviewImportEngineRequest(
          source: deniedPath,
          name: 'Imported',
          mode: ImportMode.restore,
        ),
        RegisterUniverseEngineRequest(path: deniedPath, name: 'Registered'),
        StageImageEngineRequest(
          universe: Selector('Browser universe'),
          source: deniedPath,
        ),
      ]) {
        final result = await call(session, command);
        expect(result, isA<EngineFailure>());
        expect((result as EngineFailure).error, isA<PolicyDeniedError>());
      }
      expect(File(deniedPath).existsSync(), isFalse);
      expect(Directory(deniedPath).existsSync(), isFalse);
      // The native owner's existing backup path workflow is unchanged.
      final nativeBackup = '${root.path}/native-backup.sqlite';
      await native.call(
        BackupEngineRequest(
          universe: Selector('Browser universe'),
          destination: nativeBackup,
        ),
      );
      expect(File(nativeBackup).existsSync(), isTrue);
      final preparation = await post(
        '/engine/browser/prepare-download',
        cookie: session.cookie,
        csrf: session.csrf,
        body: CanonicalObject([
          MapEntry('universe', Selector('Browser universe').toWire()),
        ]),
      );
      expect(preparation.status, HttpStatus.ok);
      final prepared = PreparedBrowserArchive.fromWire(
        CanonicalValue.parseWireJson(utf8.decode(preparation.bytes)),
      );
      expect(prepared.path, isNot(contains(root.path)));
      expect((await download(prepared.path)).status, HttpStatus.unauthorized);
      expect(
        (await download(
          prepared.path,
          cookie: session.cookie,
          origin: 'https://foreign.example',
        )).status,
        HttpStatus.forbidden,
      );
      final freshSession = await exchange(await native.createBrowserSession());
      expect(
        (await download(prepared.path, cookie: freshSession.cookie)).status,
        HttpStatus.unauthorized,
      );
      final downloaded = await download(prepared.path, cookie: session.cookie);
      expect(downloaded.status, HttpStatus.ok);
      expect(downloaded.disposition, contains('attachment'));
      expect(downloaded.bytes.length, prepared.bytes);
      final downloadedPath = '${root.path}/downloaded.sqlite';
      protectedFile(downloadedPath, createNew: true);
      File(downloadedPath).writeAsBytesSync(downloaded.bytes);
      final downloadedArchive = local.OwnedSqliteDatabase.stageLogicalArchive(
        downloadedPath,
        root.path,
      );
      try {
        expect(downloadedArchive.digest, prepared.digest);
      } finally {
        downloadedArchive.close();
      }
      expect(
        (await download(prepared.path, cookie: session.cookie)).status,
        HttpStatus.unauthorized,
      );
      // Preparing a replacement invalidates the session's unused snapshot URL.
      Future<PreparedBrowserArchive> prepare() async {
        final response = await post(
          '/engine/browser/prepare-download',
          cookie: session.cookie,
          csrf: session.csrf,
          body: CanonicalObject([
            MapEntry('universe', Selector('Browser universe').toWire()),
          ]),
        );
        expect(response.status, HttpStatus.ok);
        return PreparedBrowserArchive.fromWire(
          CanonicalValue.parseWireJson(utf8.decode(response.bytes)),
        );
      }

      final replaced = await prepare();
      final replacement = await prepare();
      expect(
        (await download(replaced.path, cookie: session.cookie)).status,
        HttpStatus.unauthorized,
      );
      now = now.add(const Duration(minutes: 6));
      expect(
        (await download(replacement.path, cookie: session.cookie)).status,
        HttpStatus.unauthorized,
      );

      Future<EngineResult> uploadFile(
        List<int> bytes,
        OperationId id, {
        String name = 'File clone',
        String? cookie,
        String? csrf,
        String? origin,
        int expectedStatus = HttpStatus.ok,
      }) async {
        final request = await http.postUrl(
          server.httpEndpoint.resolve('/engine/browser/import-file'),
        );
        request.headers.set('origin', origin ?? server.httpEndpoint.origin);
        request.headers.contentType = ContentType.binary;
        request.headers.set(HttpHeaders.cookieHeader, cookie ?? session.cookie);
        request.headers.set('x-ub-csrf', csrf ?? session.csrf);
        request.headers.set(
          'x-ub-import',
          base64Encode(
            CanonicalObject([
              MapEntry('preview_id', CanonicalString(id.value)),
              MapEntry('name', CanonicalString(name)),
              MapEntry('mode', CanonicalString('clone')),
            ]).toBytes(),
          ),
        );
        request.contentLength = bytes.length;
        request.add(bytes);
        final response = await request.close();
        final body = BytesBuilder(copy: false);
        await for (final chunk in response) {
          body.add(chunk);
        }
        expect(response.statusCode, expectedStatus);
        if (response.statusCode != HttpStatus.ok) {
          expect(body.length, 0);
          return const EngineFailure(
            PolicyDeniedError(message: 'Request denied'),
          );
        }
        return EngineResult.fromWire(
          CanonicalValue.parseWireJson(utf8.decode(body.takeBytes())),
        );
      }

      await uploadFile(
        [1],
        OperationId.generate(),
        csrf: 'wrong',
        expectedStatus: HttpStatus.forbidden,
      );
      await uploadFile(
        [1],
        OperationId.generate(),
        origin: 'https://foreign.example',
        expectedStatus: HttpStatus.forbidden,
      );
      final writerFileSession = await exchange(
        await contributor.createBrowserSession(),
      );
      await uploadFile(
        [1],
        OperationId.generate(),
        cookie: writerFileSession.cookie,
        csrf: writerFileSession.csrf,
        expectedStatus: HttpStatus.forbidden,
      );
      final selectedId = OperationId.generate();
      final fileReview = await uploadFile(downloaded.bytes, selectedId);
      expect(fileReview, isA<EngineSuccess>());
      final fileFields = Map.fromEntries(
        ((fileReview as EngineSuccess).value as CanonicalObject).fields,
      );
      expect(wireString(fileFields['preview_id']!), selectedId.value);
      expect(wireString(fileFields['source_universe']!), universe.value);
      final retried = await uploadFile(downloaded.bytes, selectedId);
      expect(
        (retried as EngineSuccess).value.toText(),
        fileReview.value.toText(),
      );
      expect(
        await uploadFile(downloaded.bytes, selectedId, name: 'Changed name'),
        isA<EngineFailure>(),
      );
      expect(
        await uploadFile([1, 2, 3], OperationId.generate()),
        isA<EngineFailure>(),
      );

      // Content upload remains available to a browser without filesystem paths.
      final exported = '${root.path}/browser-upload.sqlite';
      await native.call(
        ExportLogicalEngineRequest(
          universe: Selector('Browser universe'),
          destination: exported,
          recordIds: [],
          completeHistory: true,
        ),
      );
      final archiveBytes = File(exported).readAsBytesSync();
      final inspectedArchive = local.OwnedSqliteDatabase.stageLogicalArchive(
        exported,
        root.path,
      );
      final archiveDigest = inspectedArchive.digest;
      inspectedArchive.close();
      final uploadId = OperationId.generate();
      final beginUpload = BeginArchiveUploadEngineRequest(
        uploadId: uploadId,
        digest: archiveDigest,
        bytes: archiveBytes.length,
      );
      expect(await call(session, beginUpload), isA<EngineSuccess>());
      var ordinal = 0;
      for (
        var start = 0;
        start < archiveBytes.length;
        start += ReadMoveChunkEngineRequest.chunkBytes
      ) {
        final end = (start + ReadMoveChunkEngineRequest.chunkBytes).clamp(
          0,
          archiveBytes.length,
        );
        expect(
          await call(
            session,
            WriteArchiveChunkEngineRequest(
              uploadId: uploadId,
              chunk: MoveArchiveChunk(
                ordinal: ordinal++,
                content: archiveBytes.sublist(start, end),
              ),
            ),
          ),
          isA<EngineSuccess>(),
        );
      }
      final review = await call(
        session,
        ReviewArchiveUploadEngineRequest(
          uploadId: uploadId,
          name: 'Browser clone',
          mode: ImportMode.clone,
        ),
      );
      expect(
        review,
        isA<EngineSuccess>(),
        reason: review is EngineFailure ? review.error.toWire().toText() : null,
      );
      final reviewFields = Map.fromEntries(
        ((review as EngineSuccess).value as CanonicalObject).fields,
      );
      expect(wireString(reviewFields['source_universe']!), universe.value);
      expect(
        wireString(reviewFields['target_universe']!),
        isNot(universe.value),
      );
      final catalogAfterUpload = Map.fromEntries(
        (await native.call(StatusEngineRequest()) as CanonicalObject).fields,
      );
      expect(
        (catalogAfterUpload['universes']! as CanonicalArray).items,
        hasLength(1),
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
