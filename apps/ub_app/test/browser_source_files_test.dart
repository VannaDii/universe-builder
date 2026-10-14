@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_app/browser_source_files.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:web/web.dart' as web;

web.File file(List<int> bytes, String name) => web.File(
  [Uint8List.fromList(bytes).toJS].toJS,
  name,
  web.FilePropertyBag(type: 'text/plain'),
);

void main() {
  test(
    'selected UTF-8 sources retain BOM, Unicode, line endings and filename',
    () async {
      const text = '\uFEFFFirst 記憶 😀\r\nSecond e\u0301\n';
      final source = await readBrowserSourceFile(
        file(utf8.encode(text), 'Campaign notes 記憶.md'),
      );
      expect(source.name, 'Campaign notes 記憶.md');
      expect(source.text, text);
      expect(utf8.encode(source.text), utf8.encode(text));
      final empty = await readBrowserSourceFile(file([], 'empty.txt'));
      expect(empty.text, isEmpty);
    },
  );

  test('invalid UTF-8 is rejected without replacement characters', () async {
    for (final bytes in [
      [0xc3, 0x28],
      [0xed, 0xa0, 0x80],
      [0xff],
    ]) {
      await expectLater(
        readBrowserSourceFile(file(bytes, 'invalid.txt')),
        throwsFormatException,
      );
    }
  });

  test('source-file reads honor the existing service input bound', () async {
    await expectLater(
      readBrowserSourceFile(file(Uint8List(maxFrameBytes + 1), 'large.txt')),
      throwsFormatException,
    );
    final atLimit = await readBrowserSourceFile(
      file(List.filled(maxFrameBytes, 65), 'limit.txt'),
    );
    expect(atLimit.text.length, maxFrameBytes);
  });
}
