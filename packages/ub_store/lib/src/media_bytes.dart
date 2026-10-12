import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ub_domain/ub_domain.dart';

import 'media_metadata.dart';

const imageChunkBytes = 256 * 1024;

/// Reconstructs immutable image bytes from retained workflow chunks. Decoding
/// and metadata-versus-decoded-image checks belong to image admission/preview.
Future<Uint8List> readRetainedImageBytes(
  ImageAssetRecord asset,
  FutureOr<CanonicalValue?> Function(String key) read,
) async {
  final assembly = _ImageByteAssembly(asset);
  for (var i = 0; i < assembly.chunks; i++) {
    assembly.add(await read('image-bytes:${asset.contentDigest}:$i'));
  }
  return assembly.finish();
}

/// Native transactions use synchronous reads without yielding their ownership.
Uint8List readRetainedImageBytesSync(
  ImageAssetRecord asset,
  CanonicalValue? Function(String key) read,
) {
  final assembly = _ImageByteAssembly(asset);
  for (var i = 0; i < assembly.chunks; i++) {
    assembly.add(read('image-bytes:${asset.contentDigest}:$i'));
  }
  return assembly.finish();
}

final class _ImageByteAssembly {
  _ImageByteAssembly(this.asset) {
    validateImageMetadata(asset);
  }
  final ImageAssetRecord asset;
  final bytes = BytesBuilder(copy: false);
  int get size => asset.byteSize.toInt();
  int get chunks => (size + imageChunkBytes - 1) ~/ imageChunkBytes;

  void add(CanonicalValue? value) {
    if (value == null) throw const FormatException('missing image chunk');
    if (value is! CanonicalString) {
      throw const FormatException('invalid image chunk');
    }
    final text = value.value;
    if (text.length > ((imageChunkBytes + 2) ~/ 3) * 4) {
      throw const FormatException('image chunk exceeds limit');
    }
    Uint8List chunk;
    try {
      chunk = base64.decode(text);
      // Dart normalizes alternative alphabets, escapes and absent padding;
      // Rust's STANDARD decoder requires the original canonical representation.
      if (base64.encode(chunk) != text) {
        throw const FormatException('invalid image encoding');
      }
    } on FormatException {
      throw const FormatException('invalid image encoding');
    }
    final remaining = size - bytes.length;
    final expected = remaining < imageChunkBytes ? remaining : imageChunkBytes;
    if (chunk.length != expected) {
      throw const FormatException('image chunk size mismatch');
    }
    bytes.add(chunk);
  }

  Uint8List finish() {
    final retained = bytes.takeBytes();
    if (sha256.convert(retained).toString() != asset.contentDigest) {
      throw const FormatException('image digest mismatch');
    }
    return retained;
  }
}
