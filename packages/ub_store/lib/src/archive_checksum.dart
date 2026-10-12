import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart' show maxPackageBytes;

const maxArchiveRows = 2000000;
const maxArchiveBytes = maxPackageBytes;

String archiveReviewDigest(String rows, String manifest) => sha256
    .convert(utf8.encode('typed-row-stream:$rows:manifest:$manifest'))
    .toString();

String _quote(String name) => '"${name.replaceAll('"', '""')}"';

/// The normative typed-row-stream recipe. The caller owns a consistent read
/// transaction in a trusted schema. Rows are consumed individually; large byte
/// cells are hex-encoded in chunks rather than constructing an archive graph.
({String digest, int rows}) archiveChecksum(Database database) {
  final result = _DigestResult();
  final sink = sha256.startChunkedConversion(result);
  var count = 0;
  void raw(String text) => sink.add(utf8.encode(text));
  void json(Object? value) => raw(jsonEncode(value));
  try {
    raw('[');
    for (final table in database.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search_index%' ORDER BY name",
    )) {
      final name = table['name'] as String;
      if (name == 'archive_integrity' || name == 'r_archive_manifest') continue;
      final info = database.select('PRAGMA table_info(${_quote(name)})');
      final columns = info.map((row) => row['name'] as String).toList();
      final primary = info.where((row) => (row['pk'] as int) > 0).toList()
        ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
      final order = primary.isEmpty
          ? columns
          : primary.map((row) => row['name'] as String).toList();
      final statement = database.prepare(
        'SELECT ${columns.map(_quote).join(',')} FROM ${_quote(name)} ORDER BY ${order.map(_quote).join(',')}',
      );
      try {
        final cursor = statement.selectCursor();
        while (cursor.moveNext()) {
          count++;
          if (count > maxArchiveRows) {
            throw const FormatException('Archive row budget exceeded');
          }
          if (count > 1) raw(',');
          raw('[');
          json(name);
          raw(',');
          json(columns);
          raw(',[');
          for (var index = 0; index < columns.length; index++) {
            if (index > 0) raw(',');
            final value = cursor.current[columns[index]];
            switch (value) {
              case null:
                raw('["null",null]');
              case int():
                raw('["integer",');
                json(value);
                raw(']');
              case String():
                raw('["text",');
                json(value);
                raw(']');
              case Uint8List():
                raw('["bytes","');
                const hex = '0123456789abcdef';
                for (var start = 0; start < value.length; start += 8192) {
                  final end = start + 8192 < value.length
                      ? start + 8192
                      : value.length;
                  final chunk = Uint8List((end - start) * 2);
                  for (var i = start; i < end; i++) {
                    chunk[(i - start) * 2] = hex.codeUnitAt(value[i] >> 4);
                    chunk[(i - start) * 2 + 1] = hex.codeUnitAt(value[i] & 15);
                  }
                  sink.add(chunk);
                }
                raw('"]');
              default:
                throw const FormatException('Unsupported archive real cell');
            }
          }
          raw(']]');
        }
      } finally {
        statement.close();
      }
    }
    raw(']');
    sink.close();
    return (digest: result.value!.toString(), rows: count);
  } on Object {
    sink.close();
    rethrow;
  }
}

final class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
