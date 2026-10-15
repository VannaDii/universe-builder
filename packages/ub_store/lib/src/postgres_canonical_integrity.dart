import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'media_bytes.dart';
import 'media_decode.dart';
import 'media_metadata.dart';
import 'postgres_candidate_admission.dart';
import 'postgres_initialization.dart';
import 'postgres_journal.dart';
import 'postgres_values.dart';
import 'postgres_workflow_storage.dart';

/// Retained-content verification before recovery or transfer. This checks stored
/// evidence and history; it neither researches facts nor grants approval.
final class PostgresCanonicalIntegrity {
  PostgresCanonicalIntegrity(this._session, this.universe)
    : _schema = postgresUniverseSchema(universe),
      _journal = PostgresJournal(_session, universe);
  final TxSession _session;
  final UniverseId universe;
  final String _schema;
  final PostgresJournal _journal;

  Future<List<Map<String, dynamic>>> _rows(
    String sql,
    List<Object?> parameters,
  ) async => (await _session.execute(
    sql,
    parameters: parameters,
  )).map((row) => row.toColumnMap()).toList();

  /// The caller owns the transaction and acquires installation authority first.
  Future<void> verify() async {
    await _journal.lockUniverse();
    final workflow = PostgresWorkflowStorage(_session, universe);
    for (final row in await _rows(
      'SELECT key,source_digest,normalized_digest FROM $_schema.import_workflow_digest',
      [],
    )) {
      final value = await workflow.evidence(
        readPostgresAuthoredText(row['key'] as Uint8List),
      );
      if (value == null ||
          canonicalDigest(value) != row['normalized_digest'] ||
          !_hash(row['source_digest'] as String)) {
        throw const FormatException(
          'Converted workflow digest provenance mismatch',
        );
      }
    }
    for (final row in await _rows(
      'SELECT p.source_digest,p.normalized_digest,v.digest FROM $_schema.import_record_digest p JOIN $_schema.record_versions v ON v.universe_id=p.universe_id AND v.id=p.version_id',
      [],
    )) {
      if (row['normalized_digest'] != row['digest'] ||
          !_hash(row['source_digest'] as String)) {
        throw const FormatException('Import digest provenance mismatch');
      }
    }
    final images = <String>{};
    await for (final record in _journal.loadMany(
      (await _rows(
        'SELECT id FROM $_schema.record_versions WHERE universe_id=\$1',
        [universe.value],
      )).map((row) => RecordVersionId.parse(row['id'] as String)),
    )) {
      if (record.identity.recordKind == RecordKind.imageAsset) {
        final asset = ImageAssetRecord.fromWire(record.payload);
        validateImageMetadata(asset);
        if (images.add(asset.contentDigest)) {
          await readRetainedImageBytes(asset, workflow.evidence);
        }
      }
    }
    // Include historical entries; ordinary workflow keys intentionally hide
    // imported contexts, operations and approvals from active authorization.
    for (final row in await _rows(
      'SELECT key FROM $_schema.workflow_index',
      [],
    )) {
      if (await workflow.evidence(
            readPostgresAuthoredText(row['key'] as Uint8List),
          ) ==
          null) {
        throw const FormatException('Missing workflow evidence');
      }
    }
    await PostgresInitializationEvidence(_session, universe).verify();
  }

  /// Full transfer/restoration additionally validates staged content, anchors,
  /// historical world reservations and every unique historical membership.
  Future<void> verifyComplete() async {
    await verify();
    final workflow = PostgresWorkflowStorage(_session, universe);
    Future<String> sourceText(SourceVersionRecord source) async {
      final value = await workflow.evidence('source:${source.contentDigest}');
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

    Future<void> content(RecordPayload payload) async {
      switch (payload) {
        case ImageAssetRecord asset:
          validateImageBytes(
            asset,
            await readRetainedImageBytes(asset, workflow.evidence),
          );
        case SourceVersionRecord source:
          await sourceText(source);
        case AnchorRecord anchor:
          final record = await _journal.load(anchor.sourceVersion.version);
          if (record.identity.recordId != anchor.sourceVersion.record ||
              record.identity.recordKind != RecordKind.sourceVersion) {
            throw const FormatException(
              'Archive anchor source identity or kind mismatch',
            );
          }
          final source = SourceVersionRecord.fromWire(record.payload);
          final bytes = utf8.encode(await sourceText(source));
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
              sha256.convert(excerptBytes).toString() != anchor.excerptDigest) {
            throw const FormatException('Archive anchor excerpt mismatch');
          }
        default:
          break;
      }
    }

    await for (final record in _journal.loadMany(
      (await _rows(
        'SELECT id FROM $_schema.record_versions WHERE universe_id=\$1 ORDER BY id',
        [universe.value],
      )).map((row) => RecordVersionId.parse(row['id'] as String)),
    )) {
      final payload = RecordPayload.fromWire(record.payload);
      await content(payload);
      if (payload is WorldRecord) {
        for (final name in [payload.selector, ...payload.aliases]) {
          final reserved = await _rows(
            'SELECT record_id FROM $_schema.world_name_reservations WHERE universe_id=\$1 AND name=\$2',
            [universe.value, selectorKey(name)],
          );
          if (reserved.length != 1 ||
              reserved.single['record_id'] != record.identity.recordId.value) {
            throw const FormatException(
              'Archive omits a historical world name reservation',
            );
          }
        }
      }
    }
    for (final row in await _rows(
      "SELECT key FROM $_schema.workflow_index WHERE substring(key FROM 1 FOR 12)=convert_to('image-asset:','UTF8') OR substring(key FROM 1 FOR 15)=convert_to('source-version:','UTF8') ORDER BY key",
      [],
    )) {
      final value = await workflow.evidence(
        readPostgresAuthoredText(row['key'] as Uint8List),
      );
      if (value == null) {
        throw const FormatException('Missing staged content metadata');
      }
      final payload = RecordPayload.fromWire(value);
      if (payload is! ImageAssetRecord && payload is! SourceVersionRecord) {
        throw const FormatException('Wrong staged content family');
      }
      await content(payload);
    }
    var work = 0;
    final validated = <String>{};
    for (final row in await _rows(
      'SELECT id,continuity_id FROM $_schema.commits WHERE universe_id=\$1 ORDER BY id',
      [universe.value],
    )) {
      final membership = await _journal.snapshot(
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
        await PostgresCandidateAdmission(_journal).validate(membership);
      }
    }
  }
}

bool _hash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
