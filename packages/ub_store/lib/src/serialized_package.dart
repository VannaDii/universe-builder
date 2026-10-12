import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'canonical_integrity.dart';
import 'definition_index.dart';
import 'journal.dart';
import 'operator_rows.dart';
import 'relational.dart';
import 'serialized_conversion.dart';
import 'workflow_storage.dart';

const _scalars = [
  'universes',
  'record_identities',
  'continuities',
  'commits',
  'commit_changes',
  'world_name_reservations',
  'head_membership',
  'operation_receipts',
];
const _allowed = {
  ..._scalars,
  'projection_heads',
  'projection_state',
  'reference_index',
  'typed_projection',
  'world_projection',
  'narrative_projection',
  'schema_meta',
  'record_versions',
  'workflow_entries',
  'snapshot_membership',
  'search_index',
  'search_index_data',
  'search_index_idx',
  'search_index_content',
  'search_index_docsize',
  'search_index_config',
};

/// Construct one private normative target from the maintained serialized v1/v2
/// layouts. The offline caller owns source-file protection and publication.
/// Workflow authority stays exact; this is not historical import admission.
({int records, int workflows, int comparedTables}) constructSerializedPackage(
  Database input,
  Database output,
) {
  if (input.autocommit ||
      input.select('PRAGMA query_only').single.values.single != 1) {
    throw StateError(
      'Conversion requires a pinned read-only input transaction',
    );
  }
  if (!output.autocommit ||
      output.select('SELECT count(*) AS n FROM universes').single['n'] != 0) {
    throw StateError('Conversion requires a fresh private target');
  }
  for (final row in input.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  )) {
    if (!_allowed.contains(row['name'])) {
      throw const FormatException(
        'Unsupported input table; no evidence omitted',
      );
    }
  }
  final metadata = conversionColumns(input, 'schema_meta');
  if (metadata.isNotEmpty) {
    if (!sameConversionColumns(metadata, ['key', 'value'])) {
      throw const FormatException('Unsupported legacy schema metadata');
    }
    conversionRows(input, 'schema_meta', (row) {
      if (row['key'] != 'schema_version' ||
          row['value'] is! int ||
          !{1, 2}.contains(row['value'])) {
        throw const FormatException('Unsupported legacy schema metadata');
      }
    });
  }
  final versionColumns = conversionColumns(input, 'record_versions');
  final versioned = versionColumns.contains('schema_version');
  if (!sameConversionColumns(versionColumns, [
        'universe_id',
        'id',
        'record_id',
        'kind',
        if (versioned) 'schema_version',
        'payload',
        'digest',
      ]) ||
      !sameConversionColumns(conversionColumns(input, 'workflow_entries'), [
        'key',
        'payload',
        'digest',
      ]) ||
      !sameConversionColumns(conversionColumns(input, 'snapshot_membership'), [
        'universe_id',
        'revision_id',
        'membership',
        'checksum',
      ])) {
    throw const FormatException('Unsupported serialized conversion layout');
  }
  output.execute('BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON');
  try {
    for (final table in _scalars) {
      final columns = conversionColumns(output, table);
      if (!sameConversionColumns(columns, conversionColumns(input, table))) {
        throw FormatException('Unsupported columns in $table');
      }
      final write = output.prepare(
        'INSERT INTO ${quoteIdentifier(table)} VALUES(${List.filled(columns.length, '?').join(',')})',
      );
      try {
        conversionRows(
          input,
          table,
          (row) => write.execute([for (final column in columns) row[column]]),
        );
      } finally {
        write.close();
      }
    }
    final universes = output.select('SELECT id FROM universes LIMIT 2');
    if (universes.length != 1) {
      throw const FormatException('Conversion requires one universe');
    }
    final universe = UniverseId.parse(universes.single['id'] as String);
    final journal = SqliteJournal(output, universe);
    final codec = RelationalCodec(output);
    var recordCount = 0, workflowCount = 0;
    conversionRows(input, 'record_versions', (row) {
      if (++recordCount > maxVersions) {
        throw const FormatException('Conversion version budget exceeded');
      }
      final bytes = row['payload'];
      if (bytes is! Uint8List || row['universe_id'] != universe.value) {
        throw const FormatException('Serialized record type or scope');
      }
      final converted = convertSerializedRecord(
        universe: universe,
        recordId: RecordId.parse(row['record_id'] as String),
        versionId: RecordVersionId.parse(row['id'] as String),
        kind: RecordKind.parse(row['kind'] as String),
        bytes: bytes,
        sourceDigest: row['digest'] as String,
        schemaVersion: versioned ? row['schema_version'] as String? : null,
      );
      final record = converted.record;
      output.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', [
        universe.value,
        record.versionId.value,
        record.identity.recordId.value,
        record.identity.recordKind.wireName,
        codec.put('Payload', record.payload),
        record.digest,
      ]);
      output.execute('INSERT INTO import_record_digest VALUES(?,?,?,?)', [
        universe.value,
        record.versionId.value,
        converted.sourceDigest,
        record.digest,
      ]);
      final evidence = converted.classification;
      if (evidence != null) {
        for (var ordinal = 0; ordinal < evidence.candidates.length; ordinal++) {
          final candidate = evidence.candidates[ordinal];
          final kinds = output.select(
            'SELECT kind FROM record_identities WHERE universe_id=? AND id=?',
            [universe.value, candidate.value],
          );
          if (kinds.length != 1 || kinds.single['kind'] != 'entity_type') {
            throw const FormatException('Invalid retained ancestry candidate');
          }
          output.execute(
            'INSERT INTO classification_evidence VALUES(?,?,?,?,?)',
            [
              universe.value,
              record.versionId.value,
              evidence.relationship,
              ordinal,
              candidate.value,
            ],
          );
        }
      }
      if (journal.load(record.versionId).toCanonical().toText() !=
          record.toCanonical().toText()) {
        throw const FormatException('Converted whole-body comparison failed');
      }
    });
    final workflow = WorkflowStorage(output);
    conversionRows(input, 'workflow_entries', (row) {
      workflowCount++;
      final bytes = row['payload'];
      if (bytes is! Uint8List) {
        throw const FormatException('Serialized workflow type');
      }
      final key = row['key'] as String, hash = row['digest'] as String;
      final value = convertSerializedWorkflow(key, bytes, hash);
      workflow.put(key, value);
      output.execute('INSERT INTO import_workflow_digest VALUES(?,?,?)', [
        key,
        hash,
        canonicalDigest(value),
      ]);
      if (workflow.evidence(key)?.toText() != value.toText()) {
        throw const FormatException(
          'Converted whole-workflow comparison failed',
        );
      }
    });
    conversionRows(input, 'snapshot_membership', (row) {
      final bytes = row['membership'];
      if (bytes is! Uint8List ||
          bytes.length > 4194304 ||
          row['universe_id'] != universe.value) {
        throw const FormatException('Serialized snapshot type size or scope');
      }
      final value = CanonicalValue.parseJson(utf8.decode(bytes));
      if (value is! CanonicalObject ||
          canonicalDigest(value) != row['checksum']) {
        throw const FormatException('Original snapshot checksum mismatch');
      }
      final revision = RevisionId.parse(row['revision_id'] as String);
      final commits = output.select(
        'SELECT continuity_id FROM commits WHERE universe_id=? AND id=?',
        [universe.value, revision.value],
      );
      if (commits.length != 1) {
        throw const FormatException('Snapshot history missing');
      }
      final actual = journal.snapshot(
        ContinuityId.parse(commits.single['continuity_id'] as String),
        revision,
      );
      final expected = <RecordId, RecordVersionId>{
        for (final entry in value.fields)
          RecordId.parse(entry.key): RecordVersionId.parse(
            (entry.value as CanonicalString).value,
          ),
      };
      if (actual.length != expected.length ||
          expected.entries.any((entry) => actual[entry.key] != entry.value)) {
        throw const FormatException('Snapshot differs from factual history');
      }
      output.execute('INSERT INTO snapshot_membership VALUES(?,?,?)', [
        universe.value,
        revision.value,
        row['checksum'],
      ]);
      for (final entry in expected.entries) {
        output.execute('INSERT INTO snapshot_member VALUES(?,?,?,?)', [
          universe.value,
          revision.value,
          entry.key.value,
          entry.value.value,
        ]);
      }
    });
    final indexed = <RecordVersionId>{};
    conversionRows(output, 'commits', (row) {
      final membership = journal.snapshot(
        ContinuityId.parse(row['continuity_id'] as String),
        RevisionId.parse(row['id'] as String),
      );
      for (final version in membership.values) {
        if (indexed.add(version)) {
          DefinitionIndex(journal).index(journal.load(version), membership);
        }
      }
      _ancestry(journal, membership);
    });
    for (final row in output.select(
      'SELECT id,head_commit FROM continuities',
    )) {
      final continuity = ContinuityId.parse(row['id'] as String);
      final membership = journal.snapshot(
        continuity,
        RevisionId.parse(row['head_commit'] as String),
      );
      final retained = output.select(
        'SELECT record_id,version_id FROM head_membership WHERE universe_id=? AND continuity_id=?',
        [universe.value, continuity.value],
      );
      if (retained.length != membership.length ||
          retained.any(
            (row) =>
                membership[RecordId.parse(row['record_id'] as String)]?.value !=
                row['version_id'],
          )) {
        throw const FormatException(
          'Head membership differs from factual history',
        );
      }
    }
    CanonicalIntegrity(journal).verifyComplete();
    for (final table in _scalars) {
      compareConversionRows(input, output, table);
    }
    output.execute('COMMIT');
    return (
      records: recordCount,
      workflows: workflowCount,
      comparedTables: _scalars.length,
    );
  } on Object {
    if (!output.autocommit) output.execute('ROLLBACK');
    rethrow;
  }
}

