import 'dart:convert';

import 'package:ub_domain/ub_domain.dart';

const maxImageBytes = 10 * 1048576;

/// Metadata admission is separate from decoding and verifying retained bytes.
void validateImageMetadata(ImageAssetRecord asset) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.contentDigest) ||
      asset.byteSize <= BigInt.zero ||
      asset.byteSize > BigInt.from(maxImageBytes) ||
      asset.width == 0 ||
      asset.height == 0 ||
      asset.width > 8192 ||
      asset.height > 8192 ||
      asset.width * asset.height > 32000000 ||
      !['image/png', 'image/jpeg', 'image/webp'].contains(asset.mediaType) ||
      asset.originalName.isEmpty ||
      utf8.encode(asset.originalName).length > 255 ||
      asset.originalName.contains('/') ||
      asset.originalName.contains('\\') ||
      asset.originalName.runes.any((r) => r <= 31 || r >= 127 && r <= 159)) {
    throw const FormatException('invalid image metadata');
  }
}
