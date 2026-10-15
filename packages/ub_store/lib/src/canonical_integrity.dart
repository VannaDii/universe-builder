import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ub_domain/ub_domain.dart';

import 'initialization.dart';
import 'candidate_foundation.dart';
import 'candidate_references.dart';
import 'journal.dart';
import 'media_bytes.dart';
import 'media_decode.dart';
import 'workflow_storage.dart';

/// Runtime integrity checks from the existing kernel, before rebuilding any
/// disposable projections. This verifies retained content, not factual truth.
final class CanonicalIntegrity {
  CanonicalIntegrity(this.journal);
  final SqliteJournal journal;

  /// Complete snapshot transfer checks, including historical rather than only
  /// current memberships and staged bytes that normal startup may leave for repair.
  void verifyComplete() {
    final database = journal.database;
    final ownRead = database.autocommit;
    if (ownRead) database.execute('BEGIN');
    try {
      verify();
      final workflow = WorkflowStorage(database);
      String sourceText(SourceVersionRecord source) {
        final value = workflow.evidence('source:${source.contentDigest}');
        if (value is! CanonicalString) {
          throw const FormatException('Missing retained source bytes');
        }
        final bytes = utf8.encode(value.value);
        if (BigInt.from(bytes.length) != source.byteSize ||
            source.decoding.byteLength != source.byteSize ||
            source.decoding.encoding != 'UTF-8' ||
            source.decoding.representation != 'exact-utf8-v1' ||
            sha256.convert(bytes).toString() != source.contentDigest) {
          throw const FormatException('Source decoding mismatch');
        }
        return value.value;
      }

      void content(RecordPayload payload) {
        switch (payload) {
          case ImageAssetRecord asset:
            validateImageBytes(
              asset,
              readRetainedImageBytesSync(asset, workflow.evidence),
            );
          case SourceVersionRecord source:
            sourceText(source);
          case AnchorRecord anchor:
            final record = journal.load(anchor.sourceVersion.version);
            if (record.identity.recordId != anchor.sourceVersion.record ||
                record.identity.recordKind != RecordKind.sourceVersion) {
              throw const FormatException(
                'Archive anchor source identity or kind mismatch',
              );
            }
            final source = SourceVersionRecord.fromWire(record.payload);
            final bytes = utf8.encode(sourceText(source));
            final locator = anchor.locator;
            if (locator is! ByteRangeLocator) {
              throw const FormatException('Archive anchor locator unsupported');
            }
            if (locator.start > locator.end ||
                locator.end > BigInt.from(bytes.length)) {
              throw const FormatException('Archive anchor UTF-8 boundaries');
            }
            final excerptBytes = bytes.sublist(
              locator.start.toInt(),
              locator.end.toInt(),
            );
            bool boundary(int offset) =>
                offset == bytes.length || bytes[offset] & 0xc0 != 0x80;
            if (!boundary(locator.start.toInt()) ||
                !boundary(locator.end.toInt())) {
              throw const FormatException('Archive anchor UTF-8 boundaries');
            }
            if (decodeExactUtf8(excerptBytes) != anchor.excerpt ||
                sha256.convert(excerptBytes).toString() !=
                    anchor.excerptDigest) {
              throw const FormatException('Archive anchor excerpt mismatch');
            }
          default:
            break;
        }
      }

      for (final record in journal.loadMany(
        database
            .select(
              'SELECT id FROM record_versions WHERE universe_id=? ORDER BY id',
              [journal.universe.value],
            )
            .map((row) => RecordVersionId.parse(row['id'] as String)),
      )) {
        final payload = RecordPayload.fromWire(record.payload);
        content(payload);
        if (payload is WorldRecord) {
          for (final name in [payload.selector, ...payload.aliases]) {
            final reserved = database.select(
              'SELECT record_id FROM world_name_reservations WHERE universe_id=? AND name=?',
              [journal.universe.value, selectorKey(name)],
            );
            if (reserved.length != 1 ||
                reserved.single['record_id'] !=
                    record.identity.recordId.value) {
              throw const FormatException(
                'Archive omits a historical world name reservation',
              );
            }
          }
        }
      }
      for (final row in database.select(
        "SELECT key FROM workflow_index WHERE key LIKE 'image-asset:%' OR key LIKE 'source-version:%' ORDER BY key",
      )) {
        final value = workflow.evidence(row['key'] as String);
        if (value == null) {
          throw const FormatException('Missing staged content metadata');
        }
        final payload = RecordPayload.fromWire(value);
        if (payload is! ImageAssetRecord && payload is! SourceVersionRecord) {
          throw const FormatException('Wrong staged content family');
        }
        content(payload);
      }
      var work = 0;
      final validated = <String>{};
      for (final row in database.select(
        'SELECT id,continuity_id FROM commits WHERE universe_id=? ORDER BY id',
        [journal.universe.value],
      )) {
        final membership = journal.snapshot(
          ContinuityId.parse(row['continuity_id'] as String),
          RevisionId.parse(row['id'] as String),
        );
        work += membership.length + 1;
        if (work > 10000000) {
          throw const FormatException(
            'Historical restoration validation budget exceeded',
          );
        }
        final digest = canonicalDigest(
          CanonicalObject([
            for (final entry in membership.entries)
              MapEntry(entry.key.value, CanonicalString(entry.value.value)),
          ]),
        );
        if (validated.add(digest)) {
          CandidateFoundation(journal).validate(membership);
          CandidateReferences(journal).validate(membership);
        }
      }
      if (ownRead) database.execute('COMMIT');
    } on Object {
      if (ownRead && !database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  void verify() {
    final database = journal.database;
    final ownRead = database.autocommit;
    if (ownRead) database.execute('BEGIN');
    try {
      final checks = database.select('PRAGMA quick_check');
      if (checks.length != 1 || checks.single.values.single != 'ok') {
        throw const FormatException('SQLite integrity failure');
      }
      if (database.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw const FormatException('Foreign key integrity failure');
      }
      final workflow = WorkflowStorage(database);
      for (final row in database.select(
        'SELECT key,source_digest,normalized_digest FROM import_workflow_digest',
      )) {
        final value = workflow.evidence(row['key'] as String);
        if (value == null ||
            canonicalDigest(value) != row['normalized_digest'] ||
            !_hash(row['source_digest'] as String)) {
          throw const FormatException(
            'Converted workflow digest provenance mismatch',
          );
        }
      }
      for (final row in database.select(
        'SELECT p.source_digest,p.normalized_digest,v.digest FROM import_record_digest p JOIN record_versions v ON v.universe_id=p.universe_id AND v.id=p.version_id',
      )) {
        if (row['normalized_digest'] != row['digest'] ||
            !_hash(row['source_digest'] as String)) {
          throw const FormatException('Import digest provenance mismatch');
        }
      }
      final images = <String>{};
      for (final record in journal.loadMany(
        database
            .select('SELECT id FROM record_versions WHERE universe_id=?', [
              journal.universe.value,
            ])
            .map((row) => RecordVersionId.parse(row['id'] as String)),
      )) {
        if (record.identity.recordKind == RecordKind.imageAsset) {
          final asset = ImageAssetRecord.fromWire(record.payload);
          _imageMetadata(asset);
          final digest = asset.contentDigest;
          if (images.add(digest)) _imageBytes(workflow, asset);
        }
      }
      for (final row in database.select('SELECT key FROM workflow_index')) {
        if (workflow.evidence(row['key'] as String) == null) {
          throw const FormatException('Missing workflow evidence');
        }
      }
      InitializationEvidence(journal).verify();
      if (ownRead) database.execute('COMMIT');
    } catch (_) {
      if (ownRead && !database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }
}

bool _hash(String value) =>
    value.length == 64 &&
    value.codeUnits.every((c) => (c >= 48 && c <= 57) || (c >= 97 && c <= 102));

void _imageMetadata(ImageAssetRecord asset) {
  final digest = asset.contentDigest;
  final size = asset.byteSize;
  final width = BigInt.from(asset.width);
  final height = BigInt.from(asset.height);
  final media = asset.mediaType;
  final name = asset.originalName;
  if (!_hash(digest) ||
      size <= BigInt.zero ||
      size > BigInt.from(10 * 1048576) ||
      width <= BigInt.zero ||
      height <= BigInt.zero ||
      width > BigInt.from(8192) ||
      height > BigInt.from(8192) ||
      width * height > BigInt.from(32000000) ||
      !{'image/png', 'image/jpeg', 'image/webp'}.contains(media) ||
      name.isEmpty ||
      utf8.encode(name).length > 255 ||
      name.contains('/') ||
      name.contains('\\') ||
      name.runes.any((c) => c <= 31 || (c >= 127 && c <= 159))) {
    throw const FormatException('Invalid image metadata');
  }
}

void _imageBytes(WorkflowStorage workflow, ImageAssetRecord asset) {
  const chunkSize = 256 * 1024;
  final digest = asset.contentDigest;
  final size = asset.byteSize.toInt();
  final bytes = BytesBuilder(copy: false);
  for (var index = 0; index < (size + chunkSize - 1) ~/ chunkSize; index++) {
    final value = workflow.get('image-bytes:$digest:$index');
    if (value is! CanonicalString) {
      throw const FormatException('Missing or invalid image chunk');
    }
    if (value.value.length > ((chunkSize + 2) ~/ 3) * 4) {
      throw const FormatException('Image chunk exceeds limit');
    }
    final chunk = base64.decode(value.value);
    final remaining = size - bytes.length;
    if (chunk.length != (remaining < chunkSize ? remaining : chunkSize)) {
      throw const FormatException('Image chunk size mismatch');
    }
    bytes.add(chunk);
  }
  if (sha256.convert(bytes.takeBytes()).toString() != digest) {
    throw const FormatException('Image digest mismatch');
  }
}
