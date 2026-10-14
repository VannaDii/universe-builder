import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart'
    show privateDirectory, protectedFile;
import 'package:ub_store/sqlite.dart' show OwnedSqliteDatabase;
import 'package:ub_store/ub_store.dart' show maxImageBytes;

import 'postgres_runtime.dart';
import 'sqlite_runtime.dart';

typedef _HttpConnection = ({
  EngineWelcome welcome,
  Future<CanonicalValue> Function(EngineRequest) execute,
  void Function() close,
});

/// Transport ownership is separate from runtime/storage ownership. Closing the
/// listener drains admitted calls; the caller then closes its runtime/store.
/// Native requests use the existing profile hello. Explicitly enrolled browser
/// sessions retain that hello only in this process, recheck it on every call,
/// and require a same-origin request with a CSRF token. Mutations are not replayed.
final class LoopbackEngineServer {
  LoopbackEngineServer._(
    this._server,
    this._connect,
    this._now,
    this._webFiles,
  );
  final HttpServer _server;
  final Map<String, File> _webFiles;
  final DateTime Function() _now;
  final _enrollments = <String, ({EngineHello hello, DateTime expires})>{};
  final _browserSessions =
      <String, ({EngineHello hello, DateTime expires, String csrf})>{};
  final _downloads =
      <
        String,
        ({
          String session,
          DateTime expires,
          Directory directory,
          File file,
          UniverseId universe,
        })
      >{};
  void _expireDownloads() {
    final expired = _downloads.entries
        .where(
          (entry) =>
              !entry.value.expires.isAfter(_now()) ||
              !_browserSessions.containsKey(entry.value.session),
        )
        .map((entry) => entry.key)
        .toList();
    for (final token in expired) {
      final download = _downloads.remove(token)!;
      download.directory.deleteSync(recursive: true);
    }
  }

  String get _cookieName => 'ub_browser_${_server.port}';
  String _token() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  void _expireBrowserAccess() {
    final now = _now();
    _enrollments.removeWhere((_, value) => !value.expires.isAfter(now));
    _browserSessions.removeWhere((_, value) => !value.expires.isAfter(now));
    _expireDownloads();
  }

  final Future<_HttpConnection> Function(EngineHello) _connect;
  late final StreamSubscription<HttpRequest> _subscription;
  final _active = <Future<void>>{};
  final _done = Completer<void>();
  bool _stopping = false;
  Future<void>? _shutdown;
  DateTime _lastActive = DateTime.now();
  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');
  Future<void> get done => _done.future;
  bool get isIdle => _active.isEmpty;
  DateTime get lastActive => _lastActive;

  static Future<LoopbackEngineServer> sqlite(
    NativeSqliteRuntime runtime, {
    DateTime Function()? now,
    String? webAssets,
  }) => _bind(
    (hello) async {
      final connection = runtime.connect(hello);
      return (
        welcome: connection.welcome,
        execute: connection.execute,
        close: connection.close,
      );
    },
    now: now,
    webAssets: webAssets,
  );

  static Future<LoopbackEngineServer> postgres(
    NativePostgresRuntime runtime, {
    DateTime Function()? now,
    String? webAssets,
  }) => _bind(
    (hello) async {
      final connection = await runtime.connect(hello);
      return (
        welcome: connection.welcome,
        execute: connection.execute,
        close: connection.close,
      );
    },
    now: now,
    webAssets: webAssets,
  );

  static Future<LoopbackEngineServer> _bind(
    Future<_HttpConnection> Function(EngineHello) connect, {
    DateTime Function()? now,
    String? webAssets,
  }) async {
    final files = <String, File>{};
    if (webAssets != null) {
      final directory = Directory(webAssets);
      if (!directory.isAbsolute || !directory.existsSync()) {
        throw const FileSystemException('Web assets unavailable');
      }
      final root = Directory(directory.resolveSymbolicLinksSync());
      for (final entry in root.listSync(recursive: true, followLinks: false)) {
        if (entry is File) {
          final relative = entry.path
              .substring(root.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/');
          files['/$relative'] = entry;
        }
      }
      if (!files.containsKey('/index.html')) {
        throw const FileSystemException('Web entry point unavailable');
      }
      files['/'] = files['/index.html']!;
    }
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener.idleTimeout = const Duration(seconds: 60);
    final server = LoopbackEngineServer._(
      listener,
      connect,
      now ?? DateTime.now,
      files,
    );
    server._subscription = listener.listen(server._accept);
    return server;
  }

  void _accept(HttpRequest request) {
    _lastActive = DateTime.now();
    if (_stopping || _active.length >= 32) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.close().ignore();
      return;
    }
    final task = _serve(request);
    _active.add(task);
    task.whenComplete(() {
      _active.remove(task);
      _lastActive = DateTime.now();
    }).ignore();
  }

