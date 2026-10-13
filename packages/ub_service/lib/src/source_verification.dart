import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show readRetainedImageBytes;

Never _denied() =>
    throw const NotFoundOrNotAccessibleError(message: 'resource');

/// Pages exact retained UTF-8 without splitting characters or fetching locators.
CanonicalObject retainedSourcePage(
  SourceVersionRecord source,
  CanonicalValue? retained,
  BigInt after,
) {
  if (retained is! CanonicalString) _denied();
  final bytes = utf8.encode(retained.value);
  if (BigInt.from(bytes.length) != source.byteSize ||
      sha256.convert(bytes).toString() != source.contentDigest) {
    throw const InvalidArgumentError(
      field: 'source',
      message: 'retained source differs from published metadata',
    );
  }
  if (after < BigInt.zero || after > BigInt.from(bytes.length)) {
    throw const InvalidArgumentError(
      field: 'after',
      message: 'invalid source byte offset',
    );
  }
  final start = after.toInt();
  bool boundary(int offset) =>
      offset == bytes.length || bytes[offset] & 0xc0 != 0x80;
  if (!boundary(start)) {
    throw const InvalidArgumentError(
      field: 'after',
      message: 'source offset splits a UTF-8 character',
    );
  }
  var end = start + 65536;
  if (end > bytes.length) end = bytes.length;
  while (!boundary(end)) {
    end--;
  }
  return CanonicalObject([
    MapEntry(
      'text',
      CanonicalString(decodeExactUtf8(bytes.sublist(start, end))),
    ),
    MapEntry('after', CanonicalNumber(after.toString())),
    MapEntry(
      'next',
      end == bytes.length
          ? const CanonicalNull()
          : CanonicalNumber(end.toString()),
    ),
  ]);
}

/// Verifies every source/image/anchor in a complete candidate against retained
/// imports and exact historical versions. External locators never trigger fetches.
/// Loaders must use the workflow's pinned, authorized installation/universe.
Future<void> verifyCandidateSources({
  required List<RecordVersion> records,
  required FutureOr<CanonicalValue?> Function(String key) readWorkflow,
  required FutureOr<RecordVersion> Function(RecordVersionId version)
  readVersion,
}) async {
  Future<CanonicalValue> load(String key) async =>
      await readWorkflow(key) ?? _denied();
  Future<String> text(String digest) async {
    final value = await load('source:$digest');
    if (value is! CanonicalString) {
      throw const FormatException('Expected retained source text');
    }
    return value.value;
  }

  for (final record in records) {
    switch (record.payload) {
      case ImageAssetRecord image:
        final staged = RecordPayload.fromWire(
          await load('image-asset:${record.identity.recordId.value}'),
        );
        if (staged != image) {
          throw const InvalidArgumentError(
            field: 'image',
            message: 'image metadata differs from import receipt',
          );
        }
        await readRetainedImageBytes(image, readWorkflow);
      case SourceVersionRecord source:
        final staged = RecordPayload.fromWire(
          await load('source-version:${record.identity.recordId.value}'),
        );
        if (staged != source) {
          throw const InvalidArgumentError(
            field: 'source',
            message: 'source import provenance differs from staging receipt',
          );
        }
        final bytes = utf8.encode(await text(source.contentDigest));
        if (sha256.convert(bytes).toString() != source.contentDigest ||
            BigInt.from(bytes.length) != source.byteSize ||
            source.decoding.byteLength != source.byteSize ||
            source.decoding.encoding != 'UTF-8' ||
            source.decoding.representation != 'exact-utf8-v1') {
          throw const InvalidArgumentError(
            field: 'source',
            message: 'source digest, length or decoding differs',
          );
        }
      case AnchorRecord anchor:
        RecordVersion? source;
        for (final r in records) {
          if (r.recordVersionId == anchor.sourceVersion.version) {
            source = r;
            break;
          }
        }
        source ??= await readVersion(anchor.sourceVersion.version);
        if (source.identity.recordId != anchor.sourceVersion.record) _denied();
        final payload = source.payload;
        if (payload is! SourceVersionRecord) _denied();
        final bytes = utf8.encode(await text(payload.contentDigest));
        final locator = anchor.locator;
        if (locator is! ByteRangeLocator) {
          throw const UnsupportedSemanticsError(
            message: 'only byte-accurate UTF-8 anchors are verified',
          );
        }
        final length = BigInt.from(bytes.length);
        if (locator.start > locator.end || locator.end > length) {
          throw const InvalidArgumentError(
            field: 'anchor',
            message: 'invalid byte boundaries',
          );
        }
        final start = locator.start.toInt(), end = locator.end.toInt();
        bool boundary(int offset) =>
            offset == bytes.length || bytes[offset] & 0xc0 != 0x80;
        if (!boundary(start) || !boundary(end)) {
          throw const InvalidArgumentError(
            field: 'anchor',
            message: 'invalid byte boundaries',
          );
        }
        final excerptBytes = bytes.sublist(start, end);
        if (decodeExactUtf8(excerptBytes) != anchor.excerpt ||
            sha256.convert(excerptBytes).toString() != anchor.excerptDigest) {
          throw const InvalidArgumentError(
            field: 'anchor',
            message: 'excerpt does not match immutable source',
          );
        }
      default:
        break;
    }
  }
}
