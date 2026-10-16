import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,namespace,property_key,multiplicity,persistence,has_unit_dimension,unit_dimension,has_inverse,inverse_input,exclusive,symmetric,transitive,target_record,target_universe,expected_record_version,rationale,draft_version,has_original,original_namespace,original_key,original_multiplicity,original_persistence,original_unit_dimension,original_inverse,original_exclusive,original_symmetric,original_transitive';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE property_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL,
 base_revision TEXT NOT NULL,
 client_ref TEXT NOT NULL,
 namespace TEXT NOT NULL,
 property_key TEXT NOT NULL,
 multiplicity TEXT NOT NULL,
 persistence TEXT NOT NULL,
 has_unit_dimension INTEGER NOT NULL CHECK(has_unit_dimension IN (0,1)),
 unit_dimension TEXT NOT NULL,
 has_inverse INTEGER NOT NULL CHECK(has_inverse IN (0,1)),
 inverse_input TEXT NOT NULL,
 exclusive INTEGER NOT NULL CHECK(exclusive IN (0,1)),
 symmetric INTEGER NOT NULL CHECK(symmetric IN (0,1)),
 transitive INTEGER NOT NULL CHECK(transitive IN (0,1)),
 target_record TEXT,
 target_universe TEXT,
 expected_record_version TEXT,
 rationale TEXT NOT NULL,
 draft_version TEXT,
 has_original INTEGER NOT NULL CHECK(has_original IN (0,1)),
 original_namespace TEXT,
 original_key TEXT,
 original_multiplicity TEXT,
 original_persistence TEXT,
 original_unit_dimension TEXT,
 original_inverse TEXT,
 original_exclusive INTEGER CHECK(original_exclusive IN (0,1)),
 original_symmetric INTEGER CHECK(original_symmetric IN (0,1)),
 original_transitive INTEGER CHECK(original_transitive IN (0,1)),
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 CHECK((has_original=0 AND original_namespace IS NULL AND original_key IS NULL AND original_multiplicity IS NULL AND original_persistence IS NULL AND original_exclusive IS NULL AND original_symmetric IS NULL AND original_transitive IS NULL AND original_unit_dimension IS NULL AND original_inverse IS NULL) OR (has_original=1 AND original_namespace IS NOT NULL AND original_key IS NOT NULL AND original_multiplicity IS NOT NULL AND original_persistence IS NOT NULL AND original_exclusive IS NOT NULL AND original_symmetric IS NOT NULL AND original_transitive IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE property_label(
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES property_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE property_subject_type(
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), subject_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES property_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE property_shape(
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), depth INTEGER NOT NULL CHECK(depth>=0), shape_kind TEXT NOT NULL, unit_input TEXT, definition_input TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,depth),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES property_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE property_subject(
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), depth INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), subject_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,depth,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,list_kind,depth) REFERENCES property_shape(instance,profile,universe,continuity,context,editor_key,list_kind,depth)
) STRICT;
CREATE UNIQUE INDEX property_original_language ON property_label(instance,profile,universe,continuity,context,editor_key,language) WHERE list_kind='original';
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'has_inverse',
            'exclusive',
            'symmetric',
            'has_original',
            'ordinal',
            'original_exclusive',
            'depth',
            'original_transitive',
            'transitive',
            'has_unit_dimension',
            'original_symmetric',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named property fields, separate from canon.
final class PropertyFormRecoveryStore {
  PropertyFormRecoveryStore._(this._db);
  final Database _db;

