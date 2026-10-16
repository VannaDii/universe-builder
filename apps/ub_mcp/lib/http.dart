import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ub_contracts/mcp.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'session.dart';

/// Returned only after the host verifies token issuer, expiry, scope and the
/// exact resource audience. The key binds installation and principal; neither
/// the token nor the HTTP client may supply a trusted identity directly.
final class McpHttpPrincipal {
  McpHttpPrincipal({required this.key, required this.backend});
  final String key;
  final McpToolBackend backend;
}

typedef McpHttpAuthenticate = Future<McpHttpPrincipal?> Function(
  String bearerToken,
  Uri resource,
);

final class _HttpSession {
  _HttpSession(this.principal, this.protocol, this.dispatcher, this.touched);
  final String principal, protocol;
  final McpSession dispatcher;
  DateTime touched;
}

/// Mount on an existing HTTPS listener. Authentication is mandatory and owned
/// by the host integration; this adapter never interprets an access token or
/// grants author rights. GET streams and replay are optional and not offered.
/// A disconnected POST continues; only explicit cancellation/session closure
/// signals cancellation. Clients recover uncertain mutations through UB.
final class McpHttpHandler {
  McpHttpHandler({
    required this.resource,
    required Iterable<Uri> authorizationServers,
    required this.authenticate,
    required this.serverVersion,
    Iterable<String> allowedOrigins = const [],
    this.advanced = false,
    this.now = DateTime.now,
  }) : authorizationServers = List.unmodifiable(authorizationServers),
       allowedOrigins = Set.unmodifiable(allowedOrigins) {
    final local = {'127.0.0.1', 'localhost', '::1'}.contains(resource.host);
    if ((!resource.isScheme('https') &&
            !(local && resource.isScheme('http'))) ||
        resource.userInfo.isNotEmpty ||
        resource.host.isEmpty ||
        resource.hasQuery ||
        resource.hasFragment ||
        resource.path.isEmpty ||
        resource.path == '/' ||
        this.authorizationServers.isEmpty ||
        this.authorizationServers.any(
          (u) =>
              !u.isScheme('https') ||
              u.host.isEmpty ||
              u.userInfo.isNotEmpty ||
              u.hasFragment ||
              u.hasQuery,
        ) ||
        this.allowedOrigins.any((origin) => !_validOrigin(origin))) {
      throw ArgumentError(
        'Supply an HTTPS MCP resource, issuers and exact allowed origins',
      );
    }
    metadata = resource.replace(
      path: '/.well-known/oauth-protected-resource${resource.path}',
    );
  }
  final Uri resource;
  late final Uri metadata;
  final List<Uri> authorizationServers;
  final Set<String> allowedOrigins;
  final McpHttpAuthenticate authenticate;
  final String serverVersion;
  final bool advanced;
  final DateTime Function() now;
  final _random = Random.secure();
  final _sessions = <String, _HttpSession>{};
  int _reading = 0, _calls = 0, _initializing = 0;
  bool _closed = false;
  static const _versions = {'2025-03-26', '2025-06-18', '2025-11-25'};
  static const _lifetime = Duration(minutes: 15);

