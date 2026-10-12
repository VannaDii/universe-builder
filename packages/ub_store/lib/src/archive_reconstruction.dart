import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'journal.dart';
import 'catalog.dart' show objectFields;
import 'media_bytes.dart';
import 'relational.dart';
import 'revision_input.dart';
import 'workflow_storage.dart';

/// Only closed reference shapes are remapped. Authored strings and original
/// editorial workflow bodies are never rewritten by clone reconstruction.
CanonicalValue _references(
  CanonicalValue value,
  UniverseId source,
  UniverseId target,
) {
  return switch (value) {
    CanonicalObject(:final fields) => CanonicalObject(() {
      final map = objectFields(value);
      final reference =
          map.containsKey('record') &&
          map.keys.every(
            (key) => const {'universe', 'record', 'version'}.contains(key),
          ) &&
          map['universe'] is CanonicalString &&
          (map['universe'] as CanonicalString).value == source.value;
      return fields.map(
        (entry) => MapEntry(
          entry.key,
          reference && entry.key == 'universe'
              ? CanonicalString(target.value)
              : _references(entry.value, source, target),
        ),
      );
    }()),
    CanonicalArray(:final items) => CanonicalArray(
      items.map((item) => _references(item, source, target)),
    ),
    _ => value,
  };
}

StoredVersion _mapped(
  StoredVersion original,
  UniverseId source,
  UniverseId target,
) {
  if (original.identity.universeId != source) {
    throw const FormatException('Archive record universe mismatch');
  }
  var payload = _references(original.payload, source, target);
  if (original.identity.recordKind == RecordKind.representedContext) {
    final fields = objectFields(payload);
    if (fields['universe'] is! CanonicalString ||
        (fields['universe'] as CanonicalString).value != source.value) {
      throw const FormatException('Foreign represented context universe');
    }
    payload = CanonicalObject(
      (payload as CanonicalObject).fields.map(
        (entry) => entry.key == 'universe'
            ? MapEntry('universe', CanonicalString(target.value))
            : entry,
      ),
    );
  }
  final mapped = StoredVersion.build(
    original.versionId,
    RecordIdentity(
      universeId: target,
      recordId: original.identity.recordId,
      recordKind: original.identity.recordKind,
    ),
    payload,
  );
  if (mapped.toCanonical().toBytes().length > 1048576) {
    throw const FormatException('Archive record too large');
  }
  return mapped;
}

