@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ub_store/src/ownership.dart';
import 'package:ub_store/src/owned_database.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/workflow_storage.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-ownership-',
    );
  });
  tearDown(() {
    directory.deleteSync(recursive: true);
  });
  void chmod(String mode, String path) {
    final result = Process.runSync('chmod', [mode, path]);
    expect(result.exitCode, 0);
  }

  String executable() {
    final current = File(Platform.resolvedExecutable);
    return current.uri.pathSegments.last == 'dartvm'
        ? '${current.parent.path}/dart'
        : current.path;
  }

  Future<ProcessResult> attempt(String path) => Process.run(executable(), [
    'run',
    'test/helpers/ownership_process.dart',
    path,
  ]);

  test('owned startup verifies workflow evidence before switching projection generations', () {
    final path = '${directory.path}/package.sqlite';
    final owner = OwnedSqliteDatabase.create(path);
    try {
      final database = owner.database;
      final universe = UniverseId.parse('unv_000000000000000000000001');
      final continuity = ContinuityId.parse('cont_000000000000000000000001');
      final principal = PrincipalId.parse('prn_000000000000000000000001');
      database.execute('BEGIN IMMEDIATE');
      SqliteJournal(
        database,
        universe,
      ).initialize('Owned startup', continuity, principal);
      WorkflowStorage(database).put(
        'cursor:one',
        CanonicalValue.parseJson('{"binding":"exact binding","offset":0}'),
      );
      database.execute('COMMIT');
      owner.recover();
      expect(
        database
            .select('SELECT generation FROM projection_state')
            .single['generation'],
        1,
      );
      database.execute('DROP TRIGGER workflow_entries_no_update');
      database.execute('UPDATE workflow_entries SET digest=?', ['0' * 64]);
      expect(owner.recover, throwsFormatException);
      expect(
        database
            .select('SELECT generation FROM projection_state')
            .single['generation'],
        1,
      );
      expect(
        () => OwnedSqliteDatabase.openExisting(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(database.autocommit, isTrue);
    } finally {
      owner.close();
    }
  });
  test('maintenance verifies retained evidence before deleting reconstructible caches', () {
    final owner = OwnedSqliteDatabase.create(
      '${directory.path}/maintenance.sqlite',
    );
    try {
      final database = owner.database;
      final universe = UniverseId.generate();
      final continuity = ContinuityId.generate();
      final journal = SqliteJournal(database, universe);
      database.execute('BEGIN IMMEDIATE');
      final revision = journal.initialize(
        'Maintenance fixture',
        continuity,
        PrincipalId.generate(),
      );
      WorkflowStorage(database).put(
        'cursor:one',
        CanonicalValue.parseJson('{"binding":"pinned","offset":0}'),
      );
      database.execute('INSERT INTO snapshot_membership VALUES(?,?,?)', [
        universe.value,
        revision.value,
        canonicalDigest(CanonicalObject([])),
      ]);
      database.execute('COMMIT');
      owner.recover();
      database.execute('BEGIN');
      expect(() => owner.maintain(collect: true), throwsStateError);
      database.execute('ROLLBACK');
      database.execute('DROP TRIGGER workflow_entries_no_update');
      database.execute('UPDATE workflow_entries SET digest=?', ['0' * 64]);
      expect(() => owner.maintain(collect: true), throwsFormatException);
      expect(
        database
            .select('SELECT count(*) AS total FROM snapshot_membership')
            .single['total'],
        1,
      );
      expect(database.autocommit, isTrue);
    } finally {
      owner.close();
    }
  });

  test(
    'owned SQLite connection holds its writer lock through close and restart',
    () {
      final path = '${directory.path}/package.sqlite';
      final owner = OwnedSqliteDatabase.create(path);
      try {
        expect(File(path).statSync().mode & 0x1ff, 0x180);
        expect(
          owner.database.select('PRAGMA journal_mode').single.values.single,
          'wal',
        );
        expect(
          () => OwnedSqliteDatabase.openExisting(path),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        owner.close();
        owner.close();
      }
      expect(() => owner.database, throwsStateError);
      final reopened = OwnedSqliteDatabase.openExisting(path);
      reopened.close();
      expect(
        () => OwnedSqliteDatabase.create(path),
        throwsA(isA<FileSystemException>()),
      );
      final afterRefusal = OwnedSqliteDatabase.openExisting(path);
      afterRefusal.close();
      final absent = '${directory.path}/absent/package.sqlite';
      expect(
        () => OwnedSqliteDatabase.openExisting(absent),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory('${directory.path}/absent').existsSync(), isFalse);
    },
  );
  test('private directories and protected files preserve owners and restrictive modes', () {
    final path = '${directory.path}/instance';
    expect(privateDirectory(path), Directory(path).resolveSymbolicLinksSync());
    expect(Directory(path).statSync().mode & 0x3f, 0);
    final file = '$path/package.sqlite';
    protectedFile(file, createNew: true);
    expect(File(file).statSync().mode & 0x1ff, 0x180);
    File(file).writeAsStringSync('preserved');
    expect(
      () => protectedFile(file, createNew: true),
      throwsA(isA<FileSystemException>()),
    );
    protectedFile(file);
    expect(File(file).readAsStringSync(), 'preserved');
    chmod('644', file);
    expect(() => protectedFile(file), throwsA(isA<FileSystemException>()));
    expect(File(file).readAsStringSync(), 'preserved');
    chmod('755', path);
    expect(() => privateDirectory(path), throwsA(isA<FileSystemException>()));
    expect(Directory(path).statSync().mode & 0x3f, isNot(0));
  });
  test(
    'protected runtime paths refuse symlinks, hardlinks and nonregular files',
    () {
      final original = '${directory.path}/original';
      protectedFile(original, create: true);
      final link = '${directory.path}/symlink';
      Link(link).createSync(original);
      expect(() => protectedFile(link), throwsA(isA<FileSystemException>()));
      expect(
        () => OwnedFileLock.acquire(link),
        throwsA(isA<FileSystemException>()),
      );
      final alias = '${directory.path}/hardlink';
      expect(Process.runSync('ln', [original, alias]).exitCode, 0);
      expect(
        () => protectedFile(original),
        throwsA(isA<FileSystemException>()),
      );
      expect(() => protectedFile(alias), throwsA(isA<FileSystemException>()));
      expect(
        () => protectedFile(directory.path),
        throwsA(isA<FileSystemException>()),
      );
      final directoryLink = '${directory.path}/directory-link';
      Link(directoryLink).createSync(directory.path);
      expect(
        () => privateDirectory(directoryLink),
        throwsA(isA<FileSystemException>()),
      );
      expect(() => protectedFile('bad\u0000path'), throwsFormatException);
    },
  );
  test('descriptor ownership excludes isolates and survives unrelated descriptor close', () async {
    final path = '${directory.path}/writer.lock';
    final owner = OwnedFileLock.acquire(path);
    try {
      expect(
        () => OwnedFileLock.acquire(path),
        throwsA(isA<FileSystemException>()),
      );
      protectedFile(path);
      final admitted = await Isolate.run(() {
        try {
          final other = OwnedFileLock.acquire(path);
          other.close();
          return true;
        } on FileSystemException {
          return false;
        }
      });
      expect(admitted, isFalse);
      expect(
        () => OwnedFileLock.acquire(path),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      owner.close();
      owner.close();
    }
    final next = OwnedFileLock.acquire(path);
    next.close();
    expect(File(path).existsSync(), isTrue);
  });
  test('writer ownership excludes another process and releases after abnormal termination', () async {
    final path = '${directory.path}/writer.lock';
    final owner = OwnedFileLock.acquire(path);
    try {
      expect((await attempt(path)).exitCode, 2);
    } finally {
      owner.close();
    }
    expect((await attempt(path)).exitCode, 0);
    final child = await Process.start(executable(), [
      'run',
      'test/helpers/ownership_process.dart',
      path,
      'hold',
    ]);
    try {
      final signal = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      expect(signal, 'owned');
      expect(
        () => OwnedFileLock.acquire(path),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    final recovered = OwnedFileLock.acquire(path);
    recovered.close();
  });
}
