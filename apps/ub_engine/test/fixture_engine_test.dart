@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_engine/engine_cli.dart';
import 'package:ub_client/fixture_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/fixture_engine.dart';

Request request(String tool, Map<String, Object?> args) => Request.fromTool(
  'universe_$tool',
  CanonicalValue.parseWireJson(
    jsonEncode({'universe': 'The Ashen Cycle', ...args}),
  ),
);
void main() {
  late Directory root;
  setUp(() {
    root = Directory('/tmp').createTempSync('ub-fixture-');
    privateDirectory(root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));
  test('engine runs fixture without installation or configuration and exits on parent EOF', () async {
    final input = StreamController<List<int>>();
    final errors = <String>[];
    final path = '${root.path}/fixture.sock';
    final running = runEngine(
      ['--fixture', '--socket', path, '--exit-on-stdin-close'],
      environment: {'UB_USE_POSTGRES': 'invalid'},
      output: (_) => fail('fixture must not print credentials'),
      error: errors.add,
      parentInput: input.stream,
    );
    FixtureEngineClient? client;
    try {
      for (var n = 0; n < 100; n++) {
        if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      client = await FixtureEngineClient.connect(path);
      final response = await client.call(
        request('describe', {'mode': 'summary'}),
      ) as DescribeResponse;
      expect(response.body.result.fixture, isTrue);
      expect(
        response.body.authorizationScope,
        'disposable-fixture/read-propose-only',
      );
      await client.close();
      await input.close();
      expect(await running.timeout(const Duration(seconds: 5)), 0);
      expect(errors, isEmpty);
      expect(root.listSync(), isEmpty);
    } finally {
      await client?.close();
      if (!input.isClosed) input.close().ignore();
      await running;
    }
  });
  test(
    'fixture options cannot open persistent installation or initialize it',
    () async {
      for (final args in [
        ['--fixture'],
        ['--socket', '${root.path}/socket'],
        [
          '--fixture',
          '--socket',
          '${root.path}/socket',
          '--installation',
          '${root.path}/installation',
        ],
        ['--fixture', '--socket', '${root.path}/socket', '--initialize'],
        ['--fixture', '--socket', '${root.path}/socket', '--http-only'],
        [
          '--installation',
          '${root.path}/installation',
          '--exit-on-stdin-close',
        ],
      ]) {
        expect(
          await runEngine(args, environment: {}, output: (_) {}, error: (_) {}),
          2,
        );
      }
      expect(root.listSync(), isEmpty);
    },
  );
  test('shared disposable state survives reconnect, typed failures preserve connection', () async {
    final path = '${root.path}/fixture.sock';
    final server = await FixtureEngineServer.start(path);
    final clients = <FixtureEngineClient>[];
    try {
      final first = await FixtureEngineClient.connect(path);
      clients.add(first);
      final opened = await first.call(
        request('open_context', {
          'continuity_id': 'cont_${'1'.padLeft(24, '0')}',
          'revision': {'kind': 'head'},
          'represented_context': 'rec_${'5a'.padLeft(24, '0')}',
          'temporal_query': {'kind': 'timeless'},
          'temporal_systems': [],
          'perspective': 'author',
        }),
      ) as OpenContextResponse;
      final context = opened.body.result.contextId.value;
      await first.close();
      final second = await FixtureEngineClient.connect(path);
      clients.add(second);
      await expectLater(
        second.call(
          request('get_state', {
            'context_id': context,
            'entity_ids': ['rec_${'a'.padLeft(24, '0')}'],
            'predicate_filters': [],
          }),
        ),
        throwsA(isA<UnsupportedSemanticsError>()),
      );
      expect(
        await second.call(request('describe', {'mode': 'summary'})),
        isA<DescribeResponse>(),
      );
      final results = await Future.wait(
        List.generate(8, (_) async {
          final client = await FixtureEngineClient.connect(path);
          clients.add(client);
          return client.call(
            request('search', {
              'context_id': context,
              'query': 'Mara',
              'typed_filters': {'record_kinds': <Object?>[]},
              'limit': 25,
            }),
          );
        }),
      );
      expect(
        results.every(
          (r) => r is SearchResponse && r.body.result.hits.length == 1,
        ),
        isTrue,
      );
      await expectLater(FixtureEngineServer.start(path), throwsFormatException);
    } finally {
      for (final c in clients) {
        await c.close();
      }
      await server.close();
    }
    expect(
      FileSystemEntity.typeSync(path, followLinks: false),
      FileSystemEntityType.notFound,
    );
  });
  test('fixture handshake, cancellation and duplicate correlation are enforced on the wire', () async {
    final path = '${root.path}/fixture.sock';
    final server = await FixtureEngineServer.start(path);
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final frames = StreamIterator(decodeLengthPrefixedFrames(socket));
    try {
      socket.add(
        encodeLengthPrefixedFrame(
          const Hello(
            protocolVersion: protocolVersion,
            fixture: true,
          ).toWire().toBytes(),
        ),
      );
      await socket.flush();
      expect(
        await frames.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final welcome = HelloReply.decode(frames.current);
      expect(welcome.fixture, isTrue);
      expect(welcome.maxInFlight, BigInt.from(16));
      final describe = request('describe', {'mode': 'summary'});
      // Coalesced cancellation is observed before queued request admission.
      socket.add([
        ...encodeLengthPrefixedFrame(
          ClientRequestMessage(
            id: BigInt.one,
            request: describe,
          ).toWire().toBytes(),
        ),
        ...encodeLengthPrefixedFrame(
          ClientCancelMessage(id: BigInt.one).toWire().toBytes(),
        ),
        ...encodeLengthPrefixedFrame(
          ClientRequestMessage(
            id: BigInt.two,
            request: describe,
          ).toWire().toBytes(),
        ),
      ]);
      await socket.flush();
      expect(
        await frames.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(ServerMessage.decode(frames.current).id, BigInt.two);
      socket.add(
        encodeLengthPrefixedFrame(
          ClientRequestMessage(
            id: BigInt.two,
            request: describe,
          ).toWire().toBytes(),
        ),
      );
      await socket.flush();
      expect(
        await frames.moveNext().timeout(const Duration(seconds: 5)),
        isFalse,
      );
    } finally {
      socket.destroy();
      await frames.cancel();
      await server.close();
    }
  });
  test(
    'occupied files are retained and replaced endpoints are never removed',
    () async {
      final path = '${root.path}/fixture.sock';
      File(path).writeAsStringSync('retained');
      await expectLater(FixtureEngineServer.start(path), throwsFormatException);
      expect(File(path).readAsStringSync(), 'retained');
      File(path).deleteSync();
      final server = await FixtureEngineServer.start(path);
      File(path).deleteSync();
      File(path).writeAsStringSync('replacement');
      await expectLater(server.close(), throwsA(isA<FileSystemException>()));
      expect(File(path).readAsStringSync(), 'replacement');
    },
  );
}
