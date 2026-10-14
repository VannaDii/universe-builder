@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/browser_engine.dart';
import 'package:ub_client/browser_http.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'dart:convert';

import 'package:web/web.dart' as web;

@JS('globalThis.fetch')
external JSFunction get browserFetch;
@JS('globalThis.fetch')
external set browserFetch(JSFunction value);

void main() {
  late JSFunction originalFetch;
  setUp(() => originalFetch = browserFetch);
  tearDown(() => browserFetch = originalFetch);
  Matcher failure(LocalEngineFailure expected) => throwsA(
    isA<LocalEngineException>().having(
      (error) => error.failure,
      'failure',
      expected,
    ),
  );

  test(
    'browser HTTP keeps requests same-origin, opaque cookies, and exact bytes',
    () async {
      final bytes = Uint8List.fromList([0, 255, 1, 128]);
      var calls = 0;
      browserFetch = ((JSAny input, web.RequestInit init) {
        calls++;
        expect((input as JSString).toDart, '/engine/browser/call');
        expect(init.method, 'POST');
        expect(init.credentials, 'same-origin');
        expect(init.mode, 'same-origin');
        expect(init.redirect, 'error');
        expect(init.cache, 'no-store');
        expect((init.body as JSUint8Array).toDart, bytes);
        final headers = init.headers as web.Headers;
        expect(headers.get('content-type'), 'application/json');
        expect(headers.get('x-ub-csrf'), 'private-csrf');
        expect(headers.has('authorization'), isFalse);
        expect(headers.has('cookie'), isFalse);
        return Future.value(
          web.Response(bytes.toJS, web.ResponseInit(status: 200)),
        ).toJS;
      }).toJS;
      final transport = SameOriginBrowserTransport();
      final response = await transport.post(
        '/engine/browser/call',
        bytes,
        'private-csrf',
      );
      expect(response.status, 200);
      expect(response.bytes, bytes);
      await expectLater(
        transport.post(
          'https://foreign.example/engine/browser/call',
          bytes,
          null,
        ),
        failure(LocalEngineFailure.invalidRequest),
      );
      expect(calls, 1);
      transport.close();
      await expectLater(
        transport.post('/engine/browser/call', bytes, null),
        failure(LocalEngineFailure.closed),
      );
    },
  );

  test(
    'browser HTTP rejects oversized responses and aborts their stream',
    () async {
      web.AbortSignal? signal;
      browserFetch = ((JSAny input, web.RequestInit init) {
        signal = init.signal;
        return Future.value(
          web.Response(
            Uint8List(maxFrameBytes + 1).toJS,
            web.ResponseInit(status: 200),
          ),
        ).toJS;
      }).toJS;
      final transport = SameOriginBrowserTransport();
      await expectLater(
        transport.post('/engine/browser/hello', Uint8List(0), null),
        failure(LocalEngineFailure.interrupted),
      );
      expect(signal!.aborted, isTrue);
      transport.close();
    },
  );
  test('archive file fetch sends an opaque File body with bounded metadata and current CSRF', () async {
    final file = web.File(
      [
        Uint8List.fromList([1, 2, 3]).toJS,
      ].toJS,
      'archive.sqlite',
    );
    final id = OperationId.generate();
    browserFetch = ((JSAny input, web.RequestInit init) {
      expect((input as JSString).toDart, '/engine/browser/import-file');
      expect(init.body, same(file));
      expect(init.credentials, 'same-origin');
      expect(init.mode, 'same-origin');
      expect(init.redirect, 'error');
      final headers = init.headers as web.Headers;
      expect(headers.get('x-ub-csrf'), 'current-csrf');
      expect(headers.get('content-type'), 'application/octet-stream');
      final metadata = WireFields(
        CanonicalValue.parseWireJson(
          utf8.decode(base64Decode(headers.get('x-ub-import')!)),
        ),
        {'preview_id', 'name', 'mode'},
      );
      expect(metadata.string('preview_id'), id.value);
      expect(metadata.string('name'), 'Universe 記憶');
      expect(metadata.string('mode'), 'clone');
      expect(headers.has('authorization'), isFalse);
      return Future.value(
        web.Response(
          Uint8List.fromList([1, 2, 3]).toJS,
          web.ResponseInit(status: 200),
        ),
      ).toJS;
    }).toJS;
    final transport = SameOriginBrowserTransport();
    expect(
      (await transport.postArchive(
        file: file,
        previewId: id,
        name: 'Universe 記憶',
        mode: ImportMode.clone,
        csrf: 'current-csrf',
      )).bytes,
      [1, 2, 3],
    );
    transport.close();
  });
  test(
    'canceling a file transfer aborts fetch and requires a new transport',
    () async {
      final pending = Completer<web.Response>();
      web.AbortSignal? signal;
      browserFetch = ((JSAny _, web.RequestInit init) {
        signal = init.signal;
        signal!.addEventListener(
          'abort',
          ((web.Event _) {
            pending.completeError(StateError('Cancelled'));
          }).toJS,
        );
        return pending.future.toJS;
      }).toJS;
      final transport = SameOriginBrowserTransport();
      final future = transport.postArchive(
        file: web.File(
          [
            Uint8List.fromList([1]).toJS,
          ].toJS,
          'archive.sqlite',
        ),
        previewId: OperationId.generate(),
        name: 'Imported',
        mode: ImportMode.clone,
        csrf: 'current-csrf',
      );
      final result = expectLater(
        future,
        failure(LocalEngineFailure.interrupted),
      );
      transport.close();
      await result;
      expect(signal!.aborted, isTrue);
    },
  );
}
