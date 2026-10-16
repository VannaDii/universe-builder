import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,namespace,definition_key,target_record,target_universe,expected_record_version,rationale,draft_version,has_original,original_namespace,original_key';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE value_definition_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, namespace TEXT NOT NULL, definition_key TEXT NOT NULL,
 target_record TEXT, target_universe TEXT, expected_record_version TEXT, rationale TEXT NOT NULL, draft_version TEXT,
 has_original INTEGER NOT NULL CHECK(has_original IN (0,1)), original_namespace TEXT, original_key TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 CHECK((has_original=0 AND original_namespace IS NULL AND original_key IS NULL) OR (has_original=1 AND original_namespace IS NOT NULL AND original_key IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE value_definition_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES value_definition_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE value_definition_field (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), field_name TEXT NOT NULL, is_required INTEGER NOT NULL CHECK(is_required IN (0,1)), allows_unknown INTEGER NOT NULL CHECK(allows_unknown IN (0,1)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES value_definition_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE value_definition_shape (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), field_ordinal INTEGER NOT NULL, depth INTEGER NOT NULL CHECK(depth>=0), shape_kind TEXT NOT NULL, unit_input TEXT, definition_input TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,field_ordinal,depth),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,list_kind,field_ordinal) REFERENCES value_definition_field(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal)
) STRICT;
CREATE TABLE value_definition_subject (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), field_ordinal INTEGER NOT NULL, depth INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), subject_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,field_ordinal,depth,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,list_kind,field_ordinal,depth) REFERENCES value_definition_shape(instance,profile,universe,continuity,context,editor_key,list_kind,field_ordinal,depth)
) STRICT;
CREATE UNIQUE INDEX value_definition_original_language ON value_definition_label(instance,profile,universe,continuity,context,editor_key,language) WHERE list_kind='original';
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'field_ordinal',
            'depth',
            'is_required',
            'allows_unknown',
            'has_original',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named value-definition fields, separate from canon.
final class ValueDefinitionFormRecoveryStore {
  ValueDefinitionFormRecoveryStore._(this._db);
  final Database _db;