/// Reconstruct from an already verified owned archive, streaming factual rows
/// and editorial evidence into the target's fresh normative schema.
void reconstructArchive(
  Database input,
  Database output, {
  required CanonicalObject manifest,
  required String digest,
  required UniverseId target,
  required String name,
  Set<RecordId>? included,
}) {
  final fields = WireFields(manifest, {
    'format',
    'universe',
    'name',
    'complete',
    'omitted_records',
    'includes_history',
    'includes_workflow',
  });
  final source = UniverseId.parse(fields.string('universe'));
  final editorial = fields.boolean('includes_workflow');
  if (!output.autocommit ||
      output.select('SELECT count(*) AS n FROM universes').single['n'] != 0) {
    throw StateError('Reconstruction requires a fresh uninitialized target');
  }
  if (input.select('SELECT count(*) AS n FROM record_versions').single['n']
              as int >
          maxVersions ||
      input.select('SELECT count(*) AS n FROM record_identities').single['n']
              as int >
          maxRecords) {
    throw const FormatException('Archive record budget exceeded');
  }
  final sourceJournal = SqliteJournal(input, source);
  final codec = RelationalCodec(output);
  final sourceWorkflow = WorkflowStorage(input);
  final workflow = WorkflowStorage(output);
  final sourceMetadata = <RecordId, int>{};
  final imageMetadata = <RecordId, int>{};
  output.execute('BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON');
  try {
    output.execute('INSERT INTO universes(id,name) VALUES(?,?)', [
      target.value,
      name,
    ]);
    void copy(String table) {
      final columns = output
          .select('PRAGMA table_info(${quoteIdentifier(table)})')
          .map((row) => row['name'] as String)
          .toList();
      final selected = columns.map(quoteIdentifier).join(',');
      final read = input.prepare(
        'SELECT $selected FROM ${quoteIdentifier(table)}',
      );
      try {
        final write = output.prepare(
          'INSERT INTO ${quoteIdentifier(table)} ($selected) VALUES (${List.filled(columns.length, '?').join(',')})',
        );
        try {
          final rows = read.selectCursor();
          while (rows.moveNext()) {
            final identityColumn = switch (table) {
              'record_identities' => 'id',
              'commit_changes' || 'world_name_reservations' => 'record_id',
              'initialization_receipt' => 'instance_id',
              _ => null,
            };
            if (included != null &&
                identityColumn != null &&
                !included.contains(
                  RecordId.parse(rows.current[identityColumn] as String),
                )) {
              continue;
            }
            write.execute([
              for (final column in columns)
                column == 'universe_id' ? target.value : rows.current[column],
            ]);
          }
        } finally {
          write.close();
        }
      } finally {
        read.close();
      }
    }

    copy('record_identities');
    final records = input.prepare(
      'SELECT id,record_id FROM record_versions ORDER BY id',
    );
    try {
      final cursor = records.selectCursor();
      while (cursor.moveNext()) {
        if (included != null &&
            !included.contains(
              RecordId.parse(cursor.current['record_id'] as String),
            )) {
          continue;
        }
        final original = sourceJournal.load(
          RecordVersionId.parse(cursor.current['id'] as String),
        );
        final mapped = _mapped(original, source, target);
        final row = codec.put('Payload', mapped.payload);
        output.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', [
          target.value,
          mapped.versionId.value,
          mapped.identity.recordId.value,
          mapped.identity.recordKind.wireName,
          row,
          mapped.digest,
        ]);
        final provenance = input.select(
          'SELECT source_digest FROM import_record_digest WHERE version_id=?',
          [original.versionId.value],
        );
        if (provenance.isNotEmpty || mapped.digest != original.digest) {
          output.execute('INSERT INTO import_record_digest VALUES(?,?,?,?)', [
            target.value,
            mapped.versionId.value,
            provenance.isEmpty
                ? original.digest
                : provenance.single['source_digest'],
            mapped.digest,
          ]);
        }
        final kind = mapped.identity.recordKind;
        if (kind == RecordKind.sourceVersion || kind == RecordKind.imageAsset) {
          final metadata = kind == RecordKind.sourceVersion
              ? sourceMetadata
              : imageMetadata;
          final prior = metadata[mapped.identity.recordId];
          if (prior != null &&
              codec.get('Payload', prior).toText() != mapped.payload.toText()) {
            throw const FormatException(
              'Archive changes immutable asset metadata',
            );
          }
          metadata[mapped.identity.recordId] = row as int;
          if (!editorial) {
            final key = kind == RecordKind.sourceVersion
                ? 'source-version:'
                : 'image-asset:';
            workflow.put(
              '$key${mapped.identity.recordId.value}',
              mapped.payload,
            );
            // Only referenced canon assets enter a canon-only reconstruction.
            if (kind == RecordKind.sourceVersion) {
              final asset = SourceVersionRecord.fromWire(mapped.payload);
              final bytesKey = 'source:${asset.contentDigest}';
              workflow.put(
                bytesKey,
                sourceWorkflow.evidence(bytesKey) ??
                    (throw const FormatException(
                      'Archive source bytes missing',
                    )),
              );
            } else {
              final asset = ImageAssetRecord.fromWire(mapped.payload);
              final count =
                  (asset.byteSize.toInt() + imageChunkBytes - 1) ~/
                  imageChunkBytes;
              for (var index = 0; index < count; index++) {
                final bytesKey = 'image-bytes:${asset.contentDigest}:$index';
                workflow.put(
                  bytesKey,
                  sourceWorkflow.evidence(bytesKey) ??
                      (throw const FormatException(
                        'Archive image bytes missing',
                      )),
                );
              }
            }
          }
        }
      }
    } finally {
      records.close();
    }
    for (final table in [
      'continuities',
      'commits',
      'commit_changes',
      'initialization_receipt',
      'world_name_reservations',
    ]) {
      copy(table);
    }
    if (editorial) {
      final entries = input.prepare(
        'SELECT key FROM workflow_index ORDER BY key',
      );
      try {
        final cursor = entries.selectCursor();
        while (cursor.moveNext()) {
          final key = cursor.current['key'] as String;
          if (key.startsWith('continuity-name:')) continue;
          workflow.put(
            key,
            sourceWorkflow.evidence(key) ??
                (throw const FormatException('Missing historical workflow')),
          );
        }
      } finally {
        entries.close();
      }
      output.execute(
        'INSERT INTO historical_workflow SELECT key FROM workflow_entries',
      );
      copy('operation_receipts');
      output.execute(
        'INSERT INTO historical_receipt SELECT universe_id,principal,operation_kind,idempotency_key FROM operation_receipts',
      );
    }
    copy('continuity_name');
    if (digest.isNotEmpty) {
      workflow.put(
        'logical-import-origin:$digest',
        CanonicalObject([
          MapEntry('digest', CanonicalString(digest)),
          MapEntry('source_universe', CanonicalString(source.value)),
          MapEntry('target_universe', CanonicalString(target.value)),
          MapEntry('complete', fields.require('complete')),
          MapEntry('omitted_records', fields.require('omitted_records')),
        ]),
      );
    }
    output.execute('COMMIT');
  } on Object {
    if (!output.autocommit) output.execute('ROLLBACK');
    rethrow;
  }
}
