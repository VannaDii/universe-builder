import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'ownership.dart';

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

String originalFileHash(String path) {
  final result = _DigestSink();
  final hash = sha256.startChunkedConversion(result);
  readOriginalChunks(path, hash.add);
  hash.close();
  return result.value!.toString();
}

void _offline(String path) {
  for (final suffix in ['-wal', '-shm', '-journal']) {
    if (FileSystemEntity.typeSync('$path$suffix', followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FormatException(
        'Source has journal sidecars; a clean offline snapshot is required',
      );
    }
  }
}

/// Never installs source SQL or opens the original for writing. Callers retain
/// this pinned transaction through construction and revalidate before publish.
({Database database, String hash}) openOriginalDatabase(String path) {
  _offline(path);
  final hash = originalFileHash(path);
  _offline(path);
  // A clean closed WAL-format file can otherwise create WAL/SHM even under
  // SQLITE_OPEN_READONLY. This is an offline input, never a live connection;
  // refuse sidecars above and compare its hash again immediately before publish.
  final database = sqlite3.open(
    Uri.file(File(path).absolute.path)
        .replace(queryParameters: {'immutable': '1'})
        .toString(),
    mode: OpenMode.readOnly,
    uri: true,
  );
  try {
    database.execute('PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; BEGIN');
    final check = database.select('PRAGMA integrity_check');
    if (check.length != 1 || check.single.values.single != 'ok') {
      throw const FormatException(
        'Source SQLite integrity failure; repair a copy',
      );
    }
    return (database: database, hash: hash);
  } on Object {
    database.close();
    rethrow;
  }
}

void verifyOriginalDatabase(String path, String expectedHash) {
  final current = openOriginalDatabase(path);
  try {
    if (current.hash != expectedHash) {
      throw const FormatException(
        'Source changed during conversion; repeat with an offline snapshot',
      );
    }
  } finally {
    current.database.close();
  }
}
