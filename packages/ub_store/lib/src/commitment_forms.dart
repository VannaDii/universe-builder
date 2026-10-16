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
    'generation,base_revision,client_ref,obligated_record,obligated_universe,deadline_enabled,deadline_root,status_input,rationale,original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('commitment');
final _domainStorage = RecoveryDomainSchema([
  _originalModel,
  'Expr',
  'Operand',
]);
final _schema =
    """
CREATE TABLE commitment_form (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,obligated_record TEXT NOT NULL,obligated_universe TEXT NOT NULL,deadline_enabled INTEGER NOT NULL CHECK(deadline_enabled IN (0,1)),deadline_root INTEGER NOT NULL REFERENCES commitment_temporal(id),status_input TEXT NOT NULL,rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),draft_version TEXT,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE commitment_party (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),record_input TEXT NOT NULL,universe_input TEXT NOT NULL,role_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES commitment_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE commitment_condition (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),expression_root INTEGER NOT NULL REFERENCES commitment_expression(id),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES commitment_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('commitment')}
${RecoveryExpressionInputs.schema('commitment')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'deadline_enabled',
            'deadline_root',
            'expression_root',
            'ordinal',
            'original',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named commitment fields, separate from canon.
final class CommitmentFormRecoveryStore {
  CommitmentFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'commitment');
  late final _expressions = RecoveryExpressionInputs(
    _db,
    'commitment',
    _domainStorage,
  );

  static CommitmentFormRecoveryStore open(String path) {
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
      return CommitmentFormRecoveryStore._(db);
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
      'commitment_form': '$_keys,$_fields',
      'commitment_party':
          '$_keys,ordinal,record_input,universe_input,role_input',
      'commitment_condition': '$_keys,ordinal,expression_root',
      ...RecoveryExpressionInputs.columns('commitment'),
      ...RecoveryValueInputs.columns('commitment'),
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
      throw const FormatException('Choose the commitment context.');
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

  ExpressionReferenceInput _ref(Row r, String prefix) =>
      ExpressionReferenceInput(
        record: _text(r, '${prefix}_record'),
        universe: _text(r, '${prefix}_universe'),
      );
  List<Row> _ordered(String table, String columns, List<String> binding) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM commitment_$table WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete commitment input order');
      }
    }
    return rows;
  }

  SavedCommitmentForm? _read(EditorFormScope scope) {
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM commitment_form WHERE $_where',
      _binding(scope),
    );
    if (rows.isEmpty) return null;
    final r = rows.single, binding = _binding(scope);
    return SavedCommitmentForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedCommitmentForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        obligated: _ref(r, 'obligated'),
        deadlineEnabled: r['deadline_enabled'] == 1,
        deadline: _inputs.readTemporal(r['deadline_root'] as int, 0),
        status: _text(r, 'status_input'),
        parties:
            _ordered(
              'party',
              'record_input,universe_input,role_input',
              binding,
            ).map(
              (p) => CommitmentPartyInput(
                record: _text(p, 'record_input'),
                universe: _text(p, 'universe_input'),
                role: _text(p, 'role_input'),
              ),
            ),
        conditions: _ordered(
          'condition',
          'expression_root',
          binding,
        ).map((c) => _expressions.read(c['expression_root'] as int)),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : CommitmentRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedCommitmentForm saved) {
    final binding = _binding(scope), f = saved.form;
    final old = _db.select(
      'SELECT original,deadline_root FROM commitment_form WHERE $_where',
      binding,
    );
    final oldConditions = _db.select(
      'SELECT expression_root FROM commitment_condition WHERE $_where',
      binding,
    );
    final deadlineRoot = _inputs.writeTemporal(f.deadline, 0),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO commitment_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.obligated.record,
        f.obligated.universe,
        f.deadlineEnabled ? 1 : 0,
        deadlineRoot,
        f.status,
        f.rationale,
        original,
        f.draftVersion?.toString(),
      ],
    );
    _db.execute('DELETE FROM commitment_condition WHERE $_where', binding);
    _db.execute('DELETE FROM commitment_party WHERE $_where', binding);
    for (var i = 0; i < f.parties.length; i++) {
      final p = f.parties[i];
      _db.execute('INSERT INTO commitment_party VALUES(?,?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        p.record,
        p.universe,
        p.role,
      ]);
    }
    for (var i = 0; i < f.conditions.length; i++) {
      final root = _expressions.write(f.conditions[i]);
      _db.execute('INSERT INTO commitment_condition VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        root,
      ]);
    }
    for (final c in oldConditions) {
      _expressions.delete(c['expression_root'] as int);
    }
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['deadline_root'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedCommitmentForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Commitment form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedCommitmentForm? load(EditorFormScope scope) {
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

  SavedCommitmentForm save(
    EditorFormScope scope,
    UnfinishedCommitmentForm form,
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
      final saved = SavedCommitmentForm(
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
