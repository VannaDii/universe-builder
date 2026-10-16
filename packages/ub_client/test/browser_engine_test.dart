import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/browser_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final token = 'a' * 43, csrf = 'b' * 43;
  final principal = ProfileId.parse('prf_000000000000000000000001');
  final welcome = EngineWelcome(
    protocolVersion: protocolVersion,
    serviceInstance: 'browser-test',
    principal: principal,
    author: true,
    maxFrameBytes: BigInt.from(maxFrameBytes),
    maxInFlight: BigInt.from(engineMaxInFlight),
  );
  BrowserEngineResponse response(CanonicalValue value) =>
      BrowserEngineResponse(status: 200, bytes: value.toBytes());
  BrowserEngineResponse enrollment() => response(
    CanonicalObject([
      MapEntry('welcome', welcome.toWire()),
      MapEntry('csrf', CanonicalString(csrf)),
      MapEntry('expires_at', CanonicalNumber('2208989700')),
    ]),
  );
  Matcher failure(LocalEngineFailure expected) => throwsA(
    isA<LocalEngineException>().having(
      (error) => error.failure,
      'failure',
      expected,
    ),
  );

  test('hosted assertion opens the ordinary session and billing stays separate from canon', () async {
    final paths = <String>[];
    final client = await BrowserEngineClient.connect(
      hostedAssertion: 'provider-assertion',
      abort: () {},
      post: (path, bytes, header) async {
        paths.add(path);
        if (path == '/engine/browser/sign-in') {
          expect(header, isNull);
          final fields = WireFields(
            CanonicalValue.parseWireJson(utf8.decode(bytes)),
            {'assertion'},
          );
          expect(fields.string('assertion'), 'provider-assertion');
          return enrollment();
        }
        expect(path, '/engine/browser/billing');
        expect(bytes, isEmpty);
        expect(header, csrf);
        return response(
          CanonicalObject([
            MapEntry('provider', CanonicalString('stub')),
            MapEntry('status', CanonicalString('not_configured')),
          ]),
        );
      },
    );
    expect(client.welcome.principal, principal);
    expect(await client.billingStatus(), (
      provider: 'stub',
      status: 'not_configured',
    ));
    expect(paths, ['/engine/browser/sign-in', '/engine/browser/billing']);
    await client.close();
  });

  test(
    'unconfigured hosted sign-in never falls back to another session action',
    () async {
      var aborted = 0;
      final paths = <String>[];
      Future<BrowserEngineResponse> unavailable(
        String path,
        Uint8List bytes,
        String? csrf,
      ) async {
        paths.add(path);
        return BrowserEngineResponse(status: 503, bytes: Uint8List(0));
      }

      await expectLater(
        BrowserEngineClient.connect(
          post: unavailable,
          abort: () => aborted++,
          hostedAssertion: 'assertion',
        ),
        failure(LocalEngineFailure.handshakeFailed),
      );
      expect(paths, ['/engine/browser/sign-in']);
      expect(aborted, 1);
      await expectLater(
        BrowserEngineClient.connect(
          post: unavailable,
          abort: () => aborted++,
          hostedAssertion: 'assertion',
          enrollmentToken: token,
        ),
        failure(LocalEngineFailure.handshakeFailed),
      );
      expect(paths, ['/engine/browser/sign-in']);
    },
  );

  test('browser calls preserve exact integers and Unicode, keep errors usable, and resume without replay', () async {
    final exact = CanonicalObject([
      MapEntry('large', CanonicalNumber('9007199254740993123456789')),
      MapEntry('source', CanonicalString('é😀\r\n')),
    ]);
    final requests = <EngineCall>[];
    final paths = <String>[];
    var aborted = 0;
    Future<BrowserEngineResponse> post(
      String path,
      Uint8List bytes,
      String? header,
    ) async {
      paths.add(path);
      if (path.endsWith('/exchange')) {
        expect(header, isNull);
        expect(
          WireFields(
            CanonicalValue.parseWireJson(String.fromCharCodes(bytes)),
            {'token'},
          ).string('token'),
          token,
        );
        return enrollment();
      }
      expect(header, csrf);
      if (path.endsWith('/hello')) {
        return response(welcome.toWire());
      }
      if (path.endsWith('/logout')) {
        return response(
          CanonicalObject([MapEntry('closed', CanonicalBool(true))]),
        );
      }
      final call = EngineCall.decode(bytes);
      requests.add(call);
      if (requests.length == 2) {
        return response(
          EngineReply(
            id: call.id,
            result: EngineFailure(
              PolicyDeniedError(message: 'Current rights required'),
            ),
          ).toWire(),
        );
      }
      return response(
        EngineReply(id: call.id, result: EngineSuccess(exact)).toWire(),
      );
    }

    final client = await BrowserEngineClient.connect(
      post: post,
      abort: () => aborted++,
      enrollmentToken: token,
    );
    expect(client.welcome.principal, principal);
    final command = StageSourceEngineRequest(
      universe: Selector('Mémoire 😀'),
      label: 'Original',
      text: 'é😀\r\n',
    );
    expect((await client.call(command)).toText(), exact.toText());
    expect(
      requests.single.request.toWire().toText(),
      command.toWire().toText(),
    );
    await expectLater(
      client.call(const StatusEngineRequest()),
      throwsA(isA<PolicyDeniedError>()),
    );
    expect(
      (await client.call(const StatusEngineRequest())).toText(),
      exact.toText(),
    );
    expect(requests.map((call) => call.id), [
      BigInt.one,
      BigInt.two,
      BigInt.from(3),
    ]);
    await client.close();
    expect(paths.where((path) => path.endsWith('/logout')), isEmpty);
    final resumed = await BrowserEngineClient.connect(
      post: post,
      abort: () => aborted++,
      resumeCsrf: csrf,
    );
    expect(resumed.welcome.principal, principal);
    expect(requests, hasLength(3));
    await resumed.logout();
    await expectLater(
      resumed.call(const StatusEngineRequest()),
      failure(LocalEngineFailure.closed),
    );
    expect(aborted, 2);
  });

  test('unknown transport outcomes and correlation failures require reconnect without replay', () async {
    for (final mismatch in [false, true]) {
      var calls = 0, aborted = 0;
      final client = await BrowserEngineClient.connect(
        enrollmentToken: token,
        abort: () => aborted++,
        post: (path, bytes, header) async {
          if (path.endsWith('/exchange')) return enrollment();
          calls++;
          if (!mismatch) throw StateError('Private transport text');
          return response(
            EngineReply(
              id: EngineCall.decode(bytes).id + BigInt.one,
              result: EngineSuccess(CanonicalNull()),
            ).toWire(),
          );
        },
      );
      await expectLater(
        client.call(const StatusEngineRequest()),
        failure(LocalEngineFailure.interrupted),
      );
      await expectLater(
        client.call(const StatusEngineRequest()),
        failure(LocalEngineFailure.reconnectRequired),
      );
      expect(calls, 1);
      expect(aborted, 1);
      await client.close();
    }
  });

  test('concurrent calls and logout are bounded to one request', () async {
    final waiting = Completer<BrowserEngineResponse>();
    EngineCall? call;
    final client = await BrowserEngineClient.connect(
      enrollmentToken: token,
      abort: () {},
      post: (path, bytes, header) async {
        if (path.endsWith('/exchange')) return enrollment();
        call = EngineCall.decode(bytes);
        return waiting.future;
      },
    );
    final first = client.call(const StatusEngineRequest());
    await expectLater(
      client.call(const StatusEngineRequest()),
      failure(LocalEngineFailure.busy),
    );
    await expectLater(client.logout(), failure(LocalEngineFailure.busy));
    waiting.complete(
      response(
        EngineReply(
          id: call!.id,
          result: EngineSuccess(CanonicalNull()),
        ).toWire(),
      ),
    );
    await first;
    await client.close();
  });

  test('incompatible and rejected session handshakes fail without private diagnostics', () async {
    for (final status in [401, 403, 200]) {
      await expectLater(
        BrowserEngineClient.connect(
          enrollmentToken: token,
          abort: () {},
          post: (_, _, _) async => BrowserEngineResponse(
            status: status,
            bytes: Uint8List.fromList('Private diagnostics'.codeUnits),
          ),
        ),
        failure(LocalEngineFailure.handshakeFailed),
      );
    }
  });
  test('archive preparation validates same-origin download metadata and never retries an unknown result', () async {
    var prepares = 0, invalid = false;
    final client = await BrowserEngineClient.connect(
      enrollmentToken: token,
      abort: () {},
      post: (path, bytes, header) async {
        if (path.endsWith('/exchange')) return enrollment();
        expect(header, csrf);
        expect(path, '/engine/browser/prepare-download');
        prepares++;
        expect(
          WireFields(
            CanonicalValue.parseWireJson(String.fromCharCodes(bytes)),
            {'universe'},
          ).require('universe').toText(),
          Selector('Campaign').toWire().toText(),
        );
        return response(
          CanonicalObject([
            MapEntry(
              'path',
              CanonicalString(
                invalid
                    ? 'https://foreign.example/archive'
                    : '/engine/browser/download/${'c' * 43}',
              ),
            ),
            MapEntry('digest', CanonicalString('d' * 64)),
            MapEntry('bytes', CanonicalNumber('900719925')),
            MapEntry(
              'manifest',
              CanonicalObject([MapEntry('name', CanonicalString('Campaign'))]),
            ),
          ]),
        );
      },
    );
    final prepared = await client.prepareArchiveDownload(Selector('Campaign'));
    expect(prepared.bytes, 900719925);
    expect(prepared.digest, 'd' * 64);
    invalid = true;
    await expectLater(
      client.prepareArchiveDownload(Selector('Campaign')),
      failure(LocalEngineFailure.interrupted),
    );
    await expectLater(
      client.prepareArchiveDownload(Selector('Campaign')),
      failure(LocalEngineFailure.reconnectRequired),
    );
    expect(prepares, 2);
    await client.close();
  });
  test('selected-file review returns protocol failures without admission and poisons unknown outcomes', () async {
    final client = await BrowserEngineClient.connect(
      enrollmentToken: token,
      abort: () {},
      post: (_, _, _) async => enrollment(),
    );
    await expectLater(
      client.reviewArchiveFile(
        upload: (header) async {
          expect(header, csrf);
          return response(const EngineFailure(ApprovalStaleError()).toWire());
        },
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
    final value = CanonicalObject([
      MapEntry('preview_id', CanonicalString(OperationId.generate().value)),
    ]);
    expect(
      (await client.reviewArchiveFile(
        upload: (_) async => response(EngineSuccess(value).toWire()),
      )).toText(),
      value.toText(),
    );
    await expectLater(
      client.reviewArchiveFile(
        upload: (_) async {
          throw StateError('Response lost');
        },
      ),
      failure(LocalEngineFailure.interrupted),
    );
    await expectLater(
      client.reviewArchiveFile(
        upload: (_) async => response(EngineSuccess(value).toWire()),
      ),
      failure(LocalEngineFailure.reconnectRequired),
    );
    await client.close();
  });
  test(
    'image staging returns known rejection and never replays an unknown upload',
    () async {
      var attempts = 0;
      final client = await BrowserEngineClient.connect(
        enrollmentToken: token,
        abort: () {},
        post: (_, _, _) async => enrollment(),
      );
      await expectLater(
        client.stageImageFile(
          upload: (header) async {
            attempts++;
            expect(header, csrf);
            return response(
              const EngineFailure(PolicyDeniedError(message: 'Invalid image'))
                  .toWire(),
            );
          },
        ),
        throwsA(isA<PolicyDeniedError>()),
      );
      await expectLater(
        client.stageImageFile(
          upload: (_) async {
            attempts++;
            throw StateError('Response lost');
          },
        ),
        failure(LocalEngineFailure.interrupted),
      );
      await expectLater(
        client.stageImageFile(
          upload: (_) async {
            attempts++;
            return response(const EngineSuccess(CanonicalNull()).toWire());
          },
        ),
        failure(LocalEngineFailure.reconnectRequired),
      );
      expect(attempts, 2);
      await client.close();
    },
  );
}
