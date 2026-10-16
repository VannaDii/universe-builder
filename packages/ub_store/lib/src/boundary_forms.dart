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
import 'recovery_expression_inputs.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,boundary_key,area_kind,record_record,record_universe,predicate_input,subject_enabled,subject_record,subject_universe,category_input,mode_input,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,temporal,rationale,original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('boundary');
final _domainStorage = RecoveryDomainSchema([
  _originalModel,
  'Expr',
  'Operand',
]);
final _schema =
    """
CREATE TABLE boundary_form (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,boundary_key TEXT NOT NULL,area_kind TEXT NOT NULL,record_record TEXT NOT NULL,record_universe TEXT NOT NULL,predicate_input TEXT NOT NULL,subject_enabled INTEGER NOT NULL CHECK(subject_enabled IN (0,1)),subject_record TEXT NOT NULL,subject_universe TEXT NOT NULL,category_input TEXT NOT NULL,mode_input TEXT NOT NULL,
 scope_applicability TEXT NOT NULL,scope_context_record TEXT NOT NULL,scope_context_universe TEXT NOT NULL,scope_has_realm INTEGER NOT NULL CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT NOT NULL,scope_realm_universe TEXT NOT NULL,temporal INTEGER NOT NULL REFERENCES boundary_temporal(id),rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE boundary_world (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES boundary_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE boundary_constraint (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),expression_root INTEGER NOT NULL REFERENCES boundary_expression(id),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES boundary_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('boundary')}
${RecoveryExpressionInputs.schema('boundary')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'expression_root',
            'ordinal',
            'original',
            'scope_has_realm',
            'subject_enabled',
            'temporal',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named boundary fields, separate from canon.
final class BoundaryFormRecoveryStore {
  BoundaryFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'boundary');
  late final _expressions = RecoveryExpressionInputs(
    _db,
    'boundary',
    _domainStorage,
  );

  static BoundaryFormRecoveryStore open(String path) {
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
      return BoundaryFormRecoveryStore._(db);
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
      'boundary_form': '$_keys,$_fields',
      'boundary_world': '$_keys,ordinal,world_input',
      'boundary_constraint': '$_keys,ordinal,expression_root',
      ...RecoveryValueInputs.columns('boundary'),
      ...RecoveryExpressionInputs.columns('boundary'),
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
      throw const FormatException('Choose the boundary context.');
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

  List<Row> _ordered(String table, String columns, List<String> binding) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM boundary_$table WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete boundary input order');
      }
    }
    return rows;
  }

  ExpressionReferenceInput _ref(Row r, String prefix) =>
      ExpressionReferenceInput(
        record: _text(r, '${prefix}_record'),
        universe: _text(r, '${prefix}_universe'),
      );
  SavedBoundaryForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_textProjection(_fields)} FROM boundary_form WHERE $_where',
          _binding(scope),
        );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedBoundaryForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedBoundaryForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        key: _text(r, 'boundary_key'),
        areaKind: _text(r, 'area_kind'),
        record: _ref(r, 'record'),
        predicate: _text(r, 'predicate_input'),
        subjectEnabled: r['subject_enabled'] == 1,
        subject: _ref(r, 'subject'),
        category: _text(r, 'category_input'),
        mode: _text(r, 'mode_input'),
        constraints: _ordered(
          'constraint',
          'expression_root',
          binding,
        ).map((c) => _expressions.read(c['expression_root'] as int)),
        scope: ScopeInput(
          applicability: _text(r, 'scope_applicability'),
          contextRecord: _text(r, 'scope_context_record'),
          contextUniverse: _text(r, 'scope_context_universe'),
          hasRealm: r['scope_has_realm'] == 1,
          realmRecord: _text(r, 'scope_realm_record'),
          realmUniverse: _text(r, 'scope_realm_universe'),
          worlds: _ordered(
            'world',
            'world_input',
            binding,
          ).map((w) => _text(w, 'world_input')).toList(),
        ),
        validity: _inputs.readTemporal(r['temporal'] as int, 0),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : BoundaryRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedBoundaryForm saved) {
    final binding = _binding(scope), f = saved.form, s = f.scope;
    final old = _db.select(
      'SELECT original,temporal FROM boundary_form WHERE $_where',
      binding,
    );
    final oldConstraints = _db.select(
      'SELECT expression_root FROM boundary_constraint WHERE $_where',
      binding,
    );
    final temporal = _inputs.writeTemporal(f.validity, 0),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO boundary_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.key,
        f.areaKind,
        f.record.record,
        f.record.universe,
        f.predicate,
        f.subjectEnabled ? 1 : 0,
        f.subject.record,
        f.subject.universe,
        f.category,
        f.mode,
        s.applicability,
        s.contextRecord,
        s.contextUniverse,
        s.hasRealm ? 1 : 0,
        s.realmRecord,
        s.realmUniverse,
        temporal,
        f.rationale,
        original,
        f.draftVersion?.toString(),
      ],
    );
    _db.execute('DELETE FROM boundary_world WHERE $_where', binding);
    for (var i = 0; i < s.worlds.length; i++) {
      _db.execute('INSERT INTO boundary_world VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        s.worlds[i],
      ]);
    }
    _db.execute('DELETE FROM boundary_constraint WHERE $_where', binding);
    for (var i = 0; i < f.constraints.length; i++) {
      final root = _expressions.write(f.constraints[i]);
      _db.execute('INSERT INTO boundary_constraint VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        root,
      ]);
    }
    for (final c in oldConstraints) {
      _expressions.delete(c['expression_root'] as int);
    }
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['temporal'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedBoundaryForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Boundary form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedBoundaryForm? load(EditorFormScope scope) {
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

  SavedBoundaryForm save(
    EditorFormScope scope,
    UnfinishedBoundaryForm form,
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
      final saved = SavedBoundaryForm(
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
