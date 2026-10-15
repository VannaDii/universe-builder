import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_app/source_text_editing.dart';

void main() {
  test(
    'browser focus echoes retain original source bytes and mixed line endings',
    () {
      const original = '\ufeffFirst 記憶 😀\r\nSecond e\u0301\nThird\r';
      const displayed = '\ufeffFirst 記憶 😀\nSecond e\u0301\nThird\n';
      expect(browserSourceInputText(original), displayed);
      final retained = retainBrowserSourceText(original, displayed);
      expect(utf8.encode(retained), utf8.encode(original));
      expect(retainBrowserSourceText(original, retained), original);
    },
  );

  test(
    'actual source edits retain exactly the text supplied by the author',
    () {
      const original = '\ufeffOriginal\r\n';
      for (final edit in ['', 'Changed 記憶 😀\n', 'Original\n', 'Changed\r\n']) {
        expect(retainBrowserSourceText(original, edit), edit);
      }
    },
  );
}