  /// False means that the outer router owns this path. All responses on an
  /// owned path are completed here, including authorization failures.
  Future<bool> handle(HttpRequest request) async {
    if (request.uri.path != resource.path &&
        request.uri.path != metadata.path) {
      return false;
    }
    final response = request.response;
    StreamIterator<List<int>>? bodyReader;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      final origins = request.headers['Origin'];
      final hosts = request.headers[HttpHeaders.hostHeader];
      final host = hosts?.length == 1 ? hosts!.single : null;
      final authority = host == null
          ? null
          : Uri.tryParse('${resource.scheme}://$host');
      if (authority == null ||
          authority.host.isEmpty ||
          authority.userInfo.isNotEmpty ||
          authority.hasQuery ||
          authority.hasFragment ||
          authority.path.isNotEmpty ||
          authority.origin != resource.origin ||
          (origins != null &&
              (origins.length != 1 ||
                  !allowedOrigins.contains(origins.single)))) {
        await _finish(response, HttpStatus.forbidden);
        return true;
      }
      if (_closed) {
        await _finish(response, HttpStatus.serviceUnavailable);
        return true;
      }
      if (request.uri.hasQuery) {
        await _finish(response, HttpStatus.badRequest);
        return true;
      }
      if (request.uri.path == metadata.path) {
        if (request.method != 'GET') {
          await _method(response, 'GET');
        } else {
          await _json(
            response,
            CanonicalObject([
              MapEntry('resource', CanonicalString(resource.toString())),
              MapEntry(
                'authorization_servers',
                CanonicalArray(
                  authorizationServers.map(
                    (u) => CanonicalString(u.toString()),
                  ),
                ),
              ),
              MapEntry(
                'bearer_methods_supported',
                CanonicalArray([CanonicalString('header')]),
              ),
            ]),
          );
        }
        return true;
      }
      final authorizations = request.headers[HttpHeaders.authorizationHeader];
      final authorization = authorizations?.length == 1
          ? authorizations!.single
          : null;
      final match = authorization == null
          ? null
          : RegExp(
              r'^Bearer +([A-Za-z0-9\-._~+/]+=*)$',
              caseSensitive: false,
            ).firstMatch(authorization);
      final principal = match == null
          ? null
          : await authenticate(match.group(1)!, resource);
      if (principal == null || principal.key.isEmpty) {
        response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer resource_metadata="${metadata.toString()}"',
        );
        await _finish(response, HttpStatus.unauthorized);
        return true;
      }
      if (_closed) {
        await _finish(response, HttpStatus.serviceUnavailable);
        return true;
      }
      final now = this.now().toUtc();
      for (final id in _sessions.keys.toList()) {
        if (now.difference(_sessions[id]!.touched) >= _lifetime) {
          _sessions.remove(id)!.dispatcher.close();
        }
      }
      final ids = request.headers['MCP-Session-Id'];
      final versions = request.headers['MCP-Protocol-Version'];
      if ((ids != null && ids.length != 1) ||
          (versions != null && versions.length != 1)) {
        await _finish(response, HttpStatus.badRequest);
        return true;
      }
      final id = ids?.single;
      final session = id == null ? null : _sessions[id];
      if (id != null &&
          (session == null || session.principal != principal.key)) {
        await _finish(response, HttpStatus.notFound);
        return true;
      }
      final version = versions?.single ?? session?.protocol;
      if (version != null &&
          (!_versions.contains(version) ||
              (session != null && version != session.protocol))) {
        await _finish(response, HttpStatus.badRequest);
        return true;
      }
      if (session != null) {
        session.touched = now;
      }
      if (request.method == 'DELETE') {
        if (id == null) {
          await _finish(response, HttpStatus.badRequest);
        } else {
          _sessions.remove(id)!.dispatcher.close();
          await _finish(response, HttpStatus.noContent);
        }
        return true;
      }
      if (request.method != 'POST') {
        await _method(response, 'POST, DELETE');
        return true;
      }
      final accept = request.headers[HttpHeaders.acceptHeader]?.join(',') ?? '';
      final media = accept
          .split(',')
          .map((s) => s.trim().split(';').first)
          .toSet();
      if (!media.contains('application/json') ||
          !media.contains('text/event-stream')) {
        await _finish(response, HttpStatus.notAcceptable);
        return true;
      }
      final content = request.headers.contentType;
      if (content?.mimeType != 'application/json' ||
          (content?.charset != null &&
              content!.charset!.toLowerCase() != 'utf-8')) {
        await _finish(response, HttpStatus.unsupportedMediaType);
        return true;
      }
      if (_reading >= maxInFlight) {
        await _finish(response, HttpStatus.tooManyRequests);
        return true;
      }
      CanonicalObject frame;
      _reading++;
      try {
        if (request.contentLength > maxFrameBytes) {
          throw const _TooLarge();
        }
        final bytes = BytesBuilder(copy: false);
        bodyReader = StreamIterator(request);
        while (await bodyReader.moveNext().timeout(
          const Duration(seconds: 30),
        )) {
          final chunk = bodyReader.current;
          if (bytes.length + chunk.length > maxFrameBytes) {
            throw const _TooLarge();
          }
          bytes.add(chunk);
        }
        final body = bytes.takeBytes();
        if (body.length >= 3 &&
            body[0] == 0xef &&
            body[1] == 0xbb &&
            body[2] == 0xbf) {
          throw const FormatException('BOM');
        }
        final value = CanonicalValue.parseWireJson(utf8.decode(body));
        if (value is! CanonicalObject) {
          throw const FormatException('Single object required');
        }
        frame = value;
      } finally {
        _reading--;
      }
      if (session != null && !identical(_sessions[id], session)) {
        await _finish(response, HttpStatus.notFound);
        return true;
      }
      final invocation = McpInvocation.fromWire(frame);
      if (session == null) {
        if (invocation.method != 'initialize' || invocation.id == null) {
          await _finish(response, HttpStatus.badRequest);
          return true;
        }
        if (_sessions.length + _initializing >= maxInFlight) {
          await _finish(response, HttpStatus.tooManyRequests);
          return true;
        }
        final dispatcher = McpSession(
          backend: (_, _) async => throw StateError('Authentication required'),
          serverName: 'universe-mcp',
          serverVersion: serverVersion,
          advanced: advanced,
          streamableHttp: true,
        );
        CanonicalObject? result;
        _initializing++;
        try {
          result = await dispatcher.handle(frame);
        } finally {
          _initializing--;
        }
        if (_closed) {
          dispatcher.close();
          await _finish(response, HttpStatus.serviceUnavailable);
          return true;
        }
        final fields = {
          for (final field in result!.fields) field.key: field.value,
        };
        if (fields['result'] case final CanonicalObject initialized) {
          final protocol = wireString(
            initialized.fields
                .singleWhere((e) => e.key == 'protocolVersion')
                .value,
          );
          final token = base64Url
              .encode(List.generate(32, (_) => _random.nextInt(256)))
              .replaceAll('=', '');
          _sessions[token] = _HttpSession(
            principal.key,
            protocol,
            dispatcher,
            now,
          );
          response.headers.set('MCP-Session-Id', token);
        } else {
          dispatcher.close();
        }
        await _json(response, result);
        return true;
      }
      if (invocation.method == 'initialize') {
        await _finish(response, HttpStatus.badRequest);
        return true;
      }
      final tool = invocation.method == 'tools/call' && invocation.id != null;
      if (tool && _calls >= maxInFlight) {
        await _finish(response, HttpStatus.tooManyRequests);
        return true;
      }
      if (tool) {
        _calls++;
      }
      try {
        final result = await session.dispatcher.handle(
          frame,
          authenticatedBackend: principal.backend,
        );
        if (result == null) {
          await _finish(
            response,
            invocation.id == null ? HttpStatus.accepted : HttpStatus.notFound,
          );
        } else {
          await _json(response, result);
        }
      } finally {
        if (tool) {
          _calls--;
        }
      }
    } on _TooLarge {
      response.persistentConnection = false;
      await _finish(response, HttpStatus.requestEntityTooLarge);
    } on FormatException {
      await _finish(response, HttpStatus.badRequest);
    } on TimeoutException {
      await _finish(response, HttpStatus.requestTimeout);
    } on Object {
      // Do not expose token verifier, source, socket or backend error text.
      try {
        await _finish(response, HttpStatus.serviceUnavailable);
      } on Object {
        /* The peer may already have disconnected. */
      }
    } finally {
      // Send rejection before cancelling an incomplete body: cancelling the
      // HttpRequest first can destroy its socket before the status is flushed.
      await bodyReader?.cancel();
    }
    return true;
  }

  void close() {
    _closed = true;
    for (final session in _sessions.values) {
      session.dispatcher.close();
    }
    _sessions.clear();
  }
}

final class _TooLarge implements Exception {
  const _TooLarge();
}

bool _validOrigin(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      {'https', 'http'}.contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.origin == value;
}

Future<void> _finish(HttpResponse response, int status) async {
  response.statusCode = status;
  await response.close();
}

Future<void> _method(HttpResponse response, String allow) async {
  response.headers.set(HttpHeaders.allowHeader, allow);
  await _finish(response, HttpStatus.methodNotAllowed);
}

Future<void> _json(HttpResponse response, CanonicalObject value) async {
  final bytes = utf8.encode(value.toText());
  if (bytes.length > maxFrameBytes) {
    await _finish(response, HttpStatus.requestEntityTooLarge);
    return;
  }
  response.headers.contentType = ContentType.json;
  response.add(bytes);
  await response.close();
}
