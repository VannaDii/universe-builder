@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_store/src/archive_checksum.dart';

void main() {
  late Database db;
  setUp(() => db = sqlite3.openInMemory());
  tearDown(() => db.close());

  test('typed stream retains declared columns composite primary order exact integers and bytes', () {
    db.execute('CREATE TABLE z(id INTEGER PRIMARY KEY, value TEXT) STRICT');
    db.execute(
      'CREATE TABLE a(second INTEGER, first TEXT, value BLOB, missing TEXT, PRIMARY KEY(first,second)) STRICT',
    );
    db.execute('INSERT INTO z VALUES(?,?)', [9223372036854775807, 'é😀\n"\\']);
    db.execute('INSERT INTO a VALUES(?,?,?,?)', [
      2,
      'b',
      Uint8List.fromList([0, 15, 16, 255]),
      null,
    ]);
    db.execute('INSERT INTO a VALUES(?,?,?,?)', [
      -9223372036854775808,
      'a',
      Uint8List(0),
      '',
    ]);
    // Literal approved row-stream representation; not a canonical object map.
    const stream =
        r'[["a",["second","first","value","missing"],[["integer",-9223372036854775808],["text","a"],["bytes",""],["text",""]]],["a",["second","first","value","missing"],[["integer",2],["text","b"],["bytes","000f10ff"],["null",null]]],["z",["id","value"],[["integer",9223372036854775807],["text","é😀\n\"\\"]]]]';
    final checksum = archiveChecksum(db);
    expect(checksum.rows, 3);
    expect(checksum.digest, sha256.convert(utf8.encode(stream)).toString());
    expect(db.autocommit, isTrue);
  });

  test('checksum excludes manifest integrity search internals and orders unkeyed rows by declared columns', () {
    db.execute('CREATE TABLE body(value TEXT, ordinal INTEGER) STRICT');
    db.execute("INSERT INTO body VALUES('z',1),('a',2)");
    for (final table in [
      'r_archive_manifest',
      'archive_integrity',
      'search_index_data',
    ]) {
      db.execute('CREATE TABLE $table(value TEXT) STRICT');
      db.execute('INSERT INTO $table VALUES(?)', ['Excluded']);
    }
    const stream =
        '[["body",["value","ordinal"],[["text","a"],["integer",2]]],["body",["value","ordinal"],[["text","z"],["integer",1]]]]';
    final checksum = archiveChecksum(db);
    expect(checksum.rows, 2);
    expect(checksum.digest, sha256.convert(utf8.encode(stream)).toString());
    db.execute("UPDATE r_archive_manifest SET value='Other manifest'");
    expect(archiveChecksum(db), checksum);
    db.execute("UPDATE body SET value='Changed' WHERE ordinal=1");
    expect(archiveChecksum(db).digest, isNot(checksum.digest));
  });

  test('byte cells span encoding chunks without losing leading zeros', () {
    db.execute('CREATE TABLE data(value BLOB) STRICT');
    final bytes = Uint8List.fromList(List.generate(20001, (i) => i % 256));
    db.execute('INSERT INTO data VALUES(?)', [bytes]);
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final stream = '[["data",["value"],[["bytes","$hex"]]]]';
    expect(
      archiveChecksum(db).digest,
      sha256.convert(utf8.encode(stream)).toString(),
    );
  });

  test('unsupported real cells refuse checksum and release the statement', () {
    db.execute('CREATE TABLE invalid(value REAL) STRICT');
    db.execute('INSERT INTO invalid VALUES(1.5)');
    expect(() => archiveChecksum(db), throwsFormatException);
    db.execute('DROP TABLE invalid');
    final checksum = archiveChecksum(db);
    expect(checksum.rows, 0);
    expect(checksum.digest, sha256.convert(utf8.encode('[]')).toString());
  });

  test('archive row budget refuses an oversized stream without retaining an open statement', () {
    db.execute('CREATE TABLE oversized(id INTEGER PRIMARY KEY) STRICT');
    db.execute(
      'WITH RECURSIVE n(id) AS (VALUES(1) UNION ALL SELECT id+1 FROM n WHERE id<?) INSERT INTO oversized SELECT id FROM n',
      [maxArchiveRows + 1],
    );
    expect(() => archiveChecksum(db), throwsFormatException);
    db.execute('DROP TABLE oversized');
    expect(archiveChecksum(db).rows, 0);
  });
}
