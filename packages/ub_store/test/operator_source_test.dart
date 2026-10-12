@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_store/src/operator_source.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-offline-source-',
    );
    privateDirectory(root.path);
    path = '${root.path}/original.sqlite';
    protectedFile(path, createNew: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('hashes bounded chunks through a read-only private descriptor without modifying the original', () {
    final bytes = Uint8List.fromList(
      List.generate(3 * 65536 + 7, (i) => i % 251),
    );
    File(path).writeAsBytesSync(bytes, flush: true);
    expect(Process.runSync('chmod', ['400', path]).exitCode, 0);
    final chunks = <Uint8List>[];
    readOriginalChunks(path, chunks.add);
    expect(chunks.length, 4);
    expect(chunks.every((chunk) => chunk.length <= 65536), isTrue);
    expect(chunks.expand((chunk) => chunk), orderedEquals(bytes));
    expect(originalFileHash(path), sha256.convert(bytes).toString());
    expect(File(path).readAsBytesSync(), orderedEquals(bytes));
    expect(File(path).statSync().mode & 0x1ff, 0x100);
  });

  test('path replacement during consumption does not redirect the checked descriptor', () {
    final bytes = Uint8List.fromList(
      List.generate(65536 * 2 + 11, (i) => i % 253),
    );
    File(path).writeAsBytesSync(bytes);
    final retained = <int>[];
    var replaced = false;
    readOriginalChunks(path, (chunk) {
      retained.addAll(chunk);
      if (!replaced) {
        replaced = true;
        File(path).renameSync('$path.retained');
        protectedFile(path, createNew: true);
        File(path).writeAsStringSync('Replacement must not enter this read');
      }
    });
    expect(retained, orderedEquals(bytes));
    expect(originalFileHash(path), isNot(sha256.convert(bytes).toString()));
    expect(
      () =>
          readOriginalChunks(path, (_) => throw StateError('Callback failure')),
      throwsStateError,
    );
    expect(
      originalFileHash(path),
      sha256.convert(File(path).readAsBytesSync()).toString(),
    );
  });

  test('refuses symlinks hardlinks public modes nonregular inputs and files beyond 8 GiB', () {
    final link = Link('${root.path}/link')..createSync(path);
    expect(
      () => originalFileHash(link.path),
      throwsA(isA<FileSystemException>()),
    );
    final hard = '${root.path}/hard';
    expect(Process.runSync('ln', [path, hard]).exitCode, 0);
    expect(() => originalFileHash(path), throwsA(isA<FileSystemException>()));
    File(hard).deleteSync();
    expect(Process.runSync('chmod', ['644', path]).exitCode, 0);
    expect(() => originalFileHash(path), throwsA(isA<FileSystemException>()));
    expect(Process.runSync('chmod', ['600', path]).exitCode, 0);
    expect(
      () => originalFileHash(root.path),
      throwsA(isA<FileSystemException>()),
    );
    final fifo = '${root.path}/fifo';
    expect(Process.runSync('mkfifo', ['-m', '600', fifo]).exitCode, 0);
    expect(() => originalFileHash(fifo), throwsA(isA<FileSystemException>()));
    final sparse = File(path).openSync(mode: FileMode.writeOnly);
    try {
      sparse.setPositionSync(8589934592);
      sparse.writeByteSync(0);
    } finally {
      sparse.closeSync();
    }
    expect(() => originalFileHash(path), throwsA(isA<FileSystemException>()));
  });

  void createDatabase() {
    final database = sqlite3.open(path);
    try {
      database.execute(
        'CREATE TABLE factual(value TEXT); INSERT INTO factual VALUES(\'Original fact\')',
      );
    } finally {
      database.close();
    }
  }

  test(
    'pins read-only SQLite input and detects changed source before publication',
    () {
      createDatabase();
      final original = File(path).readAsBytesSync();
      expect(Process.runSync('chmod', ['400', path]).exitCode, 0);
      final source = openOriginalDatabase(path);
      try {
        expect(source.hash, sha256.convert(original).toString());
        expect(source.database.autocommit, isFalse);
        expect(
          source.database.select('PRAGMA trusted_schema').single.values.single,
          0,
        );
        expect(
          source.database.select('PRAGMA query_only').single.values.single,
          1,
        );
        expect(
          () => source.database.execute('DELETE FROM factual'),
          throwsA(isA<SqliteException>()),
        );
        verifyOriginalDatabase(path, source.hash);
      } finally {
        source.database.close();
      }
      expect(File(path).readAsBytesSync(), orderedEquals(original));
      expect(Process.runSync('chmod', ['600', path]).exitCode, 0);
      final writer = sqlite3.open(path);
      try {
        writer.execute("UPDATE factual SET value='Reviewed later fact'");
      } finally {
        writer.close();
      }
      expect(
        () => verifyOriginalDatabase(path, source.hash),
        throwsFormatException,
      );
    },
  );

  test(
    'refuses offline sidecars including dangling links and malformed SQLite',
    () {
      createDatabase();
      final original = File(path).readAsBytesSync();
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = Link('$path$suffix')..createSync('${root.path}/absent');
        expect(() => openOriginalDatabase(path), throwsFormatException);
        expect(
          () =>
              verifyOriginalDatabase(path, sha256.convert(original).toString()),
          throwsFormatException,
        );
        sidecar.deleteSync();
      }
      expect(File(path).readAsBytesSync(), orderedEquals(original));
      File(path).writeAsStringSync('Invalid SQLite input');
      expect(() => openOriginalDatabase(path), throwsA(isA<SqliteException>()));
    },
  );

  test('clean offline WAL-format databases never create journal sidecars while read-only', () {
    path = File(path).renameSync('${root.path}/offline ?#é%.sqlite').path;
    createDatabase();
    final writer = sqlite3.open(path);
    try {
      writer.execute('PRAGMA journal_mode=WAL');
    } finally {
      writer.close();
    }
    final before = File(path).readAsBytesSync();
    expect(before[18], 2);
    expect(Process.runSync('chmod', ['400', path]).exitCode, 0);
    final original = openOriginalDatabase(path);
    try {
      expect(
        original.database.select('SELECT value FROM factual').single['value'],
        'Original fact',
      );
      for (final suffix in ['-wal', '-shm', '-journal']) {
        expect(
          FileSystemEntity.typeSync('$path$suffix', followLinks: false),
          FileSystemEntityType.notFound,
        );
      }
    } finally {
      original.database.close();
    }
    verifyOriginalDatabase(path, original.hash);
    expect(File(path).readAsBytesSync(), orderedEquals(before));
  });
}
