import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,pack_key,pack_version,target_record,target_universe,expected_record_version,rationale,draft_version,has_original,original_key,original_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE pack_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 pack_key TEXT NOT NULL, pack_version TEXT NOT NULL, target_record TEXT, target_universe TEXT, expected_record_version TEXT,
 rationale TEXT NOT NULL, draft_version TEXT, has_original INTEGER NOT NULL CHECK(has_original IN (0,1)), original_key TEXT, original_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 CHECK((has_original=0 AND original_key IS NULL AND original_version IS NULL) OR (has_original=1 AND original_key IS NOT NULL AND original_version IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE pack_dependency (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), dependency_key TEXT NOT NULL, dependency_version TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES pack_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE UNIQUE INDEX pack_original_dependency_key ON pack_dependency(instance,profile,universe,continuity,context,editor_key,dependency_key) WHERE list_kind='original';
CREATE TABLE pack_item (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('capabilities','records','original_capabilities','original_records')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES pack_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          c == 'ordinal' || c == 'has_original' ? c : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named domain-pack fields, separate from canon.
final class PackFormRecoveryStore {
  PackFormRecoveryStore._(this._db);
  final Database _db;

  static PackFormRecoveryStore open(String path) {
    Database? db;
    try {
      final directory = privateDirectory(File(path).absolute.parent.path);
      final actual = '$directory/${File(path).uri.pathSegments.last}';
      protectedFile(actual, create: true);
      for (final suffix in ['-wal', '-shm']) {
        if (FileSystemEntity.typeSync('$actual$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          protectedFile('$actual$suffix');
        }
      }
      db = sqlite3.open(actual, mode: OpenMode.readWrite);
      if (sqlite3.version.versionNumber < 3051003) {
        throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
      }
      _checkSchema(db);
      db.execute(
        'PRAGMA foreign_keys=ON; PRAGMA busy_timeout=1000; PRAGMA synchronous=FULL',
      );
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('BEGIN IMMEDIATE');
      try {
        final version = _checkSchema(db);
        if (version == 0) {
          db.execute(_schema);
        } else if (version == 1) {
          db.execute('ALTER TABLE pack_form RENAME TO legacy_pack_form');
          db.execute(_schema);
          final store = PackFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_pack_form',
          )) {
            final scope = EditorFormScope(
              instance: OperationId.parse(_text(row, 'instance')),
              profile: ProfileId.parse(_text(row, 'profile')),
              universe: UniverseId.parse(_text(row, 'universe')),
              continuity: ContinuityId.parse(_text(row, 'continuity')),
              representedContext: RecordId.parse(_text(row, 'context')),
              typeClientRef: _text(row, 'editor_key').isEmpty
                  ? null
                  : _text(row, 'editor_key'),
            );
            final form = UnfinishedPackForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedPackForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_pack_form');
        }
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
      for (final suffix in ['-wal', '-shm']) {
        if (File('$actual$suffix').existsSync()) {
          protectedFile('$actual$suffix');
        }
      }
      return PackFormRecoveryStore._(db);
    } on EditorRecoveryException {
      db?.close();
      rethrow;
    } on Object {
      db?.close();
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  static int _checkSchema(Database db) {
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    if (tables.isEmpty) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    String columns(String table) =>
        db.select('PRAGMA table_info($table)').map((r) => r['name']).join(',');
    final legacy =
        version == 1 &&
        tables.length == 1 &&
        columns('pack_form') == _legacyColumns;
    final current =
        version == 2 &&
        tables.length == 3 &&
        columns('pack_form') == '$_keys,$_fields' &&
        columns('pack_dependency') ==
            '$_keys,list_kind,ordinal,dependency_key,dependency_version' &&
        columns('pack_item') == '$_keys,list_kind,ordinal,item';
    if (!legacy && !current) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return version as int;
  }

  List<String> _binding(EditorFormScope scope) {
    if (scope.representedContext == null ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.entityClientRef != null ||
        scope.entityNameRecord != null ||
        scope.entityClassificationRecord != null ||
        scope.entityOperationIndex != null ||
        scope.attributeClientRef != null) {
      throw const FormatException('Choose the domain pack context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
      scope.typeClientRef ?? '',
    ];
  }

  SavedPackForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM pack_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    List<String> items(String kind) => _children(
      'pack_item',
      'item',
      binding,
      kind,
    ).map((r) => _text(r, 'item')).toList();
    List<PackDependencyInput> dependencies(String kind) =>
        _children(
              'pack_dependency',
              'dependency_key,dependency_version',
              binding,
              kind,
            )
            .map(
              (r) => PackDependencyInput(
                key: _text(r, 'dependency_key'),
                version: _text(r, 'dependency_version'),
              ),
            )
            .toList();
    return SavedPackForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedPackForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        key: _text(row, 'pack_key'),
        version: _text(row, 'pack_version'),
        dependencies: dependencies('input'),
        capabilities: items('capabilities'),
        records: items('records'),
        rationale: _text(row, 'rationale'),
        revisionTarget: row['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(row, 'target_record'),
                universe: _text(row, 'target_universe'),
              ),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(row, 'expected_record_version')),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
        original: row['has_original'] == 0
            ? null
            : DomainPackRecord(
                key: _text(row, 'original_key'),
                version: _text(row, 'original_version'),
                dependencies: {
                  for (final d in dependencies('original')) d.key: d.version,
                },
                capabilities: items('original_capabilities'),
                records: items('original_records').map(RecordId.parse),
              ),
      ),
    );
  }

  List<Row> _children(
    String table,
    String columns,
    List<String> binding,
    String kind,
  ) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM $table WHERE $_where AND list_kind=? ORDER BY ordinal',
      [...binding, kind],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete pack input row order.');
      }
    }
    return rows;
  }

  void _write(EditorFormScope scope, SavedPackForm saved) {
    final binding = _binding(scope),
        form = saved.form,
        original = form.original;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO pack_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.key,
        form.version,
        form.revisionTarget?.record,
        form.revisionTarget?.universe,
        form.expectedRecordVersion?.value,
        form.rationale,
        form.draftVersion?.toString(),
        original == null ? 0 : 1,
        original?.key,
        original?.version,
      ],
    );
    _db.execute('DELETE FROM pack_dependency WHERE $_where', binding);
    final dependencies = {
      'input': form.dependencies,
      'original':
          original?.dependencies.entries
              .map((e) => PackDependencyInput(key: e.key, version: e.value))
              .toList() ??
          <PackDependencyInput>[],
    };
    for (final list in dependencies.entries) {
      for (var i = 0; i < list.value.length; i++) {
        _db.execute('INSERT INTO pack_dependency VALUES(?,?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          list.value[i].key,
          list.value[i].version,
        ]);
      }
    }
    _db.execute('DELETE FROM pack_item WHERE $_where', binding);
    final items = {
      'capabilities': form.capabilities,
      'records': form.records,
      'original_capabilities': original?.capabilities ?? <String>[],
      'original_records':
          original?.records.map((r) => r.value).toList() ?? <String>[],
    };
    for (final list in items.entries) {
      for (var i = 0; i < list.value.length; i++) {
        _db.execute('INSERT INTO pack_item VALUES(?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          list.value[i],
        ]);
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedPackForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Pack form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedPackForm? load(EditorFormScope scope) {
    _db.execute('BEGIN');
    try {
      final result = _read(scope);
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  SavedPackForm save(
    EditorFormScope scope,
    UnfinishedPackForm form,
    BigInt expectedGeneration,
  ) {
    _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    _validate(scope, form);
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = _read(scope);
      final generation = current?.generation ?? BigInt.zero;
      if (generation != expectedGeneration) {
        if (generation == expectedGeneration + BigInt.one &&
            current!.form.toWire().toText() == form.toWire().toText()) {
          _db.execute('COMMIT');
          return current;
        }
        throw const EditorRecoveryException(EditorRecoveryFailure.conflict);
      }
      if (generation == (BigInt.one << 64) - BigInt.one) {
        throw const EditorRecoveryException(
          EditorRecoveryFailure.generationExhausted,
        );
      }
      final saved = SavedPackForm(
        generation: generation + BigInt.one,
        form: form,
      );
      _write(scope, saved);
      _db.execute('COMMIT');
      return saved;
    } on EditorRecoveryException {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  void close() => _db.close();
}
