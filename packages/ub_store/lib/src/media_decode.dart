import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:ub_domain/ub_domain.dart';

import 'media_metadata.dart';

const maxDecodedImageBytes = 128 * 1048576;
const _maxPixels = 32000000;

({img.Image image, String media}) _decode(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxImageBytes) {
    throw const FormatException('image must be between 1 byte and 10 MiB');
  }
  // Only instantiate the three admitted decoders. Header probing must not
  // allocate pixels; the dimensions and output budget are checked first.
  final img.Decoder decoder;
  final String media;
  var decodingBytes = bytes;
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    decoder = img.PngDecoder(maxPixels: 0);
    media = 'image/png';
  } else if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 216) {
    decoder = img.JpegDecoder(maxPixels: _maxPixels);
    media = 'image/jpeg';
    // The codec bakes EXIF orientation while decoding; the existing service
    // decodes encoded pixels. Remove EXIF only from this disposable decode copy.
    decodingBytes = img.injectJpgExif(bytes, img.ExifData()) ?? bytes;
  } else if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    decoder = img.WebPDecoder()..maxPixels = 0;
    media = 'image/webp';
  } else {
    throw const FormatException('choose a PNG, JPEG or WebP image');
  }
  final img.DecodeInfo info;
  try {
    final header = decoder.startDecode(decodingBytes);
    if (header == null) throw const FormatException('invalid image dimensions');
    info = header;
  } on img.ImageException {
    throw const FormatException('invalid image dimensions');
  }
  // WebP's lossless transform may mutate its DecodeInfo while decoding.
  // Preserve the admitted canvas dimensions before requesting pixels.
  final width = info.width, height = info.height;
  if (width <= 0 ||
      height <= 0 ||
      width > 8192 ||
      height > 8192 ||
      width * height > _maxPixels) {
    throw const FormatException(
      'image exceeds 8192 pixels per edge or 32 megapixels',
    );
  }
  var sampleBytes = 1, channels = 4;
  if (decoder is img.PngDecoder) {
    final png = decoder.info;
    sampleBytes = png.bits == 16 ? 2 : 1;
    channels = switch (png.colorType) {
      0 => 1,
      2 => 3,
      3 => 4,
      4 => 2,
      6 => 4,
      _ => 4,
    };
    if (png.transparency != null &&
        (png.colorType == 0 || png.colorType == 2)) {
      channels = 4;
    }
  }
  // Like the existing image::Limits, this is a decoder/output allocation
  // budget, not a limit on the process heap or allocator overhead.
  if (width * height * channels * sampleBytes > maxDecodedImageBytes) {
    throw const FormatException('image could not be decoded within limits');
  }
  try {
    var decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('image could not be decoded within limits');
    }
    if (decoder is img.WebPDecoder && decoder.info!.hasAnimation) {
      final frame = decoder.info!.frames.first;
      if (frame.x < 0 ||
          frame.y < 0 ||
          frame.x + decoded.width > width ||
          frame.y + decoded.height > height) {
        throw const FormatException('image could not be decoded within limits');
      }
      final canvas = img.Image(width: width, height: height, numChannels: 4);
      img.compositeImage(
        canvas,
        decoded,
        dstX: frame.x,
        dstY: frame.y,
        blend: frame.blendFrame ? img.BlendMode.alpha : img.BlendMode.direct,
      );
      decoded = canvas;
    }
    if (decoded.width != width || decoded.height != height) {
      throw const FormatException('image could not be decoded within limits');
    }
    return (image: decoded, media: media);
  } on img.ImageException {
    throw const FormatException('image could not be decoded within limits');
  }
}

/// Import metadata is derived from decoded original bytes, never the filename.
ImageAssetRecord inspectImageBytes(Uint8List bytes, String originalName) {
  final decoded = _decode(bytes);
  final asset = ImageAssetRecord(
    contentDigest: sha256.convert(bytes).toString(),
    mediaType: decoded.media,
    byteSize: BigInt.from(bytes.length),
    width: decoded.image.width,
    height: decoded.image.height,
    originalName: originalName,
  );
  validateImageMetadata(asset);
  return asset;
}

void validateImageBytes(ImageAssetRecord asset, Uint8List bytes) {
  validateImageMetadata(asset);
  final decoded = _decode(bytes);
  if (decoded.image.width != asset.width ||
      decoded.image.height != asset.height ||
      decoded.media != asset.mediaType ||
      BigInt.from(bytes.length) != asset.byteSize ||
      sha256.convert(bytes).toString() != asset.contentDigest) {
    throw const FormatException('image metadata differs from original bytes');
  }
}

/// Disposable JPEG preview. Original bytes and their digest remain unchanged.
String imagePreview(ImageAssetRecord asset, Uint8List bytes) {
  validateImageMetadata(asset);
  if (BigInt.from(bytes.length) != asset.byteSize ||
      sha256.convert(bytes).toString() != asset.contentDigest) {
    throw const FormatException('image metadata differs from original bytes');
  }
  final decoded = _decode(bytes).image;
  // Rust previews retain encoded pixel orientation, ignoring EXIF rotation.
  decoded.exif = img.ExifData();
  for (final edge in [768, 512, 256]) {
    final scale = math.min(
      math.min(edge, decoded.width) / decoded.width,
      math.min(edge, decoded.height) / decoded.height,
    );
    final preview = img
        .copyResize(
          decoded,
          width: math.max(1, (decoded.width * scale).round()),
          height: math.max(1, (decoded.height * scale).round()),
          interpolation: img.Interpolation.average,
        )
        .convert(format: img.Format.uint8, numChannels: 3);
    final encoded = img.encodeJpg(preview, quality: 75);
    if (encoded.length <= 512 * 1024) {
      return 'data:image/jpeg;base64,${base64.encode(encoded)}';
    }
  }
  throw const FormatException('image preview exceeds limit');
}
