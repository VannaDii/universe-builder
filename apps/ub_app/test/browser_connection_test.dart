@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_app/connection_browser.dart';
import 'package:ub_client/browser_commitment_recovery.dart';
import 'package:ub_client/browser_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS('globalThis.fetch')
external JSFunction get browserFetch;
@JS('globalThis.fetch')
external set browserFetch(JSFunction value);

void main() {
  test('browser app wires recovery, sequences calls and resumes only a short-lived session', () async {
    final originalFetch = browserFetch;
    const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const csrf = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final principal = ProfileId.generate();
    final welcome = EngineWelcome(
      protocolVersion: protocolVersion,
      serviceInstance: 'app-test',
      principal: principal,
      author: false,
      maxFrameBytes: BigInt.from(maxFrameBytes),
      maxInFlight: BigInt.from(engineMaxInFlight),
    );
    final paths = <String>[];
    var active = 0, largest = 0, revoked = false;
    final exact = CanonicalObject([
      MapEntry('exact', CanonicalNumber('18446744073709551615')),
      MapEntry('source', CanonicalString('記憶 😀\r\n')),
    ]);
    Future<web.Response> handle(String path, web.RequestInit init) async {
      paths.add(path);
      expect(init.credentials, 'same-origin');
      expect(init.mode, 'same-origin');
      final headers = init.headers as web.Headers;
      expect(headers.has('authorization'), isFalse);
      if (revoked) return web.Response(null, web.ResponseInit(status: 401));
      late CanonicalValue result;
      if (path.endsWith('/exchange')) {
        expect(headers.get('x-ub-csrf'), isNull);
        final input = CanonicalValue.parseWireJson(
          String.fromCharCodes((init.body as JSUint8Array).toDart),
        );
        expect(WireFields(input, {'token'}).string('token'), token);
        result = CanonicalObject([
          MapEntry('welcome', welcome.toWire()),
          MapEntry('csrf', CanonicalString(csrf)),
          MapEntry('expires_at', CanonicalNumber('2208989700')),
        ]);
      } else {
        expect(headers.get('x-ub-csrf'), csrf);
        if (path.endsWith('/hello')) {
          result = welcome.toWire();
        } else if (path.endsWith('/logout')) {
          revoked = true;
          result = CanonicalObject([MapEntry('closed', CanonicalBool(true))]);
        } else {
          active++;
          if (active > largest) largest = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          final call = EngineCall.decode((init.body as JSUint8Array).toDart);
          result = EngineReply(
            id: call.id,
            result: EngineSuccess(exact),
          ).toWire();
          active--;
        }
      }
      return web.Response(result.toBytes().toJS, web.ResponseInit(status: 200));
    }

    browserFetch = ((JSAny input, web.RequestInit init) => handle(
      (input as JSString).toDart,
      init,
    ).toJS).toJS;
    final device = DeviceConnection([])..browserEnrollmentToken = token;
    final context = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: principal,
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: 'browser-connection-test',
    );
    final form = UnfinishedCommitmentForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'browser-connection-test',
      parties: [CommitmentPartyInput(record: 'unfinished', role: '記憶 😀')],
      deadline: TemporalValidityInput(
        start: TemporalBoundInput(value: '18446744073709551615'),
      ),
    );
    try {
      web.window.sessionStorage.removeItem('ub-browser-session-csrf');
      final session = await device.connect();
      expect(device.browserEnrollmentToken, isNull);
      expect(session.author, isFalse);
      expect(session.principal, principal);
      expect(session.backupFile, isNull);
      expect(
        (await session.saveCommitmentForm(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      final results = await Future.wait([
        session.call(StatusEngineRequest()),
        session.call(StatusEngineRequest()),
      ]);
      expect(results.map((v) => v.toText()), [exact.toText(), exact.toText()]);
      expect(largest, 1);
      await session.close();
      final store = await BrowserCommitmentFormRecoveryStore.open();
      try {
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          form.toWire().toText(),
        );
      } finally {
        store.close();
      }
      final resumed = await DeviceConnection([]).connect();
      expect(paths.where((p) => p.endsWith('/exchange')).length, 1);
      expect(paths.where((p) => p.endsWith('/hello')).length, 1);
      expect(
        web.window.sessionStorage.getItem('ub-browser-session-csrf'),
        csrf,
      );
      await resumed.logout!();
      expect(
        web.window.sessionStorage.getItem('ub-browser-session-csrf'),
        isNull,
      );
      await expectLater(
        DeviceConnection([]).connect(),
        throwsA(isA<LocalEngineException>()),
      );
      expect(paths.where((p) => p.endsWith('/call')).length, 2);
    } finally {
      browserFetch = originalFetch;
      web.window.sessionStorage.removeItem('ub-browser-session-csrf');
      final request = web.window.indexedDB.deleteDatabase(
        'ub-commitment-editor-recovery',
      );
      final done = Completer<void>();
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Test cleanup failed'),
      )).toJS;
      await done.future;
    }
  });
}