  Future<void> _serve(HttpRequest request) async {
    _HttpConnection? connection;
    var shutdown = false;
    try {
      final response = request.response;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final origin = request.headers.value('origin');
      if (request.headers.value(HttpHeaders.hostHeader) != endpoint.authority ||
          origin != null && origin != endpoint.origin) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.method == 'POST' &&
          {
            '/engine/browser/import-file',
            '/engine/browser/image-file',
          }.contains(request.uri.path)) {
        final image = request.uri.path == '/engine/browser/image-file';
        _expireBrowserAccess();
        if (request.uri.hasQuery ||
            origin != endpoint.origin ||
            request.headers.contentType?.mimeType !=
                'application/octet-stream') {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        final cookies = request.cookies.where(
          (cookie) => cookie.name == _cookieName,
        );
        final session = cookies.length == 1
            ? _browserSessions[cookies.single.value]
            : null;
        if (session == null) {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
        if (request.headers.value('x-ub-csrf') != session.csrf) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        try {
          connection = await _connect(session.hello);
        } on Object {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
        if (!connection.welcome.author) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        final header = request.headers.value(
          image ? 'x-ub-image' : 'x-ub-import',
        );
        if (header == null || header.length > 8192) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        final metadata = WireFields(
          CanonicalValue.parseWireJson(utf8.decode(base64Decode(header))),
          image
              ? {'universe', 'original_name'}
              : {'preview_id', 'name', 'mode'},
        );
        final EngineRequest Function(String path) command;
        final String filename;
        if (image) {
          final universe = Selector.fromWire(metadata.require('universe'));
          filename = metadata.string('original_name');
          if (filename.isEmpty ||
              utf8.encode(filename).length > 255 ||
              filename == '.' ||
              filename == '..' ||
              filename.contains('/') ||
              filename.contains('\\') ||
              filename.runes.any((r) => r <= 31 || r >= 127 && r <= 159)) {
            response.statusCode = HttpStatus.badRequest;
            return;
          }
          command = (path) =>
              StageImageEngineRequest(universe: universe, source: path);
        } else {
          final id = OperationId.parse(metadata.string('preview_id'));
          final name = metadata.string('name'),
              mode = ImportMode.fromName(metadata.string('mode'));
          filename = 'archive.sqlite';
          command = (path) => PreviewImportEngineRequest(
            source: path,
            name: name,
            mode: mode,
            previewId: id,
          );
        }
        final limit = image
            ? maxImageBytes
            : ReadMoveChunkEngineRequest.chunkBytes *
                  ReadMoveChunkEngineRequest.maxChunks;
        if (request.contentLength > limit || request.contentLength == 0) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        final directory = Directory.systemTemp.createTempSync(
          image
              ? 'universe-builder-browser-image-'
              : 'universe-builder-browser-import-',
        );
        try {
          privateDirectory(directory.path);
          final file = File('${directory.path}/$filename');
          protectedFile(file.path, createNew: true);
          var bytes = 0;
          final output = file.openWrite();
          try {
            await for (final chunk in request.timeout(
              const Duration(seconds: 30),
            )) {
              bytes += chunk.length;
              if (bytes > limit) {
                response.statusCode = HttpStatus.requestEntityTooLarge;
                return;
              }
              output.add(chunk);
              await output.flush();
            }
          } finally {
            await output.close();
          }
          if (bytes == 0 ||
              request.contentLength >= 0 && bytes != request.contentLength) {
            response.statusCode = HttpStatus.badRequest;
            return;
          }
          EngineResult result;
          try {
            result = EngineSuccess(
              await connection.execute(command(file.path)),
            );
          } on ProtocolError catch (error) {
            result = EngineFailure(error);
          } on Object {
            result = EngineFailure(
              PolicyDeniedError(
                message: image
                    ? 'Image staging unavailable'
                    : 'Package import unavailable',
              ),
            );
          }
          response.headers.contentType = ContentType.json;
          response.add(result.toWire().toBytes());
        } finally {
          directory.deleteSync(recursive: true);
        }
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path.startsWith('/engine/browser/download/')) {
        _expireBrowserAccess();
        if (request.uri.hasQuery || request.uri.pathSegments.length != 4) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        final token = request.uri.pathSegments.last;
        final cookies = request.cookies.where(
          (cookie) => cookie.name == _cookieName,
        );
        final download = _downloads[token];
        if (cookies.length != 1 ||
            download == null ||
            cookies.single.value != download.session) {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
        final session = _browserSessions[download.session]!;
        try {
          connection = await _connect(session.hello);
        } on Object {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
        if (!connection.welcome.author) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        final status = await connection.execute(
          const StatusEngineRequest(),
        ) as CanonicalObject;
        final universes =
            Map.fromEntries(status.fields)['universes']! as CanonicalArray;
        if (!universes.items.any(
          (row) =>
              WireFields(row, {'id', 'name'}).string('id') ==
              download.universe.value,
        )) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        if (_downloads[token] != download) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        _downloads.remove(token); // One-use URL, bound to this browser session.
        try {
          response.headers.contentType = ContentType.binary;
          response.headers.set(
            'content-disposition',
            'attachment; filename="Universe Builder archive.sqlite"',
          );
          response.headers.set('x-content-type-options', 'nosniff');
          response.headers.set('cross-origin-resource-policy', 'same-origin');
          response.contentLength = await download.file.length();
          await response.addStream(download.file.openRead());
        } finally {
          download.directory.deleteSync(recursive: true);
        }
        return;
      }
      if (request.method == 'GET' || request.method == 'HEAD') {
        final segments = request.uri.pathSegments;
        if (segments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        )) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        final path = '/${segments.join('/')}';
        final file = path.startsWith('/engine/') ? null : _webFiles[path];
        if (file == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        response.headers.set('x-content-type-options', 'nosniff');
        response.headers.set('cross-origin-resource-policy', 'same-origin');
        response.headers.contentType = switch (path.split('.').last) {
          'html' => ContentType.html,
          'js' => ContentType('text', 'javascript', charset: 'utf-8'),
          'css' => ContentType('text', 'css', charset: 'utf-8'),
          'json' => ContentType.json,
          'wasm' => ContentType('application', 'wasm'),
          'png' => ContentType('image', 'png'),
          'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
          'svg' => ContentType('image', 'svg+xml'),
          'ico' => ContentType('image', 'x-icon'),
          'ttf' => ContentType('font', 'ttf'),
          'otf' => ContentType('font', 'otf'),
          'woff' => ContentType('font', 'woff'),
          'woff2' => ContentType('font', 'woff2'),
          _ => path == '/' ? ContentType.html : ContentType.binary,
        };
        response.contentLength = await file.length();
        if (request.method == 'GET') await response.addStream(file.openRead());
        return;
      }
      if (request.method != 'POST' ||
          request.uri.hasQuery ||
          !{
            '/engine/hello',
            '/engine/call',
            '/engine/browser-grant',
            '/engine/browser/exchange',
            '/engine/browser/hello',
            '/engine/browser/call',
            '/engine/browser/logout',
            '/engine/browser/prepare-download',
          }.contains(request.uri.path)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final path = request.uri.path;
      final browser = path.startsWith('/engine/browser/');
      EngineHello? nativeHello;
      if (!browser) {
        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        if (authorization == null ||
            !authorization.startsWith('UB ') ||
            authorization.length > 8192) {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
        try {
          nativeHello = EngineHello.decode(
            base64Decode(authorization.substring(3)),
          );
          connection = await _connect(nativeHello);
        } on Object {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
      }
      final input = BytesBuilder(copy: false);
      await for (final bytes in request.timeout(const Duration(seconds: 5))) {
        if (input.length + bytes.length > maxFrameBytes) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        input.add(bytes);
      }
      CanonicalValue value;
      _expireBrowserAccess();
      EngineHello hello;
      String? browserId;
      if (browser) {
        // Browser requests must carry the exact origin, even when no credentials
        // are present. The native routes retain their existing header behavior.
        if (origin != endpoint.origin ||
            request.headers.contentType?.mimeType != 'application/json') {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        if (path == '/engine/browser/exchange') {
          final fields = WireFields(
            CanonicalValue.parseWireJson(utf8.decode(input.takeBytes())),
            {'token'},
          );
          final enrollment = _enrollments.remove(fields.string('token'));
          if (enrollment == null) {
            response.statusCode = HttpStatus.unauthorized;
            return;
          }
          hello = enrollment.hello;
        } else {
          final cookies = request.cookies.where(
            (cookie) => cookie.name == _cookieName,
          );
          if (cookies.length != 1) {
            response.statusCode = HttpStatus.unauthorized;
            return;
          }
          browserId = cookies.single.value;
          final session = _browserSessions[browserId];
          if (session == null) {
            response.statusCode = HttpStatus.unauthorized;
            return;
          }
          if (request.headers.value('x-ub-csrf') != session.csrf) {
            response.statusCode = HttpStatus.forbidden;
            return;
          }
          hello = session.hello;
          if (path == '/engine/browser/logout') {
            if (input.length != 0) {
              response.statusCode = HttpStatus.badRequest;
              return;
            }
            _browserSessions.remove(browserId);
            _expireDownloads();
            response.cookies.add(
              Cookie(_cookieName, '')
                ..httpOnly = true
                ..sameSite = SameSite.strict
                ..path = '/engine/browser'
                ..maxAge = 0,
            );
            response.headers.contentType = ContentType.json;
            response.add(
              CanonicalObject([MapEntry('closed', const CanonicalBool(true))])
                  .toBytes(),
            );
            return;
          }
        }
      } else {
        hello = nativeHello!;
      }
      if (browser) {
        try {
          connection = await _connect(hello);
        } on Object {
          response.statusCode = HttpStatus.unauthorized;
          return;
        }
      }
      final authenticated = connection!;
      if (path == '/engine/browser/prepare-download') {
        if (!authenticated.welcome.author) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        final fields = WireFields(
          CanonicalValue.parseWireJson(utf8.decode(input.takeBytes())),
          {'universe'},
        );
        final selector = Selector.fromWire(fields.require('universe'));
        final directory = Directory.systemTemp.createTempSync(
          'universe-builder-browser-download-',
        );
        var retained = false;
        try {
          privateDirectory(directory.path);
          final file = File('${directory.path}/archive.sqlite');
          final manifest = await authenticated.execute(
            ExportLogicalEngineRequest(
              universe: selector,
              destination: file.path,
              recordIds: [],
              completeHistory: true,
            ),
          ) as CanonicalObject;
          final archive = OwnedSqliteDatabase.stageLogicalArchive(
            file.path,
            directory.path,
          );
          late String digest;
          try {
            digest = archive.digest;
          } finally {
            archive.close();
          }
          if (_stopping || !_browserSessions.containsKey(browserId)) {
            response.statusCode = HttpStatus.unauthorized;
            return;
          }
          // A session owns at most one unused download snapshot.
          final previous = _downloads.entries
              .where((entry) => entry.value.session == browserId)
              .map((entry) => entry.key)
              .toList();
          for (final old in previous) {
            _downloads.remove(old)!.directory.deleteSync(recursive: true);
          }
          final token = _token();
          _downloads[token] = (
            session: browserId!,
            expires: _now().add(const Duration(minutes: 5)),
            directory: directory,
            file: file,
            universe: UniverseId.parse(
              wireString(Map.fromEntries(manifest.fields)['universe']!),
            ),
          );
          retained = true;
          value = CanonicalObject([
            MapEntry(
              'path',
              CanonicalString('/engine/browser/download/$token'),
            ),
            MapEntry('digest', CanonicalString(digest)),
            MapEntry('bytes', CanonicalNumber('${await file.length()}')),
            MapEntry('manifest', manifest),
          ]);
        } finally {
          if (!retained) directory.deleteSync(recursive: true);
        }
      } else if (path == '/engine/browser-grant') {
        if (input.length != 0) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        if (_enrollments.length + _browserSessions.length >= 256) {
          response.statusCode = HttpStatus.serviceUnavailable;
          return;
        }
        final token = _token(),
            expires = _now().add(const Duration(minutes: 1));
        _enrollments[token] = (hello: hello, expires: expires);
        value = CanonicalObject([
          MapEntry('enrollment_token', CanonicalString(token)),
          MapEntry(
            'expires_at',
            CanonicalNumber('${expires.millisecondsSinceEpoch ~/ 1000}'),
          ),
        ]);
      } else if (path == '/engine/browser/exchange') {
        if (_browserSessions.length >= 256) {
          response.statusCode = HttpStatus.serviceUnavailable;
          return;
        }
        final id = _token(),
            csrf = _token(),
            expires = _now().add(const Duration(minutes: 15));
        _browserSessions[id] = (hello: hello, csrf: csrf, expires: expires);
        response.cookies.add(
          Cookie(_cookieName, id)
            ..httpOnly = true
            ..sameSite = SameSite.strict
            ..path = '/engine/browser'
            ..maxAge = 900,
        );
        value = CanonicalObject([
          MapEntry('welcome', authenticated.welcome.toWire()),
          MapEntry('csrf', CanonicalString(csrf)),
          MapEntry(
            'expires_at',
            CanonicalNumber('${expires.millisecondsSinceEpoch ~/ 1000}'),
          ),
        ]);
      } else if ({'/engine/hello', '/engine/browser/hello'}.contains(path)) {
        if (input.length != 0) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        value = authenticated.welcome.toWire();
      } else {
        final call = EngineCall.decode(input.takeBytes());
        EngineResult result;
        try {
          if (browser &&
              (call.request is BackupEngineRequest ||
                  call.request is RestoreEngineRequest ||
                  call.request is ConvertLegacyEngineRequest ||
                  call.request is ExportLogicalEngineRequest ||
                  call.request is PreviewImportEngineRequest ||
                  call.request is RegisterUniverseEngineRequest ||
                  call.request is StageImageEngineRequest)) {
            throw const PolicyDeniedError(
              message: 'Browser file operations require content transfer; server paths are unavailable',
            );
          }
          var body = await authenticated.execute(call.request);
          if (body is CanonicalObject &&
              body.fields.any((field) => field.key == 'contract_version')) {
            body = CanonicalObject([
              for (final field in body.fields)
                if (field.key != 'request_id') field,
              MapEntry('request_id', CanonicalNumber('${call.id}')),
            ]);
          }
          result = EngineSuccess(body);
        } on ProtocolError catch (error) {
          result = EngineFailure(error);
        } on Object {
          result = const EngineFailure(
            PolicyDeniedError(
              message: 'operation unavailable; verify current profile, grant, or package state',
            ),
          );
        }
        shutdown =
            call.request is ShutdownEngineRequest && result is EngineSuccess;
        value = EngineReply(id: call.id, result: result).toWire();
        if (value.toBytes().length > maxFrameBytes) {
          value = EngineReply(
            id: call.id,
            result: const EngineFailure(
              EvaluationLimitReachedError(message: 'response size limit'),
            ),
          ).toWire();
        }
      }
      response.headers.contentType = ContentType.json;
      response.add(value.toBytes());
    } on Object {
      // Parser/transport exceptions can contain authored text or credentials.
      request.response.statusCode = HttpStatus.badRequest;
    } finally {
      connection?.close();
      try {
        await request.response.close();
      } on Object {
        /* disconnected client */
      }
      if (shutdown) close().ignore();
    }
  }

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _stopping = true;
    _enrollments.clear();
    _browserSessions.clear();
    try {
      await _subscription.cancel();
      await Future.wait(_active.toList());
      await _server.close(force: true);
      _expireDownloads();
    } finally {
      _done.complete();
    }
  }
}
