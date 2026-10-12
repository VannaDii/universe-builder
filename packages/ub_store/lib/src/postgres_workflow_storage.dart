import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'postgres_relational.dart';
import 'postgres_schema.dart';
import 'postgres_values.dart';
import 'workflow_keys.dart';

/// Internal workflow primitives in a caller-owned transaction. The caller holds
/// installation authority before writing and commits only after all required
/// checks succeed. Exceptions must escape that owning transaction to roll back
/// the whole append. This class neither exposes connections nor authorizes use.
final class PostgresWorkflowStorage {
  PostgresWorkflowStorage(this._session, UniverseId universe)
    : _universe = universe,
      _schema = postgresUniverseSchema(universe),
      _codec = PostgresRelationalCodec(_session, universe);
  final TxSession _session;
  final UniverseId _universe;
  final String _schema;
  final PostgresRelationalCodec _codec;

  Future<void> _lockWrites() async {
    await _one('SELECT id FROM $_schema.universes WHERE id=\$1 FOR UPDATE', [
      _universe.value,
    ]);
  }

  Future<void> compareAppendWithVerification({
    required FutureOr<Map<String, String?>> Function() verify,
    required List<MapEntry<String, CanonicalValue>> entries,
  }) async {
    await _lockWrites();
    await compare(await verify());
    for (final entry in entries) {
      await put(entry.key, entry.value);
    }
  }

  Future<String?> latestKey(String prefix) async {
    final rows = await _rows(
      'SELECT key FROM $_schema.active_workflow_index WHERE substring(key FROM 1 FOR octet_length(\$1::bytea))=\$1 ORDER BY key DESC LIMIT 1',
      [postgresAuthoredText(prefix)],
    );
    return rows.isEmpty
        ? null
        : readPostgresAuthoredText(rows.single['key'] as Uint8List);
  }

  Future<List<String>> keys(String prefix) async => List.unmodifiable([
    for (final row in await _rows(
      'SELECT key FROM $_schema.active_workflow_index WHERE substring(key FROM 1 FOR octet_length(\$1::bytea))=\$1 ORDER BY key LIMIT 10001',
      [postgresAuthoredText(prefix)],
    ))
      readPostgresAuthoredText(row['key'] as Uint8List),
  ]);

  Future<void> compare(Map<String, String?> expected) async {
    await _lockWrites();
    for (final entry in expected.entries) {
      if (await latestKey(entry.key) != entry.value) {
        throw const FormatException('Workflow comparison conflict');
      }
    }
  }

  Future<void> compareAppend(
    Map<String, String?> expected,
    Iterable<MapEntry<String, CanonicalValue>> entries,
  ) async {
    await compare(expected);
    for (final entry in entries) {
      await put(entry.key, entry.value);
    }
  }

  Future<void> put(String key, CanonicalValue value) async {
    await _lockWrites();
    if (value.toBytes().length > 4 * 1048576) {
      throw const FormatException('Workflow entry too large');
    }
    final hash = canonicalDigest(value);
    final encodedKey = postgresAuthoredText(key);
    final old = await evidence(key);
    if (old != null) {
      final historicalApproval =
          (await _one(
                "SELECT EXISTS(SELECT 1 FROM $_schema.historical_workflow h JOIN $_schema.workflow_entries e ON e.key=h.key WHERE h.key=\$1 AND e.family='ApprovalEvidence') AS present",
                [encodedKey],
              ))['present']
              as bool;
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
      final bytes = postgresAuthoredText(_string(value));
      if (sha256.convert(bytes).toString() != id) {
        throw const FormatException('Source content digest mismatch');
      }
      await _execute(
        'INSERT INTO $_schema.source_content VALUES(\$1,\$2,\$3,\$4)',
        [id, bytes.length, bytes, hash],
      );
    } else if (key.startsWith('image-bytes:')) {
      final (id, ordinal) = workflowChunkKey(key);
      final text = _string(value);
      final bytes = base64.decode(text);
      if (base64.encode(bytes) != text) {
        throw const FormatException('Noncanonical media encoding');
      }
      await _execute(
        'INSERT INTO $_schema.media_chunk VALUES(\$1,\$2,\$3,\$4,\$5)',
        [postgresAuthoredText(id), ordinal, bytes.length, bytes, hash],
      );
    } else if (key.startsWith('continuity-name:')) {
      await _execute(
        'INSERT INTO $_schema.continuity_name VALUES(\$1,\$2,\$3,\$4)',
        [
          postgresAuthoredText(key.substring('continuity-name:'.length)),
          encodedKey,
          postgresAuthoredText(_string(value)),
          hash,
        ],
      );
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
      final row = await _codec.put('Payload', value);
      final table = source ? 'source_staging' : 'image_staging';
      await _execute('INSERT INTO $_schema.$table VALUES(\$1,\$2,\$3)', [
        encodedKey,
        hash,
        row,
      ]);
    } else {
      final family = workflowFamily(key);
      final row = await _codec.put(family, value);
      await _execute(
        "INSERT INTO $_schema.workflow_entries(key,family,digest,digest_recipe,${postgresIdentifier(family)}) VALUES(\$1,\$2,\$3,'workflow-canonical',\$4)",
        [encodedKey, family, hash, row],
      );
    }
  }

