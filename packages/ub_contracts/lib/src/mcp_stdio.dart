import 'dart:async';
import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

/// Newline-delimited MCP objects. Bound each raw line before copying or decoding
/// it; preserve exact numbers and reject duplicate keys, malformed UTF-8 or BOMs.
/// No dispatcher queue is created. A final nonempty line is decoded at EOF,
/// matching the maintained LinesCodec input path.
Stream<CanonicalObject> decodeMcpStdio(Stream<List<int>> input) async* {
  final pending = BytesBuilder();
  CanonicalObject decode(Uint8List bytes) {
    final value = CanonicalValue.parseWireJson(decodeExactUtf8(bytes));
    if (value is! CanonicalObject) {
      throw const FormatException('MCP object required');
    }
    return value;
  }

  await for (final chunk in input) {
    var start = 0;
    while (start < chunk.length) {
      final newline = chunk.indexOf(10, start);
      final end = newline < 0 ? chunk.length : newline;
      if (pending.length + end - start > maxFrameBytes) {
        throw const FormatException('MCP input line limit');
      }
      if (end > start) pending.add(chunk.sublist(start, end));
      if (newline < 0) break;
      var bytes = pending.takeBytes();
      if (bytes.isNotEmpty && bytes.last == 13) {
        bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      }
      yield decode(bytes);
      start = newline + 1;
    }
  }
  var bytes = pending.takeBytes();
  if (bytes.isNotEmpty && bytes.last == 13) {
    bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
  }
  if (bytes.isNotEmpty) yield decode(bytes);
}

/// Stdout contains protocol JSON only. Output schemas can exceed the engine's
/// single-response bound, so the engine frame cap is not an MCP catalog cap.
Uint8List encodeMcpStdio(CanonicalObject value) {
  final bytes = value.toBytes();
  return Uint8List(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 10;
}