void _ancestry(SqliteJournal journal, Membership membership) {
  final graph = <RecordId, List<RecordId>>{};
  List<RecordId> candidates(RecordVersionId version, String relationship) => [
    for (final row in journal.database.select(
      'SELECT type_id FROM classification_evidence WHERE universe_id=? AND version_id=? AND relationship=? ORDER BY ordinal',
      [journal.universe.value, version.value, relationship],
    ))
      RecordId.parse(row['type_id'] as String),
  ];
  for (final entry in membership.entries) {
    final record = journal.load(entry.value);
    if (record.identity.recordKind != RecordKind.entityType) continue;
    final parents = candidates(entry.value, 'parent');
    final type = EntityTypeRecord.fromWire(record.payload);
    graph[entry.key] = parents.isEmpty && type.parent != null
        ? [type.parent!]
        : parents;
  }
  for (final version in membership.values) {
    for (final candidate in candidates(version, 'membership')) {
      if (!graph.containsKey(candidate)) {
        throw const FormatException(
          'Classification candidate missing from historical snapshot',
        );
      }
    }
  }
  final done = <RecordId>{}, active = <RecordId>{};
  void visit(RecordId id) {
    if (done.contains(id)) return;
    if (active.length >= 64 || !active.add(id)) {
      throw const FormatException('Historical ancestry cycle or depth');
    }
    if (!graph.containsKey(id)) {
      throw const FormatException('Historical ancestry definition missing');
    }
    for (final parent in graph[id]!) {
      visit(parent);
    }
    active.remove(id);
    done.add(id);
  }

  for (final id in graph.keys) {
    visit(id);
  }
}

