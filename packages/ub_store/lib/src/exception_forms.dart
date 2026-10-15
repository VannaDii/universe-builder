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
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,rule_record,rule_universe,rule_version_enabled,rule_version_input,fictional_departure,decision_record,decision_universe,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,temporal,rationale,original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('exception');
final _domainStorage = RecoveryDomainSchema([_originalModel]);
final _schema =
    """
CREATE TABLE exception_form (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,rule_record TEXT NOT NULL,rule_universe TEXT NOT NULL,rule_version_enabled INTEGER NOT NULL CHECK(rule_version_enabled IN (0,1)),rule_version_input TEXT NOT NULL,fictional_departure INTEGER NOT NULL CHECK(fictional_departure IN (0,1)),decision_record TEXT NOT NULL,decision_universe TEXT NOT NULL,
 scope_applicability TEXT NOT NULL,scope_context_record TEXT NOT NULL,scope_context_universe TEXT NOT NULL,scope_has_realm INTEGER NOT NULL CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT NOT NULL,scope_realm_universe TEXT NOT NULL,temporal INTEGER NOT NULL REFERENCES exception_temporal(id),rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE exception_world (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES exception_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('exception')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'expression_root',
            'fictional_departure',
            'ordinal',
            'original',
            'rule_version_enabled',
            'scope_has_realm',
            'temporal',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named exception fields, separate from canon.
final class ExceptionFormRecoveryStore {
  ExceptionFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'exception');

  static ExceptionFormRecoveryStore open(String path) {
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
          db.execute(
            'ALTER TABLE exception_form RENAME TO legacy_exception_form',
          );
          db.execute(_schema);
          final store = ExceptionFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_exception_form',
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
            final form = UnfinishedExceptionForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedExceptionForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_exception_form');
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
      return ExceptionFormRecoveryStore._(db);
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
        columns('exception_form') == _legacyColumns;
    final expected = {
      'exception_form': '$_keys,$_fields',
      'exception_world': '$_keys,ordinal,world_input',
      ...RecoveryValueInputs.columns('exception'),
    };
    final current =
        version == 2 &&
        tables.length == expected.length + _domainStorage.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domainStorage.matches(db);
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
      throw const FormatException('Choose the exception context.');
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
      'SELECT ordinal,${_textProjection(columns)} FROM exception_$table WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete exception input order');
      }
    }
    return rows;
  }

  ExpressionReferenceInput _ref(Row r, String prefix) =>
      ExpressionReferenceInput(
        record: _text(r, '${prefix}_record'),
        universe: _text(r, '${prefix}_universe'),
      );
  SavedExceptionForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_textProjection(_fields)} FROM exception_form WHERE $_where',
          _binding(scope),
        );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedExceptionForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedExceptionForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        rule: _ref(r, 'rule'),
        ruleVersionEnabled: r['rule_version_enabled'] == 1,
        ruleVersion: _text(r, 'rule_version_input'),
        fictionalDeparture: r['fictional_departure'] == 1,
        decision: _ref(r, 'decision'),
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
            : ExceptionRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedExceptionForm saved) {
    final binding = _binding(scope), f = saved.form, s = f.scope;
    final old = _db.select(
      'SELECT original,temporal FROM exception_form WHERE $_where',
      binding,
    );
    final temporal = _inputs.writeTemporal(f.validity, 0),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO exception_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.rule.record,
        f.rule.universe,
        f.ruleVersionEnabled ? 1 : 0,
        f.ruleVersion,
        f.fictionalDeparture ? 1 : 0,
        f.decision.record,
        f.decision.universe,
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
    _db.execute('DELETE FROM exception_world WHERE $_where', binding);
    for (var i = 0; i < s.worlds.length; i++) {
      _db.execute('INSERT INTO exception_world VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        s.worlds[i],
      ]);
    }
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['temporal'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedExceptionForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Exception form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedExceptionForm? load(EditorFormScope scope) {
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

  SavedExceptionForm save(
    EditorFormScope scope,
    UnfinishedExceptionForm form,
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
      final saved = SavedExceptionForm(
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
