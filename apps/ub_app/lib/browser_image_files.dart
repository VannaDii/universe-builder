import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Keep the selected File as a streamable browser handle, never load an
/// original into a data URL or trust its extension as media validation.
Future<web.File?> pickBrowserImage() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp'
    ..multiple = false;
  input.style.display = 'none';
  web.document.body!.append(input);
  final result = Completer<web.File?>();
  input.onchange = ((web.Event _) {
    if (!result.isCompleted) result.complete(input.files?.item(0));
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
