@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late String source, destination;
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-installation-publication-',
    );
    privateDirectory(root.path);
    source = privateDirectory('${root.path}/staged');
    destination = '${root.path}/published';
    privateDirectory('$source/profiles');
    for (final file in [
      '$source/installation.sqlite',
      '$source/profiles/disposable.sqlite',
    ]) {
      protectedFile(file, createNew: true);
      File(file).writeAsStringSync('Complete disposable content', flush: true);
      syncPrivateFileAndDirectory(file);
    }
    syncPrivateDirectory(source);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('publishes the complete private installation directory with its files together', () {
    publishConversionDirectory(source, destination);
    expect(Directory(source).existsSync(), isFalse);
    expect(Directory(destination).statSync().mode & 0x1ff, 0x1c0);
    for (final file in [
      '$destination/installation.sqlite',
      '$destination/profiles/disposable.sqlite',
    ]) {
      expect(File(file).readAsStringSync(), 'Complete disposable content');
      expect(File(file).statSync().mode & 0x1ff, 0x180);
    }
  });

  test('existing empty and populated directories are never replaced', () {
    privateDirectory(destination);
    expect(
      () => publishConversionDirectory(source, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(source).existsSync(), isTrue);
    expect(Directory(destination).listSync(), isEmpty);
    File('$destination/retained').writeAsStringSync('Retained needed content');
    expect(
      () => publishConversionDirectory(source, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      File('$destination/retained').readAsStringSync(),
      'Retained needed content',
    );
    expect(
      File('$source/profiles/disposable.sqlite').readAsStringSync(),
      'Complete disposable content',
    );
  });

  test('existing files and dangling links are never replaced or followed', () {
    File(destination).writeAsStringSync('Retained existing file');
    expect(
      () => publishConversionDirectory(source, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(destination).readAsStringSync(), 'Retained existing file');
    File(destination).deleteSync();
    Link(destination).createSync('${root.path}/absent');
    expect(
      () => publishConversionDirectory(source, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(Link(destination).targetSync(), '${root.path}/absent');
    expect(Directory(source).existsSync(), isTrue);
  });

  test('refuses missing linked non-directory and permissive staging without creating a destination', () {
    expect(
      () => publishConversionDirectory('${root.path}/absent', destination),
      throwsFormatException,
    );
    final linked = Link('${root.path}/linked')..createSync(source);
    expect(
      () => publishConversionDirectory(linked.path, destination),
      throwsFormatException,
    );
    expect(
      () => publishConversionDirectory(
        '$source/installation.sqlite',
        destination,
      ),
      throwsFormatException,
    );
    expect(Process.runSync('chmod', ['755', source]).exitCode, 0);
    expect(
      () => publishConversionDirectory(source, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(destination).existsSync(), isFalse);
    expect(
      File('$source/installation.sqlite').readAsStringSync(),
      'Complete disposable content',
    );
    expect(Directory('${root.path}/absent').existsSync(), isFalse);
  });
}
