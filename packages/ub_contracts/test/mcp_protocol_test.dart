import 'package:test/test.dart';
import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalObject object(String text) =>
    CanonicalValue.parseWireJson(text) as CanonicalObject;
CanonicalValue field(CanonicalObject value, String key) =>
    value.fields.singleWhere((entry) => entry.key == key).value;

void main() {
  test('MCP IDs retain signed limits, Unicode strings and distinct types', () {
    for (final token in [
      '-9223372036854775808',
      '9223372036854775807',
      '9007199254740993',
      '"é😀"',
      '""',
      '"1"',
      '1',
    ]) {
      final id = McpRequestId.fromWire(CanonicalValue.parseWireJson(token));
      expect(id.value.toText(), token);
      expect(field(mcpResultResponse(id, object('{}')), 'id').toText(), token);
    }
    expect(
      McpRequestId.fromWire(const CanonicalNumber('-0')),
      McpRequestId.fromWire(const CanonicalNumber('0')),
    );
    expect(
      McpRequestId.fromWire(CanonicalString('1')),
      isNot(McpRequestId.fromWire(const CanonicalNumber('1'))),
    );
    for (final token in [
      '9223372036854775808',
      '-9223372036854775809',
      '18446744073709551615',
      '1.0',
      '1e0',
      'null',
      'true',
      '{}',
      '[]',
    ]) {
      expect(
        () => McpRequestId.fromWire(CanonicalValue.parseWireJson(token)),
        throwsFormatException,
        reason: token,
      );
    }
  });

  test(
    'request and notification envelopes retain exact arguments and metadata',
    () {
      final request = McpInvocation.fromWire(
        object(
          '{"jsonrpc":"2.0","id":"request-1","method":"tools/call",'
          '"params":{"name":"universe_get","arguments":{"n":18446744073709551615},'
          '"_meta":{"progressToken":"a"}},"extension":true}',
        ),
      );
      expect(request.id!.value.toText(), '"request-1"');
      expect(request.method, 'tools/call');
      expect(
        field(request.params!, 'arguments').toText(),
        '{"n":18446744073709551615}',
      );
      expect(field(request.params!, '_meta').toText(), '{"progressToken":"a"}');
      final notification = McpInvocation.fromWire(
        object('{"jsonrpc":"2.0","method":"notifications/initialized"}'),
      );
      expect(notification.id, isNull);
      expect(notification.params, isNull);
      for (final text in [
        '{"method":"ping"}',
        '{"jsonrpc":"1.0","method":"ping"}',
        '{"jsonrpc":"2.0","method":1}',
        '{"jsonrpc":"2.0","method":"ping","id":null}',
        '{"jsonrpc":"2.0","method":"ping","params":[]}',
        '{"jsonrpc":"2.0","id":1,"result":{}}',
      ]) {
        expect(
          () => McpInvocation.fromWire(object(text)),
          throwsFormatException,
        );
      }
    },
  );

  test('initialization honors known handshake versions and falls back otherwise', () {
    for (final requested in [
      '2024-11-05',
      '2025-03-26',
      '2025-06-18',
      '2025-11-25',
      '2026-07-28',
      'unknown',
    ]) {
      final result = mcpInitializeResult(
        object(
          '{"protocolVersion":"$requested","capabilities":{},'
          '"clientInfo":{"name":"test","version":"1","title":"Test"}}',
        ),
        serverName: 'universe-mcp',
        serverVersion: '0.1.0',
      );
      expect(
        field(result, 'protocolVersion').toText(),
        '"${requested == 'unknown' || requested == '2026-07-28' ? '2025-11-25' : requested}"',
      );
      expect(field(result, 'capabilities').toText(), '{"tools":{}}');
      expect(
        field(result, 'serverInfo').toText(),
        '{"name":"universe-mcp","version":"0.1.0"}',
      );
      expect(
        (field(result, 'instructions') as CanonicalString).value,
        mcpInstructions(),
      );
      expect(result.fields.any((f) => f.key == 'resultType'), isFalse);
    }
  });

  test(
    'initialization refuses missing or malformed mandatory client information',
    () {
      for (final text in [
        '{}',
        '{"protocolVersion":1,"capabilities":{},"clientInfo":{}}',
        '{"protocolVersion":"2025-11-25","capabilities":[],"clientInfo":{"name":"x","version":"1"}}',
        '{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"x"}}',
      ]) {
        expect(
          () => mcpInitializeResult(
            object(text),
            serverName: 'test',
            serverVersion: '1',
          ),
          throwsFormatException,
        );
      }
      final fixture = mcpInitializeResult(
        object(
          '{"protocolVersion":"2025-11-25","capabilities":{},'
          '"clientInfo":{"name":"test","version":"1"}}',
        ),
        serverName: 'test',
        serverVersion: '1',
        fixture: true,
        advanced: true,
      );
      expect(
        (field(fixture, 'instructions') as CanonicalString).value,
        mcpInstructions(fixture: true, advanced: true),
      );
    },
  );

  test(
    'tools/list maps schema keys exactly with one complete discovery page',
    () {
      for (final advanced in [false, true]) {
        final result = mcpToolsListResult(advanced: advanced);
        expect(result.fields.map((e) => e.key), ['tools']);
        final tools = (field(result, 'tools') as CanonicalArray).items;
        final source = mcpToolSchemas(advanced: advanced).items;
        expect(tools.length, advanced ? 16 : 11);
        for (var i = 0; i < tools.length; i++) {
          final tool = tools[i] as CanonicalObject;
          final schema = source[i] as CanonicalObject;
          expect(tool.fields.map((e) => e.key).toSet(), {
            'name',
            'description',
            'inputSchema',
            'outputSchema',
          });
          for (final (from, to) in [
            ('name', 'name'),
            ('description', 'description'),
            ('input_schema', 'inputSchema'),
            ('output_schema', 'outputSchema'),
          ]) {
            expect(field(tool, to).toText(), field(schema, from).toText());
          }
        }
      }
    },
  );

  test('structured results retain exact content and protocol error bodies', () {
    final body = object(
      '{"n":18446744073709551615,"amount":0.000000000000000001}',
    );
    final result = mcpStructuredToolResult(body);
    expect(field(result, 'isError').toText(), 'false');
    expect(field(result, 'structuredContent').toText(), body.toText());
    final text =
        ((field(result, 'content') as CanonicalArray).items.single
            as CanonicalObject);
    expect(field(text, 'type').toText(), '"text"');
    expect((field(text, 'text') as CanonicalString).value, body.toText());
    const error = InvalidArgumentError(field: 'universe', message: 'required');
    final failure = mcpProtocolToolError(error);
    expect(field(failure, 'isError').toText(), 'true');
    expect(
      field(failure, 'structuredContent').toText(),
      error.toWire().toText(),
    );
    final cancelled = mcpCancelledToolResult();
    expect(cancelled.fields.any((f) => f.key == 'structuredContent'), isFalse);
    expect(field(cancelled, 'isError').toText(), 'true');
    expect(
      (field(
        (field(cancelled, 'content') as CanonicalArray).items.single
            as CanonicalObject,
        'text',
      ) as CanonicalString).value,
      'Request cancelled. Recover admitted mutations using their original idempotency key.',
    );
  });
}
