import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show maxImageBytes;
import 'package:web/web.dart' as web;

import 'browser_engine.dart';
import 'engine_failure.dart';

/// Cookie handling stays inside the browser. Redirects and cross-origin calls
/// are rejected; neither durable profile credentials nor database secrets enter
/// this adapter. Streaming enforces the same response bound as native transport.
final class SameOriginBrowserTransport {
  SameOriginBrowserTransport() {
    final location = Uri.parse(web.window.location.href);
    if (location.userInfo.isNotEmpty ||
        !(location.scheme == 'https' ||
            location.scheme == 'http' &&
                {'127.0.0.1', 'localhost', '[::1]'}.contains(location.host))) {
      throw const LocalEngineException(LocalEngineFailure.unsafeEndpoint);
    }
  }
  web.AbortController? _active;
  bool _closed = false;

  Future<BrowserEngineResponse> post(
    String path,
    Uint8List bytes,
    String? csrf,
  ) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_active != null) {
      throw const LocalEngineException(LocalEngineFailure.busy);
    }
    if (!{
          '/engine/browser/exchange',
          '/engine/browser/sign-in',
          '/engine/browser/billing',
          '/engine/browser/hello',
          '/engine/browser/call',
          '/engine/browser/logout',
          '/engine/browser/prepare-download',
        }.contains(path) ||
        bytes.length > maxFrameBytes) {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    final controller = web.AbortController();
    _active = controller;
    final deadline = Timer(
      const Duration(seconds: 15),
      () => controller.abort(),
    );
    web.ReadableStreamDefaultReader? reader;
    try {
      final headers = web.Headers()..set('content-type', 'application/json');
      if (csrf != null) headers.set('x-ub-csrf', csrf);
      final response = await web.window
          .fetch(
            path.toJS,
            web.RequestInit(
              method: 'POST',
              headers: headers,
              body: bytes.toJS,
              mode: 'same-origin',
              credentials: 'same-origin',
              redirect: 'error',
              cache: 'no-store',
              signal: controller.signal,
            ),
          )
          .toDart;
      final output = BytesBuilder(copy: false);
      final body = response.body;
      if (body != null) {
        reader = body.getReader() as web.ReadableStreamDefaultReader;
        while (true) {
          final chunk = await reader.read().toDart;
          if (chunk.done) break;
          final data = (chunk.value as JSUint8Array).toDart;
          if (output.length + data.length > maxFrameBytes) {
            controller.abort();
            throw const FormatException('Browser response size limit');
          }
          output.add(data);
        }
      }
      return BrowserEngineResponse(
        status: response.status,
        bytes: output.takeBytes(),
      );
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      deadline.cancel();
      reader?.releaseLock();
      _active = null;
    }
  }

  /// Browser fetch streams the File body directly. Only the bounded review
  /// response is buffered; cancellation aborts the transfer without admission.
  Future<BrowserEngineResponse> postArchive({
    required web.File file,
    required OperationId previewId,
    required String name,
    required ImportMode mode,
    required String csrf,
  }) async {
    return _postFile(
      file: file,
      path: '/engine/browser/import-file',
      header: 'x-ub-import',
      csrf: csrf,
      limit:
          ReadMoveChunkEngineRequest.chunkBytes *
          ReadMoveChunkEngineRequest.maxChunks,
      metadata: CanonicalObject([
        MapEntry('preview_id', CanonicalString(previewId.value)),
        MapEntry('name', CanonicalString(name)),
        MapEntry('mode', CanonicalString(mode.name)),
      ]),
    );
  }

  Future<BrowserEngineResponse> postImage({
    required web.File file,
    required Selector universe,
    required String csrf,
  }) => _postFile(
    file: file,
    path: '/engine/browser/image-file',
    header: 'x-ub-image',
    csrf: csrf,
    limit: maxImageBytes,
    metadata: CanonicalObject([
      MapEntry('universe', universe.toWire()),
      MapEntry('original_name', CanonicalString(file.name)),
    ]),
  );

  Future<BrowserEngineResponse> _postFile({
    required web.File file,
    required String path,
    required String header,
    required String csrf,
    required int limit,
    required CanonicalObject metadata,
  }) async {
    if (_closed) throw const LocalEngineException(LocalEngineFailure.closed);
    if (_active != null) {
      throw const LocalEngineException(LocalEngineFailure.busy);
    }
    final encoded = base64Encode(metadata.toBytes());
    if (file.size < 1 || file.size > limit || encoded.length > 8192) {
      throw const LocalEngineException(LocalEngineFailure.invalidRequest);
    }
    final controller = web.AbortController();
    _active = controller;
    web.ReadableStreamDefaultReader? reader;
    try {
      final headers = web.Headers()
        ..set('content-type', 'application/octet-stream')
        ..set('x-ub-csrf', csrf)
        ..set(header, encoded);
      final response = await web.window
          .fetch(
            path.toJS,
            web.RequestInit(
              method: 'POST',
              headers: headers,
              body: file,
              credentials: 'same-origin',
              mode: 'same-origin',
              redirect: 'error',
              cache: 'no-store',
              signal: controller.signal,
            ),
          )
          .toDart;
      final output = BytesBuilder(copy: false);
      if (response.body != null) {
        reader = response.body!.getReader() as web.ReadableStreamDefaultReader;
        while (true) {
          final part = await reader.read().toDart;
          if (part.done) break;
          final bytes = (part.value as JSUint8Array).toDart;
          if (output.length + bytes.length > maxFrameBytes) {
            controller.abort();
            throw const FormatException('Response exceeds input bound');
          }
          output.add(bytes);
        }
      }
      return BrowserEngineResponse(
        status: response.status,
        bytes: output.takeBytes(),
      );
    } on Object {
      throw const LocalEngineException(LocalEngineFailure.interrupted);
    } finally {
      reader?.releaseLock();
      _active = null;
    }
  }

  void close() {
    _closed = true;
    _active?.abort();
  }
}
