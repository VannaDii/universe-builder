import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,namespace,calendar_key,has_epoch,epoch_input,target_record,target_universe,expected_record_version,rationale,draft_version,has_original,original_namespace,original_key,original_epoch';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE calendar_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, namespace TEXT NOT NULL, calendar_key TEXT NOT NULL,
 has_epoch INTEGER NOT NULL CHECK(has_epoch IN (0,1)), epoch_input TEXT NOT NULL,
 target_record TEXT, target_universe TEXT, expected_record_version TEXT, rationale TEXT NOT NULL, draft_version TEXT,
 has_original INTEGER NOT NULL CHECK(has_original IN (0,1)), original_namespace TEXT, original_key TEXT, original_epoch TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 CHECK((has_original=0 AND original_namespace IS NULL AND original_key IS NULL AND original_epoch IS NULL) OR (has_original=1 AND original_namespace IS NOT NULL AND original_key IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE calendar_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES calendar_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE UNIQUE INDEX calendar_original_language ON calendar_label(instance,profile,universe,continuity,context,editor_key,language) WHERE list_kind='original';
CREATE TABLE calendar_unit (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), unit_name TEXT NOT NULL, structure TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES calendar_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE UNIQUE INDEX calendar_original_unit ON calendar_unit(instance,profile,universe,continuity,context,editor_key,unit_name) WHERE list_kind='original';
CREATE TABLE calendar_conversion (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), target_input TEXT NOT NULL,
 has_expression INTEGER NOT NULL CHECK(has_expression IN (0,1)), expression_input TEXT NOT NULL, is_valid INTEGER NOT NULL CHECK(is_valid IN (0,1)),
 CHECK(list_kind='input' OR has_expression=1 OR expression_input=''),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES calendar_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'has_original',
            'has_epoch',
            'has_expression',
            'is_valid',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named calendar fields, separate from canon.
final class CalendarFormRecoveryStore {
  CalendarFormRecoveryStore._(this._db);
  final Database _db;

  static CalendarFormRecoveryStore open(String path) {
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
      return CalendarFormRecoveryStore._(db);
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
        tables.length == 4 &&
        columns('calendar_form') == '$_keys,$_fields' &&
        columns('calendar_label') ==
            '$_keys,list_kind,ordinal,language,label_text' &&
        columns('calendar_unit') ==
            '$_keys,list_kind,ordinal,unit_name,structure' &&
        columns('calendar_conversion') ==
            '$_keys,list_kind,ordinal,target_input,has_expression,expression_input,is_valid';
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
      throw const FormatException('Choose the calendar definition context.');
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

  List<Row> _rows(
    String table,
    String columns,
    List<String> binding,
    String kind,
  ) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM calendar_$table WHERE $_where AND list_kind=? ORDER BY ordinal',
      [...binding, kind],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete calendar input order.');
      }
    }
    return rows;
  }

  SavedCalendarForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_textProjection('$_keys,$_fields')} FROM calendar_form WHERE $_where',
          _binding(scope),
        );
    if (rows.isEmpty) return null;
    final row = rows.single;
    List<PropertyLabelInput> labels(String kind) =>
        _rows('label', 'language,label_text', binding, kind)
            .map(
              (r) => PropertyLabelInput(
                language: _text(r, 'language'),
                text: _text(r, 'label_text'),
              ),
            )
            .toList();
    List<CalendarUnitInput> units(String kind) =>
        _rows('unit', 'unit_name,structure', binding, kind)
            .map(
              (r) => CalendarUnitInput(
                name: _text(r, 'unit_name'),
                structure: _text(r, 'structure'),
              ),
            )
            .toList();
    List<CalendarConversionInput> conversions(String kind) =>
        _rows(
              'conversion',
              'target_input,has_expression,expression_input,is_valid',
              binding,
              kind,
            )
            .map(
              (r) => CalendarConversionInput(
                target: _text(r, 'target_input'),
                hasExpression: r['has_expression'] == 1,
                expression: _text(r, 'expression_input'),
                valid: r['is_valid'] == 1,
              ),
            )
            .toList();
    return SavedCalendarForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedCalendarForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        namespace: _text(row, 'namespace'),
        key: _text(row, 'calendar_key'),
        labels: labels('input'),
        hasEpoch: row['has_epoch'] == 1,
        epoch: _text(row, 'epoch_input'),
        units: units('input'),
        conversions: conversions('input'),
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
            : CalendarRecord(
                namespace: _text(row, 'original_namespace'),
                key: _text(row, 'original_key'),
                labels: {
                  for (final l in labels('original')) l.language: l.text,
                },
                epoch: row['original_epoch'] == null
                    ? null
                    : _text(row, 'original_epoch'),
                unitStructure: {
                  for (final u in units('original')) u.name: u.structure,
                },
                conversions: conversions('original').map(
                  (c) => CalendarConversion(
                    target: CalendarId.parse(c.target),
                    expression: c.hasExpression ? c.expression : null,
                    valid: c.valid,
                  ),
                ),
              ),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedCalendarForm saved) {
    final binding = _binding(scope),
        form = saved.form,
        original = form.original;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO calendar_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.namespace,
        form.key,
        form.hasEpoch ? 1 : 0,
        form.epoch,
        form.revisionTarget?.record,
        form.revisionTarget?.universe,
        form.expectedRecordVersion?.value,
        form.rationale,
        form.draftVersion?.toString(),
        original == null ? 0 : 1,
        original?.namespace,
        original?.key,
        original?.epoch,
      ],
    );
    for (final table in ['conversion', 'unit', 'label']) {
      _db.execute('DELETE FROM calendar_$table WHERE $_where', binding);
    }
    for (final list in {
      'input': form.labels,
      'original':
          original?.labels.entries
              .map((e) => PropertyLabelInput(language: e.key, text: e.value))
              .toList() ??
          <PropertyLabelInput>[],
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final label = list.value[i];
        _db.execute('INSERT INTO calendar_label VALUES(?,?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          label.language,
          label.text,
        ]);
      }
    }
    for (final list in {
      'input': form.units,
      'original':
          original?.unitStructure.entries
              .map((e) => CalendarUnitInput(name: e.key, structure: e.value))
              .toList() ??
          <CalendarUnitInput>[],
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final unit = list.value[i];
        _db.execute('INSERT INTO calendar_unit VALUES(?,?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          unit.name,
          unit.structure,
        ]);
      }
    }
    for (final list in {
      'input': form.conversions,
      'original':
          original?.conversions
              .map(
                (c) => CalendarConversionInput(
                  target: c.target.value,
                  hasExpression: c.expression != null,
                  expression: c.expression ?? '',
                  valid: c.valid,
                ),
              )
              .toList() ??
          <CalendarConversionInput>[],
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final conversion = list.value[i];
        _db.execute(
          'INSERT INTO calendar_conversion VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            ...binding,
            list.key,
            i,
            conversion.target,
            conversion.hasExpression ? 1 : 0,
            conversion.expression,
            conversion.valid ? 1 : 0,
          ],
        );
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedCalendarForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Calendar form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedCalendarForm? load(EditorFormScope scope) {
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

  SavedCalendarForm save(
    EditorFormScope scope,
    UnfinishedCalendarForm form,
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
      final saved = SavedCalendarForm(
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
