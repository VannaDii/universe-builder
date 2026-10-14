import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

/// Decode only selected, bounded UTF-8 bytes; preserve BOM and line endings.
Future<SelectedSourceText> readNativeSourceFile(String path) =>
    Isolate.run(() async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in File(path).openRead()) {
        if (bytes.length + chunk.length > maxFrameBytes) {
          throw const FormatException(
            'This text file exceeds the service input limit. Choose a smaller source excerpt.',
          );
        }
        bytes.add(chunk);
      }
      final String text;
      try {
        text = decodeExactUtf8(bytes.takeBytes());
      } on FormatException {
        throw const FormatException(
          'Choose a UTF-8 text file. This file contains invalid text encoding.',
        );
      }
      return SelectedSourceText(
        name: File(path).uri.pathSegments.last,
        text: text,
      );
    });
