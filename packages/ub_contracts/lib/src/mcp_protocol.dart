import 'package:ub_domain/ub_domain.dart';

import 'mcp_metadata.dart';
import 'protocol_error.dart';

const mcpStdioProtocolVersion = '2025-11-25';
const _supportedProtocolVersions = {
  '2024-11-05',
  '2025-03-26',
  '2025-06-18',
  mcpStdioProtocolVersion,
};

/// MCP correlation IDs follow the maintained SDK's signed-i64/string contract,
/// independently of the engine's u64 IDs. BigInt avoids browser rounding.
final class McpRequestId {
  McpRequestId._(this.value);
  final CanonicalValue value;
  factory McpRequestId.fromWire(CanonicalValue value) {
    if (value is CanonicalString) return McpRequestId._(value);
    if (value is CanonicalNumber &&
        RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value.digits)) {
      final number = BigInt.parse(value.digits);
      if (number >= BigInt.parse('-9223372036854775808') &&
          number <= BigInt.parse('9223372036854775807')) {
        return McpRequestId._(CanonicalNumber(number.toString()));
      }
    }
    throw const FormatException('MCP ID must be a string or signed i64');
  }

  @override
  bool operator ==(Object other) =>
      other is McpRequestId && value.toText() == other.value.toText();
  @override
  int get hashCode => value.toText().hashCode;
}

/// Request or notification envelope only. Application DTOs remain closed and
/// are parsed separately; MCP extension fields do not relax those DTOs.
final class McpInvocation {
  McpInvocation._(this.id, this.method, this.params);
  final McpRequestId? id;
  final String method;
  final CanonicalObject? params;
  factory McpInvocation.fromWire(CanonicalObject object) {
    final fields = _fields(object);
    if (_string(fields['jsonrpc']) != '2.0') {
      throw const FormatException('MCP requires JSON-RPC 2.0');
    }
    final method = _string(fields['method']);
    final params = fields['params'];
    if (params != null &&
        params is! CanonicalNull &&
        params is! CanonicalObject) {
      throw const FormatException('MCP parameters must be an object');
    }
    return McpInvocation._(
      fields.containsKey('id') ? McpRequestId.fromWire(fields['id']!) : null,
      method,
      params is CanonicalObject ? params : null,
    );
  }
}

/// Initialize over stdio uses the supported protocol negotiation: honor a known
/// handshake version, otherwise return 2025-11-25. Streamable HTTP excludes the
/// older 2024-11-05 transport while preserving the stdio negotiation contract.
/// Lifecycle admission belongs to the adapter, not these result constructors.
CanonicalObject mcpInitializeResult(
  CanonicalObject params, {
  required String serverName,
  required String serverVersion,
  bool fixture = false,
  bool advanced = false,
  bool streamableHttp = false,
}) {
  final fields = _fields(params);
  final requested = _string(fields['protocolVersion']);
  _object(fields['capabilities']);
  final client = _fields(_object(fields['clientInfo']));
  _string(client['name']);
  _string(client['version']);
  return CanonicalObject([
    MapEntry(
      'protocolVersion',
      CanonicalString(
        _supportedProtocolVersions.contains(requested) &&
                (!streamableHttp || requested != '2024-11-05')
            ? requested
            : mcpStdioProtocolVersion,
      ),
    ),
    MapEntry(
      'capabilities',
      CanonicalObject([MapEntry('tools', CanonicalObject([]))]),
    ),
    MapEntry(
      'serverInfo',
      CanonicalObject([
        MapEntry('name', CanonicalString(serverName)),
        MapEntry('version', CanonicalString(serverVersion)),
      ]),
    ),
    MapEntry(
      'instructions',
      CanonicalString(mcpInstructions(fixture: fixture, advanced: advanced)),
    ),
  ]);
}

/// One complete page, as in the maintained adapter. Internal contract names are
/// mapped to MCP schema keys without changing the embedded schema contents.
CanonicalObject mcpToolsListResult({bool advanced = false}) => CanonicalObject([
  MapEntry(
    'tools',
    CanonicalArray(
      mcpToolSchemas(advanced: advanced).items.map((value) {
        final fields = _fields(value as CanonicalObject);
        return CanonicalObject([
          MapEntry('name', fields['name']!),
          MapEntry('description', fields['description']!),
          MapEntry('inputSchema', fields['input_schema']!),
          MapEntry('outputSchema', fields['output_schema']!),
        ]);
      }),
    ),
  ),
]);

/// Stdio results retain structured content and its exact JSON text form.
/// Protocol failures are tool errors, not JSON-RPC transport errors.
CanonicalObject mcpStructuredToolResult(
  CanonicalValue value, {
  bool isError = false,
}) => CanonicalObject([
  MapEntry('content', _textContent(value.toText())),
  MapEntry('structuredContent', value),
  MapEntry('isError', CanonicalBool(isError)),
]);

CanonicalObject mcpProtocolToolError(ProtocolError error) =>
    mcpStructuredToolResult(error.toWire(), isError: true);

CanonicalObject mcpTextToolError(String message) => CanonicalObject([
  MapEntry('content', _textContent(message)),
  const MapEntry('isError', CanonicalBool(true)),
]);

CanonicalObject mcpCancelledToolResult() => mcpTextToolError(
  'Request cancelled. Recover admitted mutations using their original idempotency key.',
);

CanonicalObject mcpResultResponse(McpRequestId id, CanonicalObject result) =>
    CanonicalObject([
      MapEntry('jsonrpc', CanonicalString('2.0')),
      MapEntry('id', id.value),
      MapEntry('result', result),
    ]);

CanonicalArray _textContent(String text) => CanonicalArray([
  CanonicalObject([
    MapEntry('type', CanonicalString('text')),
    MapEntry('text', CanonicalString(text)),
  ]),
]);
Map<String, CanonicalValue> _fields(CanonicalObject object) => {
  for (final entry in object.fields) entry.key: entry.value,
};
String _string(CanonicalValue? value) => switch (value) {
  CanonicalString(:final value) => value,
  _ => throw const FormatException('Expected MCP string'),
};
CanonicalObject _object(CanonicalValue? value) => switch (value) {
  CanonicalObject() => value,
  _ => throw const FormatException('Expected MCP object'),
};
