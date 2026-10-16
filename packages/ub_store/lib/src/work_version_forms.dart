import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,work_record,work_universe,version_label,binding_kind,binding_continuity,binding_revision,target_record,target_universe,expected_record_version,rationale,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE work_version_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 work_record TEXT NOT NULL,
 work_universe TEXT NOT NULL,
 version_label TEXT NOT NULL,
 binding_kind TEXT NOT NULL,
 binding_continuity TEXT NOT NULL,
 binding_revision TEXT NOT NULL,
 target_record TEXT,
 target_universe TEXT,
 expected_record_version TEXT,
 rationale TEXT NOT NULL, draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE work_version_segment (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),
 segment TEXT NOT NULL,
 binding_continuity TEXT NOT NULL,
 binding_revision TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES work_version_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map((c) => c == 'ordinal' ? c : 'CAST($c AS BLOB) AS $c')
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named work version fields, separate from canon.
final class WorkVersionFormRecoveryStore {
  WorkVersionFormRecoveryStore._(this._db);
  final Database _db;

  static WorkVersionFormRecoveryStore open(String path) {
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
      return WorkVersionFormRecoveryStore._(db);
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
    final current =
        version == 2 &&
        tables.length == 2 &&
        columns('work_version_form') == '$_keys,$_fields' &&
        columns('work_version_segment') ==
            '$_keys,ordinal,segment,binding_continuity,binding_revision';
    if (!current) {
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
      throw const FormatException('Choose the work version context.');
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

  SavedWorkVersionForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM work_version_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedWorkVersionForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedWorkVersionForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        work: ExpressionReferenceInput(
          record: _text(row, 'work_record'),
          universe: _text(row, 'work_universe'),
        ),
        versionLabel: _text(row, 'version_label'),
        bindingKind: _text(row, 'binding_kind'),
        continuity: _text(row, 'binding_continuity'),
        revision: _text(row, 'binding_revision'),
        bindingTarget: row['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(row, 'target_record'),
                universe: _text(row, 'target_universe'),
              ),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(row, 'expected_record_version')),
        segments:
            _children(
              'work_version_segment',
              'segment,binding_continuity,binding_revision',
              binding,
            ).map(
              (r) => WorkSegmentInput(
                segment: _text(r, 'segment'),
                continuity: _text(r, 'binding_continuity'),
                revision: _text(r, 'binding_revision'),
              ),
            ),
        rationale: _text(row, 'rationale'),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
      ),
    );
  }

  List<Row> _children(String table, String columns, List<String> binding) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM $table WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete form row order.');
      }
    }
    return rows;
  }

  void _write(EditorFormScope scope, SavedWorkVersionForm saved) {
    final binding = _binding(scope), form = saved.form;
    final values = <Object?>[
      ...binding,
      saved.generation.toString(),
      form.baseRevision.value,
      form.clientRef,
      form.work.record,
      form.work.universe,
      form.versionLabel,
      form.bindingKind,
      form.continuity,
      form.revision,
      form.bindingTarget?.record,
      form.bindingTarget?.universe,
      form.expectedRecordVersion?.value,
      form.rationale,
      form.draftVersion?.toString(),
    ];
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO work_version_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      values,
    );
    _db.execute('DELETE FROM work_version_segment WHERE $_where', binding);
    for (var i = 0; i < form.segments.length; i++) {
      final row = form.segments[i];
      _db.execute(
        'INSERT INTO work_version_segment VALUES(?,?,?,?,?,?,?,?,?,?)',
        [...binding, i, row.segment, row.continuity, row.revision],
      );
    }
  }

  void _validate(EditorFormScope scope, UnfinishedWorkVersionForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('WorkVersion form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
  }

  SavedWorkVersionForm? load(EditorFormScope scope) {
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

  SavedWorkVersionForm save(
    EditorFormScope scope,
    UnfinishedWorkVersionForm form,
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
      final saved = SavedWorkVersionForm(
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