  static ValueDefinitionFormRecoveryStore open(String path) {
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
      return ValueDefinitionFormRecoveryStore._(db);
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
        tables.length == 5 &&
        columns('value_definition_form') == '$_keys,$_fields' &&
        columns('value_definition_label') ==
            '$_keys,list_kind,ordinal,language,label_text' &&
        columns('value_definition_field') ==
            '$_keys,list_kind,ordinal,field_name,is_required,allows_unknown' &&
        columns('value_definition_shape') ==
            '$_keys,list_kind,field_ordinal,depth,shape_kind,unit_input,definition_input' &&
        columns('value_definition_subject') ==
            '$_keys,list_kind,field_ordinal,depth,ordinal,subject_input';
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
      throw const FormatException('Choose the value definition context.');
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
    String kind, {
    int? field,
    int? depth,
  }) {
    final order = table == 'shape' ? 'depth' : 'ordinal';
    final rows = _db.select(
      'SELECT $order,${_textProjection(columns)} FROM value_definition_$table WHERE $_where AND list_kind=?${field == null ? '' : ' AND field_ordinal=?'}${depth == null ? '' : ' AND depth=?'} ORDER BY $order',
      [...binding, kind, ?field, ?depth],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i][order] != i) {
        throw const FormatException(
          'Incomplete value-definition input row order.',
        );
      }
    }
    return rows;
  }

  List<String> _subjects(
    List<String> binding,
    String kind,
    int field,
    int depth,
  ) => _rows(
    'subject',
    'subject_input',
    binding,
    kind,
    field: field,
    depth: depth,
  ).map((r) => _text(r, 'subject_input')).toList();
  ValueShapeInput _inputShape(List<String> binding, int field) {
    final rows = _rows(
      'shape',
      'shape_kind,unit_input,definition_input',
      binding,
      'input',
      field: field,
    );
    ValueShapeInput? shape;
    for (final row in rows.reversed) {
      shape = ValueShapeInput(
        kind: _text(row, 'shape_kind'),
        unit: _text(row, 'unit_input'),
        definition: _text(row, 'definition_input'),
        subjectTypes: _subjects(binding, 'input', field, row['depth'] as int),
        item: shape,
      );
    }
    return shape ?? (throw const FormatException('Missing value shape input.'));
  }

  ValueShape _originalShape(List<String> binding, int field) {
    final rows = _rows(
      'shape',
      'shape_kind,unit_input,definition_input',
      binding,
      'original',
      field: field,
    );
    CanonicalObject? shape;
    for (final row in rows.reversed) {
      final kind = _text(row, 'shape_kind');
      shape = CanonicalObject([
        MapEntry('kind', CanonicalString(kind)),
        if (kind == 'quantity' || kind == 'range')
          MapEntry(
            'unit',
            row['unit_input'] == null
                ? const CanonicalNull()
                : CanonicalString(_text(row, 'unit_input')),
          ),
        if (kind == 'enum' || kind == 'structured')
          MapEntry(
            'definition',
            CanonicalString(_text(row, 'definition_input')),
          ),
        if (kind == 'entity_ref')
          MapEntry(
            'subject_types',
            CanonicalArray(
              _subjects(
                binding,
                'original',
                field,
                row['depth'] as int,
              ).map(CanonicalString.new),
            ),
          ),
        if (kind == 'sequence')
          MapEntry(
            'item',
            shape ?? (throw const FormatException('Missing sequence item.')),
          ),
      ]);
    }
    return ValueShape.fromWire(
      shape ?? (throw const FormatException('Missing original shape.')),
    );
  }

  SavedValueDefinitionForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM value_definition_form WHERE $_where',
      binding,
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
    List<Row> fields(String kind) =>
        _rows('field', 'field_name,is_required,allows_unknown', binding, kind);
    return SavedValueDefinitionForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedValueDefinitionForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        namespace: _text(row, 'namespace'),
        key: _text(row, 'definition_key'),
        labels: labels('input'),
        fields: fields('input').map(
          (r) => ValueDefinitionFieldInput(
            name: _text(r, 'field_name'),
            required: r['is_required'] == 1,
            allowsUnknown: r['allows_unknown'] == 1,
            shape: _inputShape(binding, r['ordinal'] as int),
          ),
        ),
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
            : ValueDefinitionRecord(
                namespace: _text(row, 'original_namespace'),
                key: _text(row, 'original_key'),
                labels: {
                  for (final label in labels('original'))
                    label.language: label.text,
                },
                fields: fields('original').map(
                  (r) => ValueDefinitionField(
                    name: _text(r, 'field_name'),
                    required: r['is_required'] == 1,
                    allowsUnknown: r['allows_unknown'] == 1,
                    shape: _originalShape(binding, r['ordinal'] as int),
                  ),
                ),
              ),
      ),
    );
  }

  void _shape(
    List<String> binding,
    String kind,
    int field,
    int depth,
    String shapeKind,
    String? unit,
    String? definition,
    List<String> subjects,
  ) {
    _db.execute(
      'INSERT INTO value_definition_shape VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
      [...binding, kind, field, depth, shapeKind, unit, definition],
    );
    for (var i = 0; i < subjects.length; i++) {
      _db.execute(
        'INSERT INTO value_definition_subject VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [...binding, kind, field, depth, i, subjects[i]],
      );
    }
  }

  void _write(EditorFormScope scope, SavedValueDefinitionForm saved) {
    final binding = _binding(scope),
        form = saved.form,
        original = form.original;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO value_definition_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.namespace,
        form.key,
        form.revisionTarget?.record,
        form.revisionTarget?.universe,
        form.expectedRecordVersion?.value,
        form.rationale,
        form.draftVersion?.toString(),
        original == null ? 0 : 1,
        original?.namespace,
        original?.key,
      ],
    );
    for (final table in ['subject', 'shape', 'field', 'label']) {
      _db.execute('DELETE FROM value_definition_$table WHERE $_where', binding);
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
        _db.execute(
          'INSERT INTO value_definition_label VALUES(?,?,?,?,?,?,?,?,?,?)',
          [...binding, list.key, i, label.language, label.text],
        );
      }
    }
    for (var i = 0; i < form.fields.length; i++) {
      final field = form.fields[i];
      _db.execute(
        'INSERT INTO value_definition_field VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...binding,
          'input',
          i,
          field.name,
          field.required ? 1 : 0,
          field.allowsUnknown ? 1 : 0,
        ],
      );
      ValueShapeInput? shape = field.shape;
      var depth = 0;
      while (shape != null) {
        _shape(
          binding,
          'input',
          i,
          depth++,
          shape.kind,
          shape.unit,
          shape.definition,
          shape.subjectTypes,
        );
        shape = shape.item;
      }
    }
    final fields = original?.fields ?? <ValueDefinitionField>[];
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      _db.execute(
        'INSERT INTO value_definition_field VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...binding,
          'original',
          i,
          field.name,
          field.required ? 1 : 0,
          field.allowsUnknown ? 1 : 0,
        ],
      );
      ValueShape? shape = field.shape;
      var depth = 0;
      while (shape != null) {
        final wire = Map.fromEntries(shape.toWire().fields);
        _shape(
          binding,
          'original',
          i,
          depth++,
          (wire['kind'] as CanonicalString).value,
          wire['unit'] is CanonicalString
              ? (wire['unit'] as CanonicalString).value
              : null,
          wire['definition'] is CanonicalString
              ? (wire['definition'] as CanonicalString).value
              : null,
          wire['subject_types'] is CanonicalArray
              ? (wire['subject_types'] as CanonicalArray).items
                    .map((v) => (v as CanonicalString).value)
                    .toList()
              : [],
        );
        shape = shape is SequenceShape ? shape.item : null;
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedValueDefinitionForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException(
        'Value definition form context does not match.',
      );
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedValueDefinitionForm? load(EditorFormScope scope) {
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

  SavedValueDefinitionForm save(
    EditorFormScope scope,
    UnfinishedValueDefinitionForm form,
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
      final saved = SavedValueDefinitionForm(
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
