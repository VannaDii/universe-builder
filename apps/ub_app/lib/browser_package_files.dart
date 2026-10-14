import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package_import.dart';

Future<SelectedArchiveFile?> pickBrowserArchive() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.sqlite,.ubarchive'
    ..multiple = false;
  input.style.display = 'none';
  web.document.body!.append(input);
  final result = Completer<SelectedArchiveFile?>();
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    result.complete(
      file == null ? null : SelectedArchiveFile(source: file, name: file.name),
    );
  }).toJS;
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!result.isCompleted) result.complete(null);
    }).toJS,
  );
  try {
    input.click();
    return await result.future;
  } finally {
    input.remove();
  }
}
