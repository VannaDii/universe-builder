import 'dart:async';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_mcp/session.dart';

CanonicalObject object(String value) =>
    CanonicalValue.parseWireJson(value) as CanonicalObject;
CanonicalValue field(CanonicalObject value, String key) =>
    value.fields.singleWhere((e) => e.key == key).value;
final initialize = object(
  '{"jsonrpc":"2.0","id":"init","method":"initialize","params":'
  '{"protocolVersion":"2025-11-25","capabilities":{},'
  '"clientInfo":{"name":"test","version":"1"}}}',
);
CanonicalObject call(String id, {String tool = 'universe_describe'}) => object(
  '{"jsonrpc":"2.0","id":$id,"method":"tools/call",'
  '"params":{"name":"$tool","arguments":{"universe":"Test","mode":"summary"}}}',
);
McpSession session(McpToolBackend backend, {bool advanced = false}) =>
    McpSession(
      backend: backend,
      serverName: 'universe-mcp',
      serverVersion: '0.1.0',
      advanced: advanced,
    );

void main() {
  test(
    'advanced discovery and protocol errors do not invoke the backend',
    () async {
      var called = false;
      final server = session((_, _) async {
        called = true;
        return object('{}');
      }, advanced: true);
      await server.handle(initialize);
      final response = await server.handle(
        object('{"jsonrpc":"2.0","id":1,"method":"tools/list"}'),
      );
      expect(
        (field(
          field(response!, 'result') as CanonicalObject,
          'tools',
        ) as CanonicalArray).items.length,
        16,
      );
      for (final (method, params, code) in [
        ('unknown/method', '{}', '-32601'),
        ('tools/list', '{"cursor":3}', '-32602'),
        ('tools/call', '{"name":false}', '-32602'),
        ('tools/call', '{"name":"universe_describe","arguments":[]}', '-32602'),
      ]) {
        final result = await server.handle(
          object(
            '{"jsonrpc":"2.0","id":1,"method":"$method","params":$params}',
          ),
        );
        expect(
          field(field(result!, 'error') as CanonicalObject, 'code').toText(),
          code,
        );
      }
      expect(called, isFalse);
      server.close();
    },
  );
  test(
    'pre-init ping, initialize then direct discovery without notification gate',
    () async {
      final server = session(
        (_, _) async => throw StateError('not a tool call'),
      );
      final pong = await server.handle(
        object('{"jsonrpc":"2.0","id":9223372036854775807,"method":"ping"}'),
      );
      expect(field(pong!, 'id').toText(), '9223372036854775807');
      expect(field(pong, 'result').toText(), '{}');
      expect(
        field((await server.handle(initialize))!, 'id').toText(),
        '"init"',
      );
      final listed = await server.handle(
        object(
          '{"jsonrpc":"2.0","id":"list","method":"tools/list","params":{"cursor":"ignored"}}',
        ),
      );
      final result = field(listed!, 'result') as CanonicalObject;
      expect((field(result, 'tools') as CanonicalArray).items.length, 11);
      expect(
        await server.handle(
          object('{"jsonrpc":"2.0","method":"notifications/initialized"}'),
        ),
        isNull,
      );
      server.close();
    },
  );

  test(
    'pre-init wrong message closes lifecycle without admitting a tool',
    () async {
      var admitted = false;
      for (final frame in [
        call('1'),
        object('{"jsonrpc":"2.0","method":"notifications/initialized"}'),
      ]) {
        final server = session((_, _) async {
          admitted = true;
          return object('{}');
        });
        await expectLater(server.handle(frame), throwsFormatException);
        await expectLater(server.handle(initialize), throwsFormatException);
      }
      expect(admitted, isFalse);
    },
  );

  test(
    'malformed initialization returns invalid params and closes session',
    () async {
      final server = session((_, _) async => object('{}'));
      final response = await server.handle(
        object('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'),
      );
      expect(
        field(field(response!, 'error') as CanonicalObject, 'code').toText(),
        '-32602',
      );
      await expectLater(server.handle(initialize), throwsFormatException);
    },
  );

  test(
    'routes closed public DTOs and returns exact structured backend values',
    () async {
      Request? received;
      final server = session((request, _) async {
        received = request;
        return object(
          '{"n":18446744073709551615,"decimal":1.00000000000000000001}',
        );
      });
      await server.handle(initialize);
      final response = await server.handle(call('"tool-😀"'));
      expect(received, isA<DescribeSummaryRequest>());
      expect(field(response!, 'id').toText(), '"tool-😀"');
      final result = field(response, 'result') as CanonicalObject;
      expect(
        field(result, 'structuredContent').toText(),
        '{"decimal":1.00000000000000000001,"n":18446744073709551615}',
      );
      expect(field(result, 'isError').toText(), 'false');
      server.close();
    },
  );

  test(
    'invalid application arguments never call backend and remain tool errors',
    () async {
      var count = 0;
      final server = session((_, _) async {
        count++;
        return object('{}');
      });
      await server.handle(initialize);
      for (final args in ['{}', '{"universe":"Test","owner_approve":true}']) {
        final response = await server.handle(
          object(
            '{"jsonrpc":"2.0","id":1,"method":"tools/call",'
            '"params":{"name":"universe_describe","arguments":$args}}',
          ),
        );
        final result = field(response!, 'result') as CanonicalObject;
        expect(field(result, 'isError').toText(), 'true');
        expect(
          field(
            field(result, 'structuredContent') as CanonicalObject,
            'code',
          ).toText(),
          '"INVALID_ARGUMENT"',
        );
      }
      expect(count, 0);
      server.close();
    },
  );

  test(
    'current service denials are structured; raw failures are redacted',
    () async {
      final server = session((_, _) async {
        throw const PolicyDeniedError(message: 'Current grant denied');
      });
      await server.handle(initialize);
      final denied =
          field((await server.handle(call('1')))!, 'result') as CanonicalObject;
      expect(
        field(
          field(denied, 'structuredContent') as CanonicalObject,
          'code',
        ).toText(),
        '"POLICY_DENIED"',
      );
      server.close();
      final broken = session(
        (_, _) async => throw StateError('password=secret source text'),
      );
      await broken.handle(initialize);
      final result = field((await broken.handle(call('1')))!, 'result');
      expect(result.toText(), isNot(contains('secret')));
      expect(result.toText(), contains('original idempotency key'));
      broken.close();
    },
  );

  test('in-flight cancellation stays responsive and keeps numeric/string IDs distinct', () async {
    final entered = Completer<void>(), completed = Completer<CanonicalValue>();
    var signalled = false;
    final server = session((_, cancelled) {
      entered.complete();
      cancelled.then((_) {
        signalled = true;
      });
      return completed.future;
    });
    await server.handle(initialize);
    final pending = server.handle(call('1'));
    await entered.future;
    final duplicate = await server.handle(call('1'));
    expect(
      field(field(duplicate!, 'error') as CanonicalObject, 'code').toText(),
      '-32600',
    );
    await server.handle(
      object(
        '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"1"}}',
      ),
    );
    expect(signalled, isFalse);
    expect(
      await server.handle(
        object('{"jsonrpc":"2.0","id":"ping","method":"ping"}'),
      ),
      isNotNull,
    );
    await server.handle(
      object(
        '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}',
      ),
    );
    final cancelled = field((await pending)!, 'result');
    expect(signalled, isTrue);
    expect(
      cancelled.toText(),
      contains('Request cancelled. Recover admitted mutations'),
    );
    completed.complete(object('{"published":true}'));
    await Future<void>.delayed(Duration.zero);
    server.close();
  });

  test(
    'disconnect signals backend cleanup and suppresses late output',
    () async {
      final entered = Completer<void>(), complete = Completer<CanonicalValue>();
      var cancelled = false;
      final server = session((_, signal) {
        entered.complete();
        signal.then((_) {
          cancelled = true;
        });
        return complete.future;
      });
      await server.handle(initialize);
      final pending = server.handle(call('1'));
      await entered.future;
      server.close();
      server.close();
      expect(await pending, isNull);
      expect(cancelled, isTrue);
      complete.complete(object('{}'));
      await Future<void>.delayed(Duration.zero);
      await expectLater(server.handle(call('2')), throwsFormatException);
    },
  );
}
