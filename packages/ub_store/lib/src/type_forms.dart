import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';
import 'catalog.dart';
import 'relational.dart';
import 'recovery_domain_rows.dart';

const _columns =
    'instance,profile,universe,continuity,context,editor_key,generation,base_revision,client_ref,namespace,key,name,parent_choice,applicability_choice,rationale,classification_executable,draft_version';
const _currentColumns =
    '$_columns,target_record,target_universe,expected_record_version,original,parent_resolution';
const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,namespace,key,name,parent_choice,applicability_choice,rationale,classification_executable,draft_version,target_record,target_universe,expected_record_version,original,parent_resolution';
final _originalModel = recoveryPayloadModel(RecordKind.entityType.wireName);
final _domains = RecoveryDomainSchema([_originalModel]);
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _schema =
    '''
CREATE TABLE type_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, generation TEXT NOT NULL,
 base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, namespace TEXT NOT NULL,
 key TEXT NOT NULL, name TEXT NOT NULL, parent_choice TEXT NOT NULL,
 applicability_choice TEXT NOT NULL, rationale TEXT NOT NULL,
 classification_executable INTEGER CHECK(classification_executable IN (0,1)),
 draft_version TEXT,target_record TEXT,target_universe TEXT,expected_record_version TEXT,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),parent_resolution TEXT NOT NULL,
 CHECK(target_record IS NOT NULL OR target_universe IS NULL),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE type_form_world (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES type_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE
) STRICT;
CREATE TABLE type_form_label (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),language TEXT NOT NULL,label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES type_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
${_domains.statements.join('\n')}
PRAGMA user_version=4;
''';

String _projection(String columns) => columns
    .split(',')
    .map(
      (c) => {'ordinal', 'classification_executable', 'original'}.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row r, String column) => decodeExactUtf8(r[column] as List<int>);

/// Device-private incomplete type input, separate from canon and world forms.
final class TypeFormRecoveryStore {
  TypeFormRecoveryStore._(this._db);
  final Database _db;

  static TypeFormRecoveryStore open(String path) {
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
      return TypeFormRecoveryStore._(db);
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
      'type_form': _currentColumns,
      'type_form_world': '$_keys,ordinal,world',
      'type_form_label': '$_keys,ordinal,language,label_text',
    };
    final current =
        version == 4 &&
        tables.length == expected.length + _domains.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domains.matches(db);
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
        scope.typeClientRef == '') {
      throw const FormatException('Choose the type form context.');
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

  SavedTypeForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_projection(_currentColumns)} FROM type_form WHERE $_where',
          _binding(scope),
        );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final labels = _db.select(
      'SELECT ordinal,${_projection('language,label_text')} FROM type_form_label WHERE $_where ORDER BY ordinal',
      binding,
    );
    final worlds = _db.select(
      'SELECT ordinal,${_projection('world')} FROM type_form_world WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (final list in [labels, worlds]) {
      for (var i = 0; i < list.length; i++) {
        if (list[i]['ordinal'] != i) {
          throw const FormatException('Incomplete type input order');
        }
      }
    }
    return SavedTypeForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedTypeForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        namespace: _text(r, 'namespace'),
        key: _text(r, 'key'),
        name: _text(r, 'name'),
        parentChoice: _text(r, 'parent_choice'),
        applicabilityChoice: _text(r, 'applicability_choice'),
        rationale: _text(r, 'rationale'),
        classificationExecutable: r['classification_executable'] == null
            ? null
            : r['classification_executable'] == 1,
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
        revisionTarget: r['target_record'] == null
            ? null
            : RecordRef(
                record: RecordId.parse(_text(r, 'target_record')),
                universe: r['target_universe'] == null
                    ? null
                    : UniverseId.parse(_text(r, 'target_universe')),
              ),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        original: r['original'] == null
            ? null
            : EntityTypeRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        parentResolution: _text(r, 'parent_resolution'),
        labels: labels.map(
          (l) => PropertyLabelInput(
            language: _text(l, 'language'),
            text: _text(l, 'label_text'),
          ),
        ),
        worlds: worlds.map((w) => WorldId.parse(_text(w, 'world'))),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedTypeForm saved) {
    final binding = _binding(scope), f = saved.form;
    final old = _db.select(
      'SELECT original FROM type_form WHERE $_where',
      binding,
    );
    final original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire()),
        columns = _currentColumns.split(',');
    _db.execute(
      'INSERT INTO type_form VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.namespace,
        f.key,
        f.name,
        f.parentChoice,
        f.applicabilityChoice,
        f.rationale,
        f.classificationExecutable == null
            ? null
            : f.classificationExecutable!
            ? 1
            : 0,
        f.draftVersion?.toString(),
        f.revisionTarget?.record.value,
        f.revisionTarget?.universe?.value,
        f.expectedRecordVersion?.value,
        original,
        f.parentResolution,
      ],
    );
    _db.execute('DELETE FROM type_form_world WHERE $_where', binding);
    _db.execute('DELETE FROM type_form_label WHERE $_where', binding);
    for (var i = 0; i < f.worlds.length; i++) {
      _db.execute('INSERT INTO type_form_world VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.worlds[i].value,
      ]);
    }
    for (var i = 0; i < f.labels.length; i++) {
      final l = f.labels[i];
      _db.execute('INSERT INTO type_form_label VALUES(?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        l.language,
        l.text,
      ]);
    }
    if (old.isNotEmpty) {
      _domains.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  SavedTypeForm? load(EditorFormScope scope) {
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

  void _validate(EditorFormScope scope, UnfinishedTypeForm form) {
    if (scope.representedContext != form.representedContext ||
        (scope.typeClientRef != null &&
            scope.typeClientRef != form.clientRef)) {
      throw const FormatException('Type form context does not match.');
    }
    for (final text in [
      form.clientRef,
      form.namespace,
      form.key,
      form.name,
      form.parentChoice,
      form.applicabilityChoice,
      form.rationale,
      form.parentResolution,
      for (final l in form.labels) ...[l.language, l.text],
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.revisionFields;
  }

  SavedTypeForm save(
    EditorFormScope scope,
    UnfinishedTypeForm form,
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
      final saved = SavedTypeForm(
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
