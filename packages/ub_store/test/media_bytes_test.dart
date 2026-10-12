import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

ImageAssetRecord asset(List<int> bytes, {String? digest}) => ImageAssetRecord(
  contentDigest: digest ?? sha256.convert(bytes).toString(),
  mediaType: 'image/png',
  byteSize: BigInt.from(bytes.length),
  width: 1,
  height: 1,
  originalName: 'image.png',
);
Map<String, CanonicalValue> chunks(List<int> bytes, ImageAssetRecord image) => {
  for (var offset = 0; offset < bytes.length; offset += imageChunkBytes)
    'image-bytes:${image.contentDigest}:${offset ~/ imageChunkBytes}':
        CanonicalString(
          base64.encode(
            bytes.sublist(
              offset,
              offset + imageChunkBytes < bytes.length
                  ? offset + imageChunkBytes
                  : bytes.length,
            ),
          ),
        ),
};
void main() {
  test('retained chunks reconstruct exact bytes at each boundary and the size limit', () async {
    for (final size in [
      1,
      imageChunkBytes,
      imageChunkBytes + 1,
      maxImageBytes,
    ]) {
      final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
      final image = asset(bytes), entries = chunks(bytes, asset(bytes));
      final keys = <String>[];
      final retained = await readRetainedImageBytes(image, (key) async {
        keys.add(key);
        return entries[key];
      });
      expect(retained, bytes);
      expect(keys, entries.keys.toList());
    }
  });
  test(
    'missing, malformed and wrong-sized chunks do not produce image bytes',
    () async {
      final image = asset([0]);
      for (final entry in <CanonicalValue?>[
        null,
        const CanonicalBool(true),
        CanonicalString('%%%'),
        CanonicalString(''),
        CanonicalString('AAA='),
      ]) {
        await expectLater(
          readRetainedImageBytes(image, (_) => entry),
          throwsFormatException,
        );
      }
      final tooLarge = CanonicalString(
        'A' * (((imageChunkBytes + 2) ~/ 3) * 4 + 1),
      );
      await expectLater(
        readRetainedImageBytes(image, (_) => tooLarge),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'image chunk exceeds limit',
          ),
        ),
      );
    },
  );
  test(
    'Rust STANDARD encoding rejects Dart-normalized forms and trailing bits',
    () async {
      final image = asset([255]);
      for (final text in ['/w', '_w==', '%2Fw==', '/x==', '/w==\n']) {
        await expectLater(
          readRetainedImageBytes(image, (_) => CanonicalString(text)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'invalid image encoding',
            ),
          ),
        );
      }
      expect(
        await readRetainedImageBytes(image, (_) => CanonicalString('/w==')),
        [255],
      );
    },
  );
  test(
    'the complete image digest is verified after reconstructing every chunk',
    () async {
      final bytes = Uint8List(imageChunkBytes + 1),
          image = asset(Uint8List(imageChunkBytes + 1));
      final entries = chunks(bytes, image);
      entries[entries.keys.last] = CanonicalString('AQ==');
      await expectLater(
        readRetainedImageBytes(image, (key) => entries[key]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'image digest mismatch',
          ),
        ),
      );
    },
  );
  test(
    'invalid metadata is rejected before accessing retained chunks',
    () async {
      var reads = 0;
      await expectLater(
        readRetainedImageBytes(asset([], digest: 'a' * 64), (_) {
          reads++;
          return null;
        }),
        throwsFormatException,
      );
      expect(reads, 0);
    },
  );
}
