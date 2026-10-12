import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

ImageAssetRecord image({
  String? digest,
  String media = 'image/png',
  int size = 1,
  int width = 1,
  int height = 1,
  String name = 'image.png',
}) => ImageAssetRecord(
  contentDigest: digest ?? 'a' * 64,
  mediaType: media,
  byteSize: BigInt.from(size),
  width: width,
  height: height,
  originalName: name,
);
void main() {
  test('supported images have bounded valid metadata independent of retained bytes', () {
    for (final media in ['image/png', 'image/jpeg', 'image/webp']) {
      validateImageMetadata(
        image(media: media, size: maxImageBytes, width: 8000, height: 4000),
      );
    }
  });
  test(
    'invalid digest type byte size dimensions and pixel total are rejected',
    () {
      for (final asset in [
        image(digest: 'A' * 64),
        image(digest: 'a' * 63),
        image(media: 'image/gif'),
        image(size: 0),
        image(size: maxImageBytes + 1),
        image(width: 0),
        image(height: 0),
        image(width: 8193),
        image(height: 8193),
        image(width: 8192, height: 8192),
      ]) {
        expect(() => validateImageMetadata(asset), throwsFormatException);
      }
    },
  );
  test('original name uses UTF8 bytes and excludes separators and Unicode controls', () {
    for (final name in [
      '',
      'a' * 256,
      'é' * 128,
      'path/image.png',
      'path\\image.png',
      'image\u0085.png',
      'image\u0000.png',
    ]) {
      expect(
        () => validateImageMetadata(image(name: name)),
        throwsFormatException,
      );
    }
    validateImageMetadata(image(name: 'é' * 127));
    validateImageMetadata(image(name: 'a' * 255));
  });
}
