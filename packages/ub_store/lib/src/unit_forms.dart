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
    'generation,base_revision,client_ref,namespace,unit_key,dimension,symbol,has_base,base_input,has_scale,scale_input,validity_choice,temporal_input,target_record,target_universe,expected_record_version,rationale,draft_version,original';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _catalog = BodyCatalog.instance;
final _originalModel = recoveryPayloadModel('unit');
// Reuse the existing closed UnitRecord/Value/Validity tables and codec. Only
// tables reachable from UnitRecord are installed in this private recovery file.
final _originalStorage = RecoveryDomainSchema([_originalModel]);
final _originalSchema = _originalStorage.statements;
final _schema =
    """
CREATE TABLE unit_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, namespace TEXT NOT NULL, unit_key TEXT NOT NULL, dimension TEXT NOT NULL, symbol TEXT NOT NULL,
 has_base INTEGER NOT NULL CHECK(has_base IN (0,1)), base_input TEXT NOT NULL, has_scale INTEGER NOT NULL CHECK(has_scale IN (0,1)), scale_input INTEGER NOT NULL REFERENCES unit_qualifier(id), validity_choice TEXT NOT NULL, temporal_input INTEGER REFERENCES unit_temporal(id),
 target_record TEXT, target_universe TEXT, expected_record_version TEXT, rationale TEXT NOT NULL, draft_version TEXT, original INTEGER REFERENCES "${_catalog.model(_originalModel).table}"(__row_id),
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE unit_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES unit_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
${RecoveryValueInputs.schema('unit')}
${_originalSchema.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'id',
            'owner',
            'child',
            'has_base',
            'has_scale',
            'scale_input',
            'temporal_input',
            'original',
            'lower_input',
            'upper_input',
            'temporal',
            'start_input',
            'end_input',
            'amount',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named unit fields, separate from canon.
final class UnitFormRecoveryStore {
  UnitFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'unit');

  static UnitFormRecoveryStore open(String path) {
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
          db.execute('ALTER TABLE unit_form RENAME TO legacy_unit_form');
          db.execute(_schema);
          final store = UnitFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_unit_form',
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
            final form = UnfinishedUnitForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedUnitForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_unit_form');
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
      return UnitFormRecoveryStore._(db);
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
        columns('unit_form') == _legacyColumns;
    final expected = {
      'unit_form': '$_keys,$_fields',
      'unit_label': '$_keys,ordinal,language,label_text',
      ...RecoveryValueInputs.columns('unit'),
    };
    final current =
        version == 2 &&
        tables.length == expected.length + _originalSchema.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _originalStorage.matches(db);
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
      throw const FormatException('Choose the unit definition context.');
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

  SavedUnitForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM unit_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final labels = _db.select(
      'SELECT ordinal,${_textProjection('language,label_text')} FROM unit_label WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < labels.length; i++) {
      if (labels[i]['ordinal'] != i) {
        throw const FormatException('Incomplete unit label order');
      }
    }
    return SavedUnitForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedUnitForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        namespace: _text(r, 'namespace'),
        key: _text(r, 'unit_key'),
        dimension: _text(r, 'dimension'),
        symbol: _text(r, 'symbol'),
        hasBase: r['has_base'] == 1,
        base: _text(r, 'base_input'),
        hasScale: r['has_scale'] == 1,
        scale: _inputs.readQualifier(r['scale_input'] as int, 0),
        validityChoice: _text(r, 'validity_choice'),
        temporalValidity: r['temporal_input'] == null
            ? null
            : _inputs.readTemporal(r['temporal_input'] as int, 0),
        labels: labels.map(
          (l) => PropertyLabelInput(
            language: _text(l, 'language'),
            text: _text(l, 'label_text'),
          ),
        ),
        rationale: _text(r, 'rationale'),
        revisionTarget: r['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(r, 'target_record'),
                universe: _text(r, 'target_universe'),
              ),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
        original: r['original'] == null
            ? null
            : UnitRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedUnitForm saved) {
    final binding = _binding(scope), f = saved.form;
    final old = _db.select(
      'SELECT scale_input,temporal_input,original FROM unit_form WHERE $_where',
      binding,
    );
    final scale = _inputs.writeQualifier(f.scale, 0),
        temporal = f.temporalValidity == null
            ? null
            : _inputs.writeTemporal(f.temporalValidity!, 0);
    final original = f.original == null
        ? null
        : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO unit_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.namespace,
        f.key,
        f.dimension,
        f.symbol,
        f.hasBase ? 1 : 0,
        f.base,
        f.hasScale ? 1 : 0,
        scale,
        f.validityChoice,
        temporal,
        f.revisionTarget?.record,
        f.revisionTarget?.universe,
        f.expectedRecordVersion?.value,
        f.rationale,
        f.draftVersion?.toString(),
        original,
      ],
    );
    _db.execute('DELETE FROM unit_label WHERE $_where', binding);
    for (var i = 0; i < f.labels.length; i++) {
      _db.execute('INSERT INTO unit_label VALUES(?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.labels[i].language,
        f.labels[i].text,
      ]);
    }
    if (old.isNotEmpty) {
      _inputs.deleteQualifier(old.single['scale_input'] as int);
      if (old.single['temporal_input'] case final int t) {
        _inputs.deleteTemporal(t);
      }
      _originalStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedUnitForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Unit form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedUnitForm? load(EditorFormScope scope) {
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

  SavedUnitForm save(
    EditorFormScope scope,
    UnfinishedUnitForm form,
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
      final saved = SavedUnitForm(
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
