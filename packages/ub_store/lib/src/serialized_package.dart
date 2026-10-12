import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'canonical_integrity.dart';
import 'definition_index.dart';
import 'journal.dart';
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
List<String> _columns(Database db, String table) => [
  for (final row in db.select('PRAGMA table_info(${quoteIdentifier(table)})'))
    row['name'] as String,
];
bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

void _rows(Database db, String table, void Function(Row) accept) {
  final columns = _columns(db, table);
  if (columns.isEmpty) throw FormatException('Missing conversion table $table');
  final read = db.prepare(
    'SELECT * FROM ${quoteIdentifier(table)} ORDER BY ${columns.map(quoteIdentifier).join(',')} LIMIT 2000001',
  );
  try {
    final rows = read.selectCursor();
    var count = 0;
    while (rows.moveNext()) {
      if (++count > 2000000) {
        throw const FormatException('Conversion row budget exceeded');
      }
      accept(rows.current);
    }
  } finally {
    read.close();
  }
}

bool _cell(Object? a, Object? b) {
  if (a is Uint8List && b is Uint8List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
  }
  return a.runtimeType == b.runtimeType && a == b;
}

void _compare(Database input, Database output, String table) {
  final columns = _columns(input, table);
  if (!_same(columns, _columns(output, table))) {
    throw FormatException('Unsupported columns in $table');
  }
  final sql =
      'SELECT * FROM ${quoteIdentifier(table)} ORDER BY ${columns.map(quoteIdentifier).join(',')}';
  final read = input.prepare(sql);
  try {
    final retained = output.prepare(sql);
    try {
      final source = read.selectCursor(), target = retained.selectCursor();
      while (true) {
        final a = source.moveNext(), b = target.moveNext();
        if (a != b ||
            a &&
                columns.any(
                  (column) =>
                      !_cell(source.current[column], target.current[column]),
                )) {
          throw FormatException('Retained scalar table differs: $table');
        }
        if (!a) break;
      }
    } finally {
      retained.close();
    }
  } finally {
    read.close();
  }
}

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
  final metadata = _columns(input, 'schema_meta');
  if (metadata.isNotEmpty) {
    if (!_same(metadata, ['key', 'value'])) {
      throw const FormatException('Unsupported legacy schema metadata');
    }
    _rows(input, 'schema_meta', (row) {
      if (row['key'] != 'schema_version' ||
          row['value'] is! int ||
          !{1, 2}.contains(row['value'])) {
        throw const FormatException('Unsupported legacy schema metadata');
      }
    });
  }
  final versionColumns = _columns(input, 'record_versions');
  final versioned = versionColumns.contains('schema_version');
  if (!_same(versionColumns, [
        'universe_id',
        'id',
        'record_id',
        'kind',
        if (versioned) 'schema_version',
        'payload',
        'digest',
      ]) ||
      !_same(_columns(input, 'workflow_entries'), [
        'key',
        'payload',
        'digest',
      ]) ||
      !_same(_columns(input, 'snapshot_membership'), [
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
      final columns = _columns(output, table);
      if (!_same(columns, _columns(input, table))) {
        throw FormatException('Unsupported columns in $table');
      }
      final write = output.prepare(
        'INSERT INTO ${quoteIdentifier(table)} VALUES(${List.filled(columns.length, '?').join(',')})',
      );
      try {
        _rows(
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
    _rows(input, 'record_versions', (row) {
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
    _rows(input, 'workflow_entries', (row) {
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
    _rows(input, 'snapshot_membership', (row) {
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
    _rows(output, 'commits', (row) {
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
      _compare(input, output, table);
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
