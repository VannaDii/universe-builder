import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ub_domain/ub_domain.dart';

import 'initialization.dart';
import 'journal.dart';
import 'workflow_storage.dart';

/// Runtime integrity checks from the existing kernel, before rebuilding any
/// disposable projections. This verifies retained content, not factual truth.
final class CanonicalIntegrity {
  CanonicalIntegrity(this.journal);
  final SqliteJournal journal;

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
      for (final row in database.select(
        'SELECT id FROM record_versions WHERE universe_id=?',
        [journal.universe.value],
      )) {
        final record = journal.load(RecordVersionId.parse(row['id'] as String));
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
