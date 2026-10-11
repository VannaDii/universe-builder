import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'relational.dart';

/// Internal closed storage envelopes. Canonical values are transient boundary
/// objects; stored application metadata always uses the normative typed rows.
final class WorkflowStorage {
  WorkflowStorage(this.database) : codec = RelationalCodec(database);
  final Database database;
  final RelationalCodec codec;

  String? latestKey(String prefix) {
    final rows = database.select(
      'SELECT key FROM active_workflow_index WHERE substr(key,1,length(?))=? ORDER BY key DESC LIMIT 1',
      [prefix, prefix],
    );
    return rows.isEmpty ? null : rows.single['key'] as String;
  }

  List<String> keys(String prefix) => List.unmodifiable(
    database
        .select(
          'SELECT key FROM active_workflow_index WHERE substr(key,1,?)=? ORDER BY key LIMIT 10001',
          [utf8.encode(prefix).length, prefix],
        )
        .map((r) => r['key'] as String),
  );

  void compare(Map<String, String?> expected) {
    for (final entry in expected.entries) {
      if (latestKey(entry.key) != entry.value) {
        throw const FormatException('Workflow comparison conflict');
      }
    }
  }

  /// Compare selection and append all retained evidence in one immediate write.
  /// Authorization and exact approval bindings remain service responsibilities.
  void compareAppend(
    Map<String, String?> expected,
    Iterable<MapEntry<String, CanonicalValue>> entries,
  ) {
    if (!database.autocommit) {
      throw StateError('Workflow append owns its transaction');
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      compare(expected);
      for (final entry in entries) {
        put(entry.key, entry.value);
      }
      database.execute('COMMIT');
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  void put(String key, CanonicalValue value) {
    if (database.autocommit) {
      throw StateError('Workflow writes require an owned transaction');
    }
    if (value.toBytes().length > 4 * 1048576) {
      throw const FormatException('Workflow entry too large');
    }
    final hash = canonicalDigest(value);
    // Reconstruct an identical retry too: its envelope digest cannot conceal
    // a corrupt typed body or retained byte stream.
    final old = evidence(key);
    if (old != null) {
      final historicalApproval =
          database.select(
            "SELECT EXISTS(SELECT 1 FROM historical_workflow WHERE key=?) AND EXISTS(SELECT 1 FROM workflow_entries WHERE key=? AND family='ApprovalEvidence') AS present",
            [key, key],
          ).single['present'] ==
          1;
      if (historicalApproval) {
        throw const FormatException(
          'Imported approval requires a fresh validation run',
        );
      }
      if (old.toText() != value.toText()) {
        throw const FormatException('Immutable workflow key conflict');
      }
      return;
    }
    if (key.startsWith('source:')) {
      final id = key.substring('source:'.length);
      final text = _string(value);
      final bytes = Uint8List.fromList(utf8.encode(text));
      if (sha256.convert(bytes).toString() != id) {
        throw const FormatException('Source content digest mismatch');
      }
      database.execute('INSERT INTO source_content VALUES(?,?,?,?)', [
        id,
        bytes.length,
        bytes,
        hash,
      ]);
    } else if (key.startsWith('image-bytes:')) {
      final (id, ordinal) = _chunkKey(key);
      final text = _string(value);
      final bytes = base64.decode(text);
      if (base64.encode(bytes) != text) {
        throw const FormatException('Noncanonical media encoding');
      }
      database.execute('INSERT INTO media_chunk VALUES(?,?,?,?,?)', [
        id,
        ordinal,
        bytes.length,
        bytes,
        hash,
      ]);
    } else if (key.startsWith('continuity-name:')) {
      database.execute('INSERT INTO continuity_name VALUES(?,?,?,?)', [
        key.substring('continuity-name:'.length),
        key,
        _string(value),
        hash,
      ]);
    } else if (key.startsWith('source-version:') ||
        key.startsWith('image-asset:')) {
      final source = key.startsWith('source-version:');
      if (objectFields(value)['record_kind'] case CanonicalString(
        :final value,
      )) {
        if (value != (source ? 'source_version' : 'image_asset')) {
          throw const FormatException('Staging kind mismatch');
        }
      } else {
        throw const FormatException('Staging kind mismatch');
      }
      final row = codec.put('Payload', value);
      final table = source ? 'source_staging' : 'image_staging';
      database.execute('INSERT INTO $table VALUES(?,?,?)', [key, hash, row]);
    } else {
      final family = _family(key);
      final row = codec.put(family, value);
      database.execute(
        'INSERT INTO workflow_entries(key,family,digest,digest_recipe,${quoteIdentifier(family)}) VALUES(?,?,?,\'workflow-canonical\',?)',
        [key, family, hash, row],
      );
    }
  }

  CanonicalValue? get(String key) {
    final historical =
        database.select(
          "SELECT EXISTS(SELECT 1 FROM historical_workflow h JOIN workflow_entries e ON e.key=h.key WHERE h.key=? AND e.family IN ('ApprovalEvidence','StoredOperation','StoredContext','Cursor')) AS present",
          [key],
        ).single['present'] ==
        1;
    return historical ? null : evidence(key);
  }

  /// Historical evidence remains inspectable without reactivating its authority.
  CanonicalValue? evidence(String key) {
    final indexed = database.select(
      'SELECT digest FROM workflow_index WHERE key=?',
      [key],
    );
    if (indexed.isEmpty) return null;
    if (indexed.length != 1) {
      throw const FormatException('Ambiguous workflow evidence');
    }
    final expected = indexed.single['digest'] as String;
    final CanonicalValue value;
    if (key.startsWith('source:')) {
      final id = key.substring('source:'.length);
      final row = _one(
        'SELECT byte_size,utf8_content FROM source_content WHERE digest=?',
        [id],
      );
      final bytes = row['utf8_content'] as Uint8List;
      if (row['byte_size'] != bytes.length ||
          sha256.convert(bytes).toString() != id) {
        throw const FormatException('Source content integrity failure');
      }
      value = CanonicalString(utf8.decode(bytes));
    } else if (key.startsWith('image-bytes:')) {
      final (id, ordinal) = _chunkKey(key);
      final row = _one(
        'SELECT byte_size,content FROM media_chunk WHERE digest=? AND ordinal=?',
        [id, ordinal],
      );
      final bytes = row['content'] as Uint8List;
      if (row['byte_size'] != bytes.length) {
        throw const FormatException('Media size mismatch');
      }
      value = CanonicalString(base64.encode(bytes));
    } else if (key.startsWith('continuity-name:')) {
      value = CanonicalString(
        _one('SELECT name FROM continuity_name WHERE key=?', [key])['name']
            as String,
      );
    } else if (key.startsWith('source-version:') ||
        key.startsWith('image-asset:')) {
      final source = key.startsWith('source-version:');
      final table = source ? 'source_staging' : 'image_staging';
      final column = source ? 'source_version_row' : 'image_asset_row';
      value = codec.get(
        'Payload',
        _one('SELECT $column FROM $table WHERE key=?', [key])[column],
      );
    } else {
      final family = _family(key);
      final row = _one(
        'SELECT family,digest_recipe,${quoteIdentifier(family)} FROM workflow_entries WHERE key=?',
        [key],
      );
      if (row['family'] != family ||
          row['digest_recipe'] != 'workflow-canonical') {
        throw const FormatException('Workflow family mismatch');
      }
      value = codec.get(family, row[family]);
    }
    if (canonicalDigest(value) != expected) {
      throw const FormatException('Workflow integrity failure');
    }
    return value;
  }

  Row _one(String sql, List<Object?> arguments) {
    final rows = database.select(sql, arguments);
    if (rows.length != 1) {
      throw const FormatException('Missing or ambiguous workflow body');
    }
    return rows.single;
  }
}

String _string(CanonicalValue value) {
  if (value is! CanonicalString) {
    throw const FormatException('Expected workflow text');
  }
  return value.value;
}

(String, int) _chunkKey(String key) {
  final suffix = key.substring('image-bytes:'.length);
  final colon = suffix.lastIndexOf(':');
  if (colon < 0) throw const FormatException('Invalid media key');
  final digits = suffix.substring(colon + 1);
  final ordinal = int.tryParse(digits);
  if (ordinal == null || ordinal < 0 || ordinal.toString() != digits) {
    throw const FormatException('Invalid media ordinal');
  }
  return (suffix.substring(0, colon), ordinal);
}

String _family(String key) => switch (key.split(':').first) {
  'context' => 'StoredContext',
  'proposal' => 'StoredProposal',
  'reserved-record' => 'ReservedRecord',
  'validation' => 'Checked',
  'operation' || 'request' || 'job' => 'StoredOperation',
  'cancel' => 'Cancellation',
  'approval' => 'ApprovalEvidence',
  'assessment' => 'AssessmentEnvelope',
  'assessment-selection' => 'AssessmentSelection',
  'assessment-receipt' => 'AssessmentReceipt',
  'cursor' => 'Cursor',
  'draft' => 'SavedDraft',
  'logical-import-origin' => 'ImportOrigin',
  'logical-import-admission' => 'ImportAdmission',
  _ => throw const FormatException('Unknown workflow key family'),
};
