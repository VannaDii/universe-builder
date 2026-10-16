import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';
import 'catalog.dart';
import 'relational.dart';
import 'recovery_domain_rows.dart';
import 'recovery_value_inputs.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,work_kind,title,rationale,original,target_record,target_universe,expected_record_version,association_original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('work');
final _domainStorage = RecoveryDomainSchema([
  _originalModel,
  'WorldAssociation',
]);
final _schema =
    """
CREATE TABLE work_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, work_kind TEXT NOT NULL, title TEXT NOT NULL, rationale TEXT NOT NULL,
 original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id), target_record TEXT, target_universe TEXT, expected_record_version TEXT, association_original INTEGER REFERENCES "${BodyCatalog.instance.model('WorldAssociation').table}"(__row_id), draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE work_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES work_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE work_source (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), record_input TEXT NOT NULL, universe_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES work_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE work_version (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), version_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES work_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE work_association (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), world_input TEXT NOT NULL, role_input TEXT NOT NULL, temporal INTEGER NOT NULL REFERENCES work_temporal(id), original_ordinal TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES work_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE work_association_qualifier (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 association_ordinal INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), input_root INTEGER NOT NULL REFERENCES work_qualifier(id),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,association_ordinal,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,association_ordinal) REFERENCES work_association(instance,profile,universe,continuity,context,editor_key,ordinal)
) STRICT;
${RecoveryValueInputs.schema('work')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'temporal',
            'original',
            'association_original',
            'input_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named work fields, separate from canon.
final class WorkFormRecoveryStore {
  WorkFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'work');

  static WorkFormRecoveryStore open(String path) {
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
      return WorkFormRecoveryStore._(db);
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
    final expected = {
      'work_form': '$_keys,$_fields',
      'work_label': '$_keys,ordinal,language,label_text',
      'work_source': '$_keys,ordinal,record_input,universe_input',
      'work_version': '$_keys,ordinal,version_input',
      'work_association':
          '$_keys,ordinal,world_input,role_input,temporal,original_ordinal',
      'work_association_qualifier':
          '$_keys,association_ordinal,ordinal,input_root',
      ...RecoveryValueInputs.columns('work'),
    };
    final current =
        version == 2 &&
        tables.length == expected.length + _domainStorage.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domainStorage.matches(db);
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
      throw const FormatException('Choose the work context.');
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

  List<Row> _ordered(
    String table,
    String columns,
    List<String> binding, {
    int? association,
  }) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM work_$table WHERE $_where${association == null ? '' : ' AND association_ordinal=?'} ORDER BY ordinal',
      [...binding, ?association],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete work input order');
      }
    }
    return rows;
  }

  SavedWorkForm? _read(EditorFormScope scope) {
    final binding = _binding(scope), codec = RelationalCodec(_db);
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM work_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedWorkForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedWorkForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        kind: _text(r, 'work_kind'),
        title: _text(r, 'title'),
        rationale: _text(r, 'rationale'),
        labels: _ordered('label', 'language,label_text', binding).map(
          (l) => PropertyLabelInput(
            language: _text(l, 'language'),
            text: _text(l, 'label_text'),
          ),
        ),
        sources: _ordered('source', 'record_input,universe_input', binding).map(
          (s) => ExpressionReferenceInput(
            record: _text(s, 'record_input'),
            universe: _text(s, 'universe_input'),
          ),
        ),
        versions: _ordered(
          'version',
          'version_input',
          binding,
        ).map((v) => _text(v, 'version_input')),
        associations:
            _ordered(
              'association',
              'world_input,role_input,temporal,original_ordinal',
              binding,
            ).map(
              (a) => WorkAssociationInput(
                world: _text(a, 'world_input'),
                role: _text(a, 'role_input'),
                validity: _inputs.readTemporal(a['temporal'] as int, 0),
                originalOrdinal: a['original_ordinal'] == null
                    ? null
                    : int.parse(_text(a, 'original_ordinal')),
                qualifiers: _ordered(
                  'association_qualifier',
                  'input_root',
                  binding,
                  association: a['ordinal'] as int,
                ).map((q) => _inputs.readQualifier(q['input_root'] as int, 0)),
              ),
            ),
        original: r['original'] == null
            ? null
            : WorkRecord.fromWire(codec.get(_originalModel, r['original'])),
        associationTarget: r['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(r, 'target_record'),
                universe: _text(r, 'target_universe'),
              ),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        associationOriginal: r['association_original'] == null
            ? null
            : WorldAssociation.fromWire(
                codec.get('WorldAssociation', r['association_original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedWorkForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        codec = RelationalCodec(_db);
    final old = _db.select(
      'SELECT original,association_original FROM work_form WHERE $_where',
      binding,
    );
    final oldAssociations = _db.select(
      'SELECT temporal FROM work_association WHERE $_where',
      binding,
    );
    final oldQualifiers = _db.select(
      'SELECT input_root FROM work_association_qualifier WHERE $_where',
      binding,
    );
    final original = f.original == null
            ? null
            : codec.put(_originalModel, f.original!.toWire()),
        associationOriginal = f.associationOriginal == null
            ? null
            : codec.put('WorldAssociation', f.associationOriginal!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO work_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.kind,
        f.title,
        f.rationale,
        original,
        f.associationTarget?.record,
        f.associationTarget?.universe,
        f.expectedRecordVersion?.value,
        associationOriginal,
        f.draftVersion?.toString(),
      ],
    );
    for (final table in [
      'association_qualifier',
      'association',
      'label',
      'source',
      'version',
    ]) {
      _db.execute('DELETE FROM work_$table WHERE $_where', binding);
    }
    for (var i = 0; i < f.labels.length; i++) {
      _db.execute('INSERT INTO work_label VALUES(?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.labels[i].language,
        f.labels[i].text,
      ]);
    }
    for (var i = 0; i < f.sources.length; i++) {
      _db.execute('INSERT INTO work_source VALUES(?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.sources[i].record,
        f.sources[i].universe,
      ]);
    }
    for (var i = 0; i < f.versions.length; i++) {
      _db.execute('INSERT INTO work_version VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.versions[i],
      ]);
    }
    for (var i = 0; i < f.associations.length; i++) {
      final a = f.associations[i],
          temporal = _inputs.writeTemporal(f.associations[i].validity, 0);
      _db.execute(
        'INSERT INTO work_association VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...binding,
          i,
          a.world,
          a.role,
          temporal,
          a.originalOrdinal?.toString(),
        ],
      );
      for (var j = 0; j < a.qualifiers.length; j++) {
        final root = _inputs.writeQualifier(a.qualifiers[j], 0);
        _db.execute(
          'INSERT INTO work_association_qualifier VALUES(?,?,?,?,?,?,?,?,?)',
          [...binding, i, j, root],
        );
      }
    }
    for (final q in oldQualifiers) {
      _inputs.deleteQualifier(q['input_root'] as int);
    }
    for (final a in oldAssociations) {
      _inputs.deleteTemporal(a['temporal'] as int);
    }
    if (old.isNotEmpty) {
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
      _domainStorage.deleteOwned(
        _db,
        'WorldAssociation',
        old.single['association_original'],
      );
    }
  }

  void _validate(EditorFormScope scope, UnfinishedWorkForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Work form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedWorkForm? load(EditorFormScope scope) {
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

  SavedWorkForm save(
    EditorFormScope scope,
    UnfinishedWorkForm form,
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
      final saved = SavedWorkForm(
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
