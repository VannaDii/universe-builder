import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'media_metadata.dart';
import 'native_ownership.dart';

/// Bounded original image import from one regular, non-symlink descriptor.
Uint8List readImageFile(String path) {
  if (path.isEmpty ||
      path.contains('\u0000') ||
      path.runes.any((c) => c >= 0xd800 && c <= 0xdfff)) {
    throw const FormatException('Invalid image path');
  }
  return using((arena) {
    final bytes = arena<Uint8>(maxImageBytes + 1);
    final length = arena<Int32>();
    final error = nativeReadImage(
      path.toNativeUtf8(allocator: arena).cast(),
      bytes,
      maxImageBytes + 1,
      length,
    );
    if (error != 0) {
      throw FileSystemException(
        'Regular image file required',
        path,
        OSError('Image import refused', error),
      );
    }
    if (length.value == 0 || length.value > maxImageBytes) {
      throw const FormatException('image must be between 1 byte and 10 MiB');
    }
    return Uint8List.fromList(bytes.asTypedList(length.value));
  });
}
