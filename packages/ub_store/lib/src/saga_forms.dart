import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,title,target_record,target_universe,expected_record_version,rationale,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE saga_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 title TEXT NOT NULL,
 target_record TEXT,
 target_universe TEXT,
 expected_record_version TEXT,
 rationale TEXT NOT NULL, draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE saga_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),
 language TEXT NOT NULL,
 label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES saga_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE saga_membership (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),
 work_record TEXT NOT NULL,
 work_universe TEXT NOT NULL,
 role TEXT NOT NULL,
 order_enabled INTEGER NOT NULL CHECK(order_enabled IN (0,1)),
 order_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES saga_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          c == 'ordinal' || c == 'order_enabled' ? c : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named saga fields, separate from canon.
final class SagaFormRecoveryStore {
  SagaFormRecoveryStore._(this._db);
  final Database _db;

  static SagaFormRecoveryStore open(String path) {
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
          db.execute('ALTER TABLE saga_form RENAME TO legacy_saga_form');
          db.execute(_schema);
          final store = SagaFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_saga_form',
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
            final form = UnfinishedSagaForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedSagaForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_saga_form');
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
      return SagaFormRecoveryStore._(db);
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
        columns('saga_form') == _legacyColumns;
    final current =
        version == 2 &&
        tables.length == 3 &&
        columns('saga_form') == '$_keys,$_fields' &&
        columns('saga_label') == '$_keys,ordinal,language,label_text' &&
        columns('saga_membership') ==
            '$_keys,ordinal,work_record,work_universe,role,order_enabled,order_input';
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
      throw const FormatException('Choose the saga context.');
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

  SavedSagaForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM saga_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedSagaForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedSagaForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        title: _text(row, 'title'),
        membershipTarget: row['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(row, 'target_record'),
                universe: _text(row, 'target_universe'),
              ),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(row, 'expected_record_version')),
        labels: _children('saga_label', 'language,label_text', binding).map(
          (r) => PropertyLabelInput(
            language: _text(r, 'language'),
            text: _text(r, 'label_text'),
          ),
        ),
        memberships:
            _children(
              'saga_membership',
              'work_record,work_universe,role,order_enabled,order_input',
              binding,
            ).map(
              (r) => SagaMembershipInput(
                work: ExpressionReferenceInput(
                  record: _text(r, 'work_record'),
                  universe: _text(r, 'work_universe'),
                ),
                role: _text(r, 'role'),
                orderEnabled: r['order_enabled'] == 1,
                order: _text(r, 'order_input'),
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

  void _write(EditorFormScope scope, SavedSagaForm saved) {
    final binding = _binding(scope), form = saved.form;
    final values = <Object?>[
      ...binding,
      saved.generation.toString(),
      form.baseRevision.value,
      form.clientRef,
      form.title,
      form.membershipTarget?.record,
      form.membershipTarget?.universe,
      form.expectedRecordVersion?.value,
      form.rationale,
      form.draftVersion?.toString(),
    ];
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO saga_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      values,
    );
    _db.execute('DELETE FROM saga_label WHERE $_where', binding);
    for (var i = 0; i < form.labels.length; i++) {
      final row = form.labels[i];
      _db.execute('INSERT INTO saga_label VALUES(?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        row.language,
        row.text,
      ]);
    }
    _db.execute('DELETE FROM saga_membership WHERE $_where', binding);
    for (var i = 0; i < form.memberships.length; i++) {
      final row = form.memberships[i];
      _db.execute(
        'INSERT INTO saga_membership VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...binding,
          i,
          row.work.record,
          row.work.universe,
          row.role,
          row.orderEnabled ? 1 : 0,
          row.order,
        ],
      );
    }
  }

  void _validate(EditorFormScope scope, UnfinishedSagaForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Saga form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
  }

  SavedSagaForm? load(EditorFormScope scope) {
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

  SavedSagaForm save(
    EditorFormScope scope,
    UnfinishedSagaForm form,
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
      final saved = SavedSagaForm(
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
