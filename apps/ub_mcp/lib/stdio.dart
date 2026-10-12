import 'dart:async';

import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'session.dart';

/// Bound input before decoding, keep controls responsive, and serialize whole
/// output frames. Retained calls including blocked output are bounded by the
/// engine's advertised in-flight capacity; excess calls receive its limit code.
Future<bool> serveMcpStdio({
  required Stream<List<int>> input,
  required Future<void> Function(List<int>) write,
  required McpSession session,
}) async {
  final frames = StreamIterator(decodeMcpStdio(input));
  final pending = <Future<void>>{};
  var closed = false, failed = false;
  Future<void> tail = Future.value();
  Future<void> stop() async {
    failed = true;
    closed = true;
    session.close();
    await frames.cancel();
  }

  Future<void> send(CanonicalObject? response) async {
    if (response == null || closed) return;
    final next = tail.then((_) async {
      if (!closed) await write(encodeMcpStdio(response));
    });
    tail = next;
    await next;
  }

  Future<void> dispatch(CanonicalObject frame) async {
    try {
      await send(await session.handle(frame));
    } on Object {
      await stop();
    }
  }

  try {
    while (!closed && await frames.moveNext()) {
      final frame = frames.current;
      final invocation = McpInvocation.fromWire(frame);
      if (invocation.id != null && invocation.method == 'tools/call') {
        if (pending.length >= engineMaxInFlight) {
          await send(
            mcpResultResponse(
              invocation.id!,
              mcpProtocolToolError(
                const EvaluationLimitReachedError(
                  message: 'MCP in-flight capacity reached',
                ),
              ),
            ),
          );
          continue;
        }
        final task = dispatch(frame);
        pending.add(task);
        unawaited(task.then((_) => pending.remove(task)));
      } else {
        await dispatch(frame);
      }
    }
  } on Object {
    failed = true;
  } finally {
    closed = true;
    session.close();
    await frames.cancel();
    await Future.wait(pending.toList());
  }
  return !failed;
}
