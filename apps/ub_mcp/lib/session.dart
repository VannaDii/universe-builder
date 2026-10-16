import 'dart:async';
import 'dart:convert';

import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// The backend must release its connection when cancellation completes. Closing
/// that connection does not revoke mutations already admitted by the service.
typedef McpToolBackend = Future<CanonicalValue> Function(
  Request request,
  Future<void> cancelled,
);

/// UB's MCP lifecycle/dispatch, independent of byte transport. This is
/// application behavior, not a general MCP SDK. HTTP authorization and session
/// lifetime belong to its transport adapter; no authority is granted here.
final class McpSession {
  McpSession({
    required this.backend,
    required this.serverName,
    required this.serverVersion,
    this.fixture = false,
    this.advanced = false,
    this.streamableHttp = false,
  });
  final McpToolBackend backend;
  final String serverName, serverVersion;
  final bool fixture, advanced;
  final bool streamableHttp;
  final _active = <McpRequestId, Completer<void>>{};
  bool _initialized = false, _closed = false;

  /// Calls may run concurrently so pings and cancellation remain responsive.
  /// The byte transport serializes complete output frames. Stdio closes this
  /// session on EOF or failed framing/output. HTTP retains it across requests
  /// and disconnections, until explicit deletion, expiry or server shutdown.
  Future<CanonicalObject?> handle(
    CanonicalObject frame, {
    McpToolBackend? authenticatedBackend,
  }) async {
    if (_closed) throw const FormatException('MCP session closed');
    final invocation = McpInvocation.fromWire(frame);
    final id = invocation.id;
    if (id == null) {
      if (!_initialized) {
        close();
        throw const FormatException('Initialize request required');
      }
      if (invocation.method == 'notifications/cancelled') {
        final params = _params(invocation);
        final value = params['requestId'];
        if (value != null && value is! CanonicalNull) {
          final target = McpRequestId.fromWire(value);
          final cancellation = _active[target];
          if (cancellation != null && !cancellation.isCompleted) {
            cancellation.complete();
          }
        }
      }
      return null;
    }
    if (_active.containsKey(id)) {
      return _error(id, -32600, 'Request ID already in flight');
    }
    if (invocation.method == 'ping') {
      return mcpResultResponse(id, CanonicalObject([]));
    }
    if (!_initialized) {
      if (invocation.method != 'initialize') {
        close();
        throw const FormatException('Initialize request required');
      }
      try {
        final result = mcpInitializeResult(
          invocation.params ?? CanonicalObject([]),
          serverName: serverName,
          serverVersion: serverVersion,
          fixture: fixture,
          advanced: advanced,
          streamableHttp: streamableHttp,
        );
        _initialized = true;
        return mcpResultResponse(id, result);
      } on FormatException {
        close();
        return _error(id, -32602, 'Invalid initialize parameters');
      }
    }
    // The maintained SDK dispatches after the initialize response, without an
    // additional initialized-notification gate.
    if (invocation.method == 'tools/list') {
      final cursor = _params(invocation)['cursor'];
      if (cursor != null &&
          cursor is! CanonicalNull &&
          cursor is! CanonicalString) {
        return _error(id, -32602, 'Invalid cursor');
      }
      return _listTools(id, cursor is CanonicalString ? cursor.value : null);
    }
    if (invocation.method != 'tools/call') {
      return _error(id, -32601, invocation.method);
    }
    final params = _params(invocation);
    final name = params['name'];
    final args = params['arguments'];
    if (name is! CanonicalString ||
        (args != null && args is! CanonicalNull && args is! CanonicalObject)) {
      return _error(id, -32602, 'Invalid tool parameters');
    }
    late Request request;
    try {
      request = Request.fromTool(
        name.value,
        args is CanonicalObject ? args : CanonicalObject([]),
      );
    } on ProtocolError catch (error) {
      return mcpResultResponse(id, mcpProtocolToolError(error));
    }
    final cancellation = Completer<void>();
    _active[id] = cancellation;
    Future<CanonicalObject> execute() async {
      try {
        return mcpStructuredToolResult(
          await (authenticatedBackend ?? backend)(request, cancellation.future),
        );
      } on ProtocolError catch (error) {
        return mcpProtocolToolError(error);
      } on Object {
        // Raw transport/parser failures can contain source text or credentials.
        return mcpTextToolError(
          'Engine connection interrupted. Recover uncertain mutations using their original idempotency key.',
        );
      }
    }

    try {
      final result = await Future.any([
        execute(),
        cancellation.future.then((_) => mcpCancelledToolResult()),
      ]);
      return _closed
          ? null
          : mcpResultResponse(
              id,
              cancellation.isCompleted ? mcpCancelledToolResult() : result,
            );
    } finally {
      if (identical(_active[id], cancellation)) _active.remove(id);
    }
  }

  CanonicalObject _listTools(McpRequestId id, String? cursor) {
    final tools =
        (mcpToolsListResult(advanced: advanced).fields
                    .singleWhere((entry) => entry.key == 'tools')
                    .value
                as CanonicalArray)
            .items;
    final prefix = 'tools:${advanced ? 'advanced' : 'ordinary'}:';
    var start = 0;
    if (cursor != null) {
      final parsed = cursor.startsWith(prefix)
          ? int.tryParse(cursor.substring(prefix.length))
          : null;
      if (parsed == null ||
          parsed <= 0 ||
          parsed >= tools.length ||
          cursor != '$prefix$parsed') {
        return _error(id, -32602, 'Invalid cursor');
      }
      start = parsed;
    }
    CanonicalObject page(int end) => mcpResultResponse(
      id,
      CanonicalObject([
        MapEntry('tools', CanonicalArray(tools.sublist(start, end))),
        if (end < tools.length)
          MapEntry('nextCursor', CanonicalString('$prefix$end')),
      ]),
    );
    var end = start;
    while (end < tools.length &&
        utf8.encode(page(end + 1).toText()).length <= maxFrameBytes) {
      end++;
    }
    if (end == start) {
      return _error(id, -32603, 'Tool metadata exceeds the response limit');
    }
    return page(end);
  }

  /// No output is produced after close; backend cleanup is signalled once.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final cancellation in _active.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _active.clear();
  }
}

Map<String, CanonicalValue> _params(McpInvocation invocation) => {
  for (final entry
      in invocation.params?.fields ?? <MapEntry<String, CanonicalValue>>[])
    entry.key: entry.value,
};
CanonicalObject _error(McpRequestId id, int code, String message) =>
    CanonicalObject([
      MapEntry('jsonrpc', CanonicalString('2.0')),
      MapEntry('id', id.value),
      MapEntry(
        'error',
        CanonicalObject([
          MapEntry('code', CanonicalNumber(code.toString())),
          MapEntry('message', CanonicalString(message)),
        ]),
      ),
    ]);