  static PropertyFormRecoveryStore open(String path) {
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
      return PropertyFormRecoveryStore._(db);
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
        columns('property_form') == '$_keys,$_fields' &&
        columns('property_label') ==
            '$_keys,list_kind,ordinal,language,label_text' &&
        columns('property_subject_type') ==
            '$_keys,list_kind,ordinal,subject_input' &&
        columns('property_shape') ==
            '$_keys,list_kind,depth,shape_kind,unit_input,definition_input' &&
        columns('property_subject') ==
            '$_keys,list_kind,depth,ordinal,subject_input';
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
      throw const FormatException('Choose the property context.');
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
    int? depth,
  }) {
    final order = table == 'shape' ? 'depth' : 'ordinal';
    final rows = _db.select(
      'SELECT $order,${_textProjection(columns)} FROM property_$table WHERE $_where AND list_kind=?${depth == null ? '' : ' AND depth=?'} ORDER BY $order',
      [...binding, kind, ?depth],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i][order] != i) {
        throw const FormatException('Incomplete property input row order.');
      }
    }
    return rows;
  }

  List<String> _subjects(List<String> binding, String kind, int depth) => _rows(
    'subject',
    'subject_input',
    binding,
    kind,
    depth: depth,
  ).map((r) => _text(r, 'subject_input')).toList();
  ValueShapeInput _inputShape(List<String> binding) {
    final rows = _rows(
      'shape',
      'shape_kind,unit_input,definition_input',
      binding,
      'input',
    );
    ValueShapeInput? shape;
    for (final row in rows.reversed) {
      shape = ValueShapeInput(
        kind: _text(row, 'shape_kind'),
        unit: _text(row, 'unit_input'),
        definition: _text(row, 'definition_input'),
        subjectTypes: _subjects(binding, 'input', row['depth'] as int),
        item: shape,
      );
    }
    return shape ?? (throw const FormatException('Missing value shape input.'));
  }

  ValueShape _originalShape(List<String> binding) {
    final rows = _rows(
      'shape',
      'shape_kind,unit_input,definition_input',
      binding,
      'original',
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

  SavedPropertyForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM property_form WHERE $_where',
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
    List<String> subjects(String kind) => _rows(
      'subject_type',
      'subject_input',
      binding,
      kind,
    ).map((r) => _text(r, 'subject_input')).toList();
    return SavedPropertyForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedPropertyForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        namespace: _text(row, 'namespace'),
        key: _text(row, 'property_key'),
        labels: labels('input'),
        subjectTypes: subjects('input'),
        shape: _inputShape(binding),
        multiplicity: _text(row, 'multiplicity'),
        persistence: _text(row, 'persistence'),
        hasUnitDimension: row['has_unit_dimension'] == 1,
        unitDimension: _text(row, 'unit_dimension'),
        hasInverse: row['has_inverse'] == 1,
        inverse: _text(row, 'inverse_input'),
        exclusive: row['exclusive'] == 1,
        symmetric: row['symmetric'] == 1,
        transitive: row['transitive'] == 1,
        revisionTarget: row['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(row, 'target_record'),
                universe: _text(row, 'target_universe'),
              ),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(row, 'expected_record_version')),
        rationale: _text(row, 'rationale'),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
        original: row['has_original'] == 0
            ? null
            : PropertyRecord(
                namespace: _text(row, 'original_namespace'),
                key: _text(row, 'original_key'),
                labels: {
                  for (final l in labels('original')) l.language: l.text,
                },
                subjectTypes: subjects('original').map(RecordId.parse),
                value: _originalShape(binding),
                multiplicity: Multiplicity.fromName(
                  _text(row, 'original_multiplicity'),
                ),
                persistence: PersistenceSemantics.fromWire(
                  CanonicalString(_text(row, 'original_persistence')),
                ),
                unitDimension: row['original_unit_dimension'] == null
                    ? null
                    : _text(row, 'original_unit_dimension'),
                inverse: row['original_inverse'] == null
                    ? null
                    : _text(row, 'original_inverse'),
                exclusive: row['original_exclusive'] == 1,
                symmetric: row['original_symmetric'] == 1,
                transitive: row['original_transitive'] == 1,
              ),
      ),
    );
  }

  void _shape(
    List<String> binding,
    String kind,
    int depth,
    String shapeKind,
    String? unit,
    String? definition,
    List<String> subjects,
  ) {
    _db.execute('INSERT INTO property_shape VALUES(?,?,?,?,?,?,?,?,?,?,?)', [
      ...binding,
      kind,
      depth,
      shapeKind,
      unit,
      definition,
    ]);
    for (var i = 0; i < subjects.length; i++) {
      _db.execute('INSERT INTO property_subject VALUES(?,?,?,?,?,?,?,?,?,?)', [
        ...binding,
        kind,
        depth,
        i,
        subjects[i],
      ]);
    }
  }

  void _write(EditorFormScope scope, SavedPropertyForm saved) {
    final binding = _binding(scope),
        form = saved.form,
        original = form.original;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO property_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.namespace,
        form.key,
        form.multiplicity,
        form.persistence,
        form.hasUnitDimension ? 1 : 0,
        form.unitDimension,
        form.hasInverse ? 1 : 0,
        form.inverse,
        form.exclusive ? 1 : 0,
        form.symmetric ? 1 : 0,
        form.transitive ? 1 : 0,
        form.revisionTarget?.record,
        form.revisionTarget?.universe,
        form.expectedRecordVersion?.value,
        form.rationale,
        form.draftVersion?.toString(),
        original == null ? 0 : 1,
        original?.namespace,
        original?.key,
        original?.multiplicity.name,
        original?.persistence.wireName,
        original?.unitDimension,
        original?.inverse,
        original == null ? null : (original.exclusive ? 1 : 0),
        original == null ? null : (original.symmetric ? 1 : 0),
        original == null ? null : (original.transitive ? 1 : 0),
      ],
    );
    for (final table in ['subject', 'shape', 'subject_type', 'label']) {
      _db.execute('DELETE FROM property_$table WHERE $_where', binding);
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
        _db.execute('INSERT INTO property_label VALUES(?,?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          label.language,
          label.text,
        ]);
      }
    }
    for (final list in {
      'input': form.subjectTypes,
      'original':
          original?.subjectTypes.map((id) => id.value).toList() ?? <String>[],
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        _db.execute(
          'INSERT INTO property_subject_type VALUES(?,?,?,?,?,?,?,?,?)',
          [...binding, list.key, i, list.value[i]],
        );
      }
    }
    ValueShapeInput? input = form.shape;
    var depth = 0;
    while (input != null) {
      _shape(
        binding,
        'input',
        depth++,
        input.kind,
        input.unit,
        input.definition,
        input.subjectTypes,
      );
      input = input.item;
    }
    ValueShape? value = original?.value;
    depth = 0;
    while (value != null) {
      final wire = Map.fromEntries(value.toWire().fields);
      _shape(
        binding,
        'original',
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
      value = value is SequenceShape ? value.item : null;
    }
  }

  void _validate(EditorFormScope scope, UnfinishedPropertyForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Property form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedPropertyForm? load(EditorFormScope scope) {
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

  SavedPropertyForm save(
    EditorFormScope scope,
    UnfinishedPropertyForm form,
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
      final saved = SavedPropertyForm(
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