  Future<CanonicalValue?> get(String key) async {
    final historical =
        (await _one(
              "SELECT EXISTS(SELECT 1 FROM $_schema.historical_workflow h JOIN $_schema.workflow_entries e ON e.key=h.key WHERE h.key=\$1 AND e.family IN ('ApprovalEvidence','StoredOperation','StoredContext','Cursor')) AS present",
              [postgresAuthoredText(key)],
            ))['present']
            as bool;
    return historical ? null : await evidence(key);
  }

  Future<CanonicalValue?> evidence(String key) async {
    final encodedKey = postgresAuthoredText(key);
    final indexed = await _rows(
      'SELECT digest FROM $_schema.workflow_index WHERE key=\$1',
      [encodedKey],
    );
    if (indexed.isEmpty) return null;
    if (indexed.length != 1) {
      throw const FormatException('Ambiguous workflow evidence');
    }
    final expected = indexed.single['digest'] as String;
    final CanonicalValue value;
    if (key.startsWith('source:')) {
      final id = key.substring('source:'.length);
      final row = await _one(
        'SELECT byte_size,utf8_content FROM $_schema.source_content WHERE digest=\$1',
        [id],
      );
      final bytes = row['utf8_content'] as Uint8List;
      if (row['byte_size'] != bytes.length ||
          sha256.convert(bytes).toString() != id) {
        throw const FormatException('Source content integrity failure');
      }
      value = CanonicalString(readPostgresAuthoredText(bytes));
    } else if (key.startsWith('image-bytes:')) {
      final (id, ordinal) = workflowChunkKey(key);
      final row = await _one(
        'SELECT byte_size,content FROM $_schema.media_chunk WHERE digest=\$1 AND ordinal=\$2',
        [postgresAuthoredText(id), ordinal],
      );
      final bytes = row['content'] as Uint8List;
      if (row['byte_size'] != bytes.length) {
        throw const FormatException('Media size mismatch');
      }
      value = CanonicalString(base64.encode(bytes));
    } else if (key.startsWith('continuity-name:')) {
      final row = await _one(
        'SELECT name FROM $_schema.continuity_name WHERE key=\$1',
        [encodedKey],
      );
      value = CanonicalString(
        readPostgresAuthoredText(row['name'] as Uint8List),
      );
    } else if (key.startsWith('source-version:') ||
        key.startsWith('image-asset:')) {
      final source = key.startsWith('source-version:');
      final table = source ? 'source_staging' : 'image_staging';
      final column = source ? 'source_version_row' : 'image_asset_row';
      final row = await _one(
        'SELECT $column FROM $_schema.$table WHERE key=\$1',
        [encodedKey],
      );
      value = await _codec.get('Payload', row[column]);
    } else {
      final family = workflowFamily(key);
      final row = await _one(
        'SELECT family,digest_recipe,${postgresIdentifier(family)} FROM $_schema.workflow_entries WHERE key=\$1',
        [encodedKey],
      );
      if (row['family'] != family ||
          row['digest_recipe'] != 'workflow-canonical') {
        throw const FormatException('Workflow family mismatch');
      }
      value = await _codec.get(family, row[family]);
    }
    if (canonicalDigest(value) != expected) {
      throw const FormatException('Workflow integrity failure');
    }
    return value;
  }

  Future<void> _execute(String sql, List<Object?> parameters) async {
    await _session.execute(sql, parameters: parameters);
  }

  Future<List<Map<String, dynamic>>> _rows(
    String sql,
    List<Object?> parameters,
  ) async => (await _session.execute(
    sql,
    parameters: parameters,
  )).map((row) => row.toColumnMap()).toList();
  Future<Map<String, dynamic>> _one(
    String sql,
    List<Object?> parameters,
  ) async {
    final rows = await _rows(sql, parameters);
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
