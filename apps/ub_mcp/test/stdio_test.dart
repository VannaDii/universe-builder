import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_mcp/stdio.dart';

import 'session_test.dart' show object, field, initialize, call, session;

void main() {
  test(
    'serves fragmented initialization and coalesced discovery/ping frames',
    () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final responses = StreamIterator(decodeMcpStdio(output.stream));
      final server = serveMcpStdio(
        input: input.stream,
        write: (bytes) async => output.add(bytes),
        session: session((_, _) async => object('{}')),
      );
      final init = encodeMcpStdio(initialize);
      for (final byte in init) {
        input.add([byte]);
      }
      expect(await responses.moveNext(), isTrue);
      expect(field(responses.current, 'id').toText(), '"init"');
      input.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":"list","method":"tools/list"}\n'
          '{"jsonrpc":"2.0","id":"ping","method":"ping"}\n',
        ),
      );
      expect(await responses.moveNext(), isTrue);
      expect(field(responses.current, 'id').toText(), '"list"');
      expect(await responses.moveNext(), isTrue);
      expect(field(responses.current, 'id').toText(), '"ping"');
      await input.close();
      expect(await server, isTrue);
      await responses.cancel();
      await output.close();
    },
  );

  test(
    'malformed input closes upstream and never reads a following mutation',
    () async {
      var readLater = false, closed = false, calls = 0;
      Stream<List<int>> hostile() async* {
        try {
          yield encodeMcpStdio(initialize);
          yield utf8.encode('{"id":1,"id":2}\n');
          readLater = true;
          yield encodeMcpStdio(call('3'));
        } finally {
          closed = true;
        }
      }

      expect(
        await serveMcpStdio(
          input: hostile(),
          write: (_) async {},
          session: session((_, _) async {
            calls++;
            return object('{}');
          }),
        ),
        isFalse,
      );
      expect(readLater, isFalse);
      expect(closed, isTrue);
      expect(calls, 0);
    },
  );

  test('retained call limit leaves ping and cancellation responsive', () async {
    final input = StreamController<List<int>>(),
        output = StreamController<List<int>>();
    final responses = StreamIterator(decodeMcpStdio(output.stream));
    var calls = 0;
    final server = serveMcpStdio(
      input: input.stream,
      write: (bytes) async => output.add(bytes),
      session: session((_, cancelled) async {
        calls++;
        await cancelled;
        return object('{}');
      }),
    );
    input.add(encodeMcpStdio(initialize));
    await responses.moveNext();
    for (var i = 1; i <= engineMaxInFlight + 1; i++) {
      input.add(encodeMcpStdio(call('$i')));
    }
    expect(await responses.moveNext(), isTrue);
    expect(field(responses.current, 'id').toText(), '${engineMaxInFlight + 1}');
    expect(responses.current.toText(), contains('EVALUATION_LIMIT_REACHED'));
    expect(calls, engineMaxInFlight);
    input.add(utf8.encode('{"jsonrpc":"2.0","id":"ping","method":"ping"}\n'));
    expect(await responses.moveNext(), isTrue);
    expect(field(responses.current, 'id').toText(), '"ping"');
    input.add(
      utf8.encode(
        '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}\n',
      ),
    );
    expect(await responses.moveNext(), isTrue);
    expect(responses.current.toText(), contains('Request cancelled.'));
    await input.close();
    expect(await server, isTrue);
    await responses.cancel();
    await output.close();
  });

  test(
    'failed output closes input and signals admitted backend cleanup',
    () async {
      final input = StreamController<List<int>>();
      final entered = Completer<void>(), cancelled = Completer<void>();
      var writes = 0;
      final server = serveMcpStdio(
        input: input.stream,
        write: (_) async {
          if (++writes > 1) throw StateError('output disconnected');
        },
        session: session((_, signal) async {
          entered.complete();
          await signal;
          cancelled.complete();
          return object('{}');
        }),
      );
      input.add(encodeMcpStdio(initialize));
      input.add(encodeMcpStdio(call('1')));
      await entered.future;
      input.add(utf8.encode('{"jsonrpc":"2.0","id":"ping","method":"ping"}\n'));
      expect(await server, isFalse);
      await cancelled.future;
      await input.close();
    },
  );
}
