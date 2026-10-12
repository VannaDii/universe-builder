import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/source_verification.dart';

import 'operation_compilation_test.dart' as f;

const sourceText = 'Aé😀\r\nZ';
String hash(String text) => sha256.convert(utf8.encode(text)).toString();
SourceVersionRecord source({
  String text = sourceText,
  String? digest,
  int? size,
  int? decodedSize,
  String encoding = 'UTF-8',
  String representation = 'exact-utf8-v1',
  String importTime = '2026-10-11T00:00:00Z',
  OriginMetadata origin = const OriginMetadata(originNote: 'External research'),
}) => SourceVersionRecord(
  source: f.ref(1),
  contentDigest: digest ?? hash(text),
  mediaType: 'text/plain; charset=utf-8',
  byteSize: BigInt.from(size ?? utf8.encode(text).length),
  importActor: PrincipalId.parse('prn_${f.suffix(1)}'),
  importTime: importTime,
  decoding: DecodingDescriptor(
    encoding: encoding,
    representation: representation,
    byteLength: BigInt.from(decodedSize ?? size ?? utf8.encode(text).length),
  ),
  origin: origin,
);
AnchorRecord anchor({
  int start = 1,
  int end = 7,
  String excerpt = 'é😀',
  String? digest,
  AnchorLocator? locator,
  VersionRef? version,
}) => AnchorRecord(
  sourceVersion: version ?? VersionRef(record: f.id(2), version: f.ver(2)),
  locator: locator ?? ByteRangeLocator(BigInt.from(start), BigInt.from(end)),
  excerpt: excerpt,
  excerptDigest: digest ?? hash(excerpt),
);
Map<String, CanonicalValue> staging(
  SourceVersionRecord v, {
  String text = sourceText,
}) => {
  'source-version:${f.id(2).value}': v.toWire(),
  'source:${v.contentDigest}': CanonicalString(text),
};
Future<void> verify(
  List<RecordVersion> records,
  Map<String, CanonicalValue> entries, {
  RecordVersion? historical,
}) => verifyCandidateSources(
  records: records,
  readWorkflow: (key) async => entries[key],
  readVersion: (_) async =>
      historical ?? (throw StateError('Unexpected historical read')),
);
Matcher invalid(String field, String message) => throwsA(
  isA<InvalidArgumentError>()
      .having((e) => e.field, 'field', field)
      .having((e) => e.message, 'message', message),
);
void main() {
  test(
    'exact UTF-8 source imports and multibyte excerpts retain original bytes',
    () async {
      final v = source(), entries = staging(source());
      await verify([f.row(2, v), f.row(3, anchor())], entries);
      // Candidate versions are preferred over historical lookup, even when the
      // anchor precedes the source version in authored record order.
      await verify([f.row(3, anchor()), f.row(2, v)], entries);
      await verify([
        f.row(3, anchor(start: 7, end: 10, excerpt: '\r\nZ')),
        f.row(2, v),
      ], entries);
    },
  );
  test('full import provenance must match its retained receipt', () async {
    final original = source(), entries = staging(source());
    for (final changed in [
      source(importTime: '2026-10-12T00:00:00Z'),
      source(
        origin: const OriginMetadata(externallyAssertedAuthor: 'Someone else'),
      ),
      source(size: 9),
    ]) {
      await expectLater(
        verify([f.row(2, changed)], entries),
        invalid(
          'source',
          'source import provenance differs from staging receipt',
        ),
      );
    }
    expect(original.contentDigest, hash(sourceText));
  });
  test(
    'source digest, byte size and exact decoding are independently checked',
    () async {
      for (final v in [
        source(digest: 'a' * 64),
        source(size: sourceText.length),
        source(decodedSize: 0),
        source(encoding: 'utf-8'),
        source(representation: 'normalized-utf8'),
      ]) {
        await expectLater(
          verify([f.row(2, v)], staging(v)),
          invalid('source', 'source digest, length or decoding differs'),
        );
      }
      final v = source();
      await expectLater(
        verify([f.row(2, v)], staging(v, text: 'Aé😀\nZ')),
        invalid('source', 'source digest, length or decoding differs'),
      );
    },
  );
  test(
    'anchors use the pinned historical version rather than a newer source head',
    () async {
      final old = source(), newer = source(text: 'Other content');
      final current = RecordVersion.build(
        recordVersionId: f.ver(20),
        identity: f.row(2, newer).identity,
        payload: newer,
      );
      await verify(
        [f.row(3, anchor()), current],
        {
          ...staging(newer, text: 'Other content'),
          'source:${old.contentDigest}': CanonicalString(sourceText),
        },
        historical: f.row(2, old),
      );
      await expectLater(
        verify([f.row(3, anchor())], staging(old), historical: f.row(8, old)),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        verify(
          [f.row(3, anchor())],
          staging(old),
          historical: f.row(2, f.entity()),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    },
  );
  test(
    'UTF-8 boundaries, empty ranges and huge offsets are handled exactly',
    () async {
      final v = source(), entries = staging(source());
      for (final range in [(2, 3), (1, 2), (2, 2), (4, 4), (7, 6), (0, 11)]) {
        await expectLater(
          verify([
            f.row(2, v),
            f.row(3, anchor(start: range.$1, end: range.$2)),
          ], entries),
          invalid('anchor', 'invalid byte boundaries'),
        );
      }
      final huge = anchor(
        locator: ByteRangeLocator(BigInt.zero, (BigInt.one << 64) - BigInt.one),
      );
      await expectLater(
        verify([f.row(2, v), f.row(3, huge)], entries),
        invalid('anchor', 'invalid byte boundaries'),
      );
      for (final offset in [0, 1, 3, 7, 10]) {
        await verify([
          f.row(2, v),
          f.row(3, anchor(start: offset, end: offset, excerpt: '')),
        ], entries);
      }
    },
  );
  test('excerpt text and digest must both match and structural anchors stay unsupported', () async {
    final v = source(), entries = staging(source());
    for (final a in [anchor(excerpt: 'é😃'), anchor(digest: 'a' * 64)]) {
      await expectLater(
        verify([f.row(2, v), f.row(3, a)], entries),
        invalid('anchor', 'excerpt does not match immutable source'),
      );
    }
    await expectLater(
      verify([
        f.row(2, v),
        f.row(3, anchor(locator: StructuralPathLocator(['chapter1']))),
      ], entries),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
  });
  test(
    'missing receipts or retained content cannot be inferred from metadata',
    () async {
      final v = source();
      for (final entries in [
        <String, CanonicalValue>{},
        {'source-version:${f.id(2).value}': v.toWire()},
      ]) {
        await expectLater(
          verify([f.row(2, v)], entries),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      }
    },
  );
  test('image metadata must match staging and retained bytes must match its digest', () async {
    final bytes = [0, 1, 255];
    final image = ImageAssetRecord(
      contentDigest: sha256.convert(bytes).toString(),
      mediaType: 'image/png',
      byteSize: BigInt.from(bytes.length),
      width: 1,
      height: 1,
      originalName: 'image.png',
    );
    final entries = <String, CanonicalValue>{
      'image-asset:${f.id(4).value}': image.toWire(),
      'image-bytes:${image.contentDigest}:0': CanonicalString(
        base64.encode(bytes),
      ),
    };
    await verify([f.row(4, image)], entries);
    final changed = f.patch(image, {
      'original_name': CanonicalString('changed.png'),
    });
    await expectLater(
      verify([f.row(4, changed)], entries),
      invalid('image', 'image metadata differs from import receipt'),
    );
    entries['image-bytes:${image.contentDigest}:0'] = CanonicalString('AAAA');
    await expectLater(
      verify([f.row(4, image)], entries),
      throwsFormatException,
    );
  });
}
