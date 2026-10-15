@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  test(
    'temporary directories are private and never reuse an existing path',
    () {
      final parent = Directory.systemTemp.createTempSync(
        'ub-private-temp-test-',
      );
      try {
        final first = privateTemporaryDirectory(parent.path, 'stage-');
        final second = privateTemporaryDirectory(parent.path, 'stage-');
        expect(first.path, isNot(second.path));
        expect(first.parent.path, parent.path);
        expect(privateDirectory(first.path), first.resolveSymbolicLinksSync());
        expect(
          privateDirectory(second.path),
          second.resolveSymbolicLinksSync(),
        );
        expect(
          () => privateTemporaryDirectory(parent.path, '../escape'),
          throwsFormatException,
        );
        expect(
          () => privateTemporaryDirectory(parent.path, ''),
          throwsFormatException,
        );
      } finally {
        parent.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );
}
