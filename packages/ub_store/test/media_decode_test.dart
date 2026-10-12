import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

img.Image pixels({int width = 7, int height = 5, bool highDepth = false}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: 4,
    format: highDepth ? img.Format.uint16 : img.Format.uint8,
  );
  for (final p in image) {
    p.setRgba(p.x * 19, p.y * 31, 180, 255);
  }
  return image;
}

ImageAssetRecord altered(
  ImageAssetRecord asset, {
  String? digest,
  String? media,
  int? size,
  int? width,
  int? height,
}) => ImageAssetRecord(
  contentDigest: digest ?? asset.contentDigest,
  mediaType: media ?? asset.mediaType,
  byteSize: size == null ? asset.byteSize : BigInt.from(size),
  width: width ?? asset.width,
  height: height ?? asset.height,
  originalName: asset.originalName,
);

void main() {
  test('PNG JPEG and lossy/lossless WebP derive metadata from bytes and produce bounded JPEG previews', () {
    final image = pixels();
    for (final entry in {
      'image/png': [
        img.encodePng(image),
        img.encodePng(pixels(highDepth: true)),
      ],
      'image/jpeg': [img.encodeJpg(image)],
      'image/webp': [
        img.encodeWebP(image),
        img.encodeWebP(image, lossless: false),
      ],
    }.entries) {
      for (final bytes in entry.value) {
        final before = bytes.toList(),
            asset = inspectImageBytes(bytes, 'misleading.extension');
        expect(asset.mediaType, entry.key);
        expect(asset.width, 7);
        expect(asset.height, 5);
        expect(asset.byteSize, BigInt.from(bytes.length));
        expect(asset.contentDigest, sha256.convert(bytes).toString());
        validateImageBytes(asset, bytes);
        final preview = imagePreview(asset, bytes);
        expect(preview, startsWith('data:image/jpeg;base64,'));
        final jpeg = base64.decode(preview.split(',').last);
        expect(jpeg.length, lessThanOrEqualTo(512 * 1024));
        final decoded = img.decodeJpg(jpeg)!;
        expect(decoded.width, 7);
        expect(decoded.height, 5);
        expect(bytes, before);
      }
    }
  });

  test(
    'every declared image field is checked against the decoded original',
    () {
      final bytes = img.encodePng(pixels()),
          asset = inspectImageBytes(bytes, 'original.png');
      for (final changed in [
        altered(asset, digest: '0' * 64),
        altered(asset, media: 'image/jpeg'),
        altered(asset, size: bytes.length + 1),
        altered(asset, width: 8),
        altered(asset, height: 6),
      ]) {
        expect(() => validateImageBytes(changed, bytes), throwsFormatException);
      }
      expect(
        () => inspectImageBytes(bytes, '../original.png'),
        throwsFormatException,
      );
    },
  );

  test('truncation, corrupt pixels, unsupported formats and empty or oversized inputs reject', () {
    final png = img.encodePng(pixels());
    final corrupt = Uint8List.fromList(png);
    final type = ascii.encode('IDAT');
    var offset = 8;
    while (offset + 12 <= corrupt.length) {
      final length = ByteData.sublistView(corrupt).getUint32(offset);
      if (List.generate(4, (i) => corrupt[offset + 4 + i]).join(',') ==
          type.join(',')) {
        corrupt[offset + 8] ^= 1;
        break;
      }
      offset += length + 12;
    }
    for (final bytes in [
      Uint8List(0),
      Uint8List(maxImageBytes + 1),
      Uint8List.fromList([1, 2, 3]),
      img.encodeGif(pixels()),
      Uint8List.sublistView(png, 0, png.length - 16),
      corrupt,
    ]) {
      expect(
        () => inspectImageBytes(bytes, 'image.png'),
        throwsFormatException,
      );
    }
  });

  test('dimension and 16-bit decoded-buffer limits reject header-only images before pixel allocation', () {
    // A real one-pixel PNG header with recomputed CRC; no large pixel buffer.
    final seed = img.encodePng(pixels(width: 1, height: 1, highDepth: true));
    Uint8List header(int width, int height) {
      final bytes = Uint8List.fromList(seed),
          data = ByteData.sublistView(bytes);
      data.setUint32(16, width);
      data.setUint32(20, height);
      var crc = 0xffffffff;
      for (final byte in bytes.sublist(12, 29)) {
        crc ^= byte;
        for (var bit = 0; bit < 8; bit++) {
          crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
        }
      }
      data.setUint32(29, crc ^ 0xffffffff);
      return bytes;
    }

    for (final dimensions in [
      (8193, 1),
      (1, 8193),
      (8192, 4096),
      (0, 1),
      (5000, 4000),
    ]) {
      expect(
        () => inspectImageBytes(
          header(dimensions.$1, dimensions.$2),
          'limit.png',
        ),
        throwsFormatException,
      );
    }
  });

  test('animated originals validate and preview the first frame rather than all frames', () {
    final image = pixels(width: 12, height: 8);
    image.addFrame(pixels(width: 12, height: 8));
    for (final bytes in [
      img.encodePng(image, singleFrame: false),
      img.encodeWebP(image, singleFrame: false),
    ]) {
      final asset = inspectImageBytes(bytes, 'animation');
      expect(asset.width, 12);
      expect(asset.height, 8);
      validateImageBytes(asset, bytes);
      expect(
        img
            .decodeJpg(
              base64.decode(imagePreview(asset, bytes).split(',').last),
            )!
            .width,
        12,
      );
    }
  });

  test(
    'large previews fit 768 pixels while preserving encoded EXIF orientation',
    () {
      final image = pixels(width: 1000, height: 400);
      image.exif.imageIfd.orientation = 6;
      final bytes = img.encodeJpg(image),
          asset = inspectImageBytes(bytes, 'portrait.jpg');
      final preview = img.decodeJpg(
        base64.decode(imagePreview(asset, bytes).split(',').last),
      )!;
      expect(asset.width, 1000);
      expect(asset.height, 400);
      expect(preview.width, 768);
      expect(preview.height, 307);
    },
  );
  test('all EXIF orientations retain the encoded pixels and leave originals untouched', () {
    final image = pixels(width: 20, height: 12);
    final baseline = img.encodeJpg(image);
    final baselineAsset = inspectImageBytes(baseline, 'baseline.jpg');
    final expected = imagePreview(baselineAsset, baseline);
    for (var orientation = 1; orientation <= 8; orientation++) {
      final exif = img.ExifData()..imageIfd.orientation = orientation;
      final bytes = img.injectJpgExif(baseline, exif)!;
      final original = bytes.toList(),
          asset = inspectImageBytes(bytes, 'oriented.jpg');
      expect(asset.width, 20);
      expect(asset.height, 12);
      expect(imagePreview(asset, bytes), expected);
      expect(bytes, original);
    }
  });
  test(
    'lossless WebP transforms cannot replace admitted canvas dimensions',
    () {
      final bytes = img.encodeWebP(
        img.Image(width: 5, height: 3, numChannels: 4),
      );
      final asset = inspectImageBytes(bytes, 'transparent.webp');
      expect(asset.width, 5);
      expect(asset.height, 3);
      validateImageBytes(asset, bytes);
      final preview = img.decodeJpg(
        base64.decode(imagePreview(asset, bytes).split(',').last),
      )!;
      expect(preview.width, 5);
      expect(preview.height, 3);
    },
  );
}
