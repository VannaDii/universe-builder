@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ub_store/src/ownership.dart';
import 'package:ub_store/src/owned_database.dart';

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