/// Copy the maintained relational layout, allowing only the previously absent
/// workflow digest provenance table. Source SQL is compared, never installed.
({int records, int workflows, int comparedTables}) constructRelationalPackage(
  Database input,
  Database output,
) {
  if (input.autocommit ||
      input.select('PRAGMA query_only').single.values.single != 1 ||
      !output.autocommit ||
      output.select('SELECT count(*) AS n FROM universes').single['n'] != 0) {
    throw StateError(
      'Conversion requires a pinned read-only input and fresh private target',
    );
  }
  List<(String, String, String, String)> schema(Database db) => [
    for (final row in db.select(
      "SELECT type,name,tbl_name,coalesce(sql,'') AS sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
    ))
      (
        row['type'] as String,
        row['name'] as String,
        row['tbl_name'] as String,
        row['sql'] as String,
      ),
  ];
  final source = schema(input);
  final missing = !source.any((entry) => entry.$2 == 'import_workflow_digest');
  final expected = schema(output)
      .where((entry) => !missing || entry.$3 != 'import_workflow_digest')
      .toList();
  if (source.length != expected.length ||
      Iterable<int>.generate(source.length)
          .any((i) => source[i] != expected[i])) {
    throw const FormatException(
      'Unrecognized relational conversion schema; original retained',
    );
  }
  final tables = [
    for (final row in input.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search_index%' ORDER BY name",
    ))
      row['name'] as String,
  ];
  output.execute(
    'BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON; DELETE FROM projection_state',
  );
  try {
    for (final table in tables) {
      final columns = conversionColumns(output, table);
      final write = output.prepare(
        'INSERT INTO ${quoteIdentifier(table)} VALUES(${List.filled(columns.length, '?').join(',')})',
      );
      try {
        conversionRows(
          input,
          table,
          (row) => write.execute([for (final column in columns) row[column]]),
        );
      } finally {
        write.close();
      }
    }
    for (final table in tables) {
      compareConversionRows(input, output, table);
    }
    final universes = output.select('SELECT id FROM universes LIMIT 2');
    if (universes.length != 1) {
      throw const FormatException('Conversion requires one universe');
    }
    final journal = SqliteJournal(
      output,
      UniverseId.parse(universes.single['id'] as String),
    );
    CanonicalIntegrity(journal).verifyComplete();
    conversionRows(
      output,
      'commits',
      (row) => _ancestry(
        journal,
        journal.snapshot(
          ContinuityId.parse(row['continuity_id'] as String),
          RevisionId.parse(row['id'] as String),
        ),
      ),
    );
    final records =
        output.select('SELECT count(*) AS n FROM record_versions').single['n']
            as int;
    final workflows =
        output.select('SELECT count(*) AS n FROM workflow_index').single['n']
            as int;
    output.execute('COMMIT');
    return (
      records: records,
      workflows: workflows,
      comparedTables: tables.length,
    );
  } on Object {
    if (!output.autocommit) output.execute('ROLLBACK');
    rethrow;
  }
}
