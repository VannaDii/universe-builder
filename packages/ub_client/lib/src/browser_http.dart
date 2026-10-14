import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart' show maxFrameBytes;
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

  void close() {
    _closed = true;
    _active?.abort();
  }
}
