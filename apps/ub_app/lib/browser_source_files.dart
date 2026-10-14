import 'dart:async';
import 'dart:js_interop';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

import 'connection.dart';

/// Read only the selected file. Preserve UTF-8 bytes, including BOM and line
/// endings; retaining a source never normalizes it or submits it to canon.
Future<SelectedSourceText> readBrowserSourceFile(web.File file) async {
  if (file.size > maxFrameBytes) {
    throw const FormatException(
      'This text file exceeds the service input limit. Choose a smaller source excerpt.',
    );
  }
  final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
  if (bytes.length > maxFrameBytes) {
    throw const FormatException(
      'This text file exceeds the service input limit. Choose a smaller source excerpt.',
    );
  }
  try {
    return SelectedSourceText(name: file.name, text: decodeExactUtf8(bytes));
  } on FormatException {
    throw const FormatException(
      'Choose a UTF-8 text file. This file contains invalid text encoding.',
    );
  }
}

Future<SelectedSourceText?> pickBrowserSourceText() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.txt,.md,text/plain,text/markdown'
    ..multiple = false;
  input.style.display = 'none';
  web.document.body!.append(input);
  final result = Completer<SelectedSourceText?>();
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      result.complete(null);
    } else {
      result.complete(readBrowserSourceFile(file));
    }
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
