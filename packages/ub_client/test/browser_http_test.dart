@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/browser_engine.dart';
import 'package:ub_client/browser_http.dart';
import 'package:ub_contracts/ub_contracts.dart';
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
}
