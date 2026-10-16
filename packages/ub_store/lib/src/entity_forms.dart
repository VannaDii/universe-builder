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

const _baseColumns =
    'instance,profile,universe,continuity,context,editor_key,generation,base_revision,client_ref,name,classification,world_role,rationale,draft_version';
const _inputColumns = '$_baseColumns,association_edits_present';
const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _columns =
    '$_inputColumns,expected_record_version,name_present,name_language,name_community,name_role,name_validity,name_temporal';
const _fields =
    'generation,base_revision,client_ref,name,classification,world_role,rationale,draft_version,association_edits_present,expected_record_version,name_present,name_language,name_community,name_role,name_validity,name_temporal';
const _associationColumns =
    '$_keys,ordinal,world,role,original_ordinal,validity_root,temporal_root,qualifiers_present';
final _domains = RecoveryDomainSchema(['Validity']);
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _schema =
    """
CREATE TABLE entity_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,name TEXT NOT NULL,classification TEXT NOT NULL,world_role TEXT NOT NULL,rationale TEXT NOT NULL,draft_version TEXT,
 association_edits_present INTEGER NOT NULL CHECK(association_edits_present IN (0,1)),expected_record_version TEXT,name_present INTEGER NOT NULL CHECK(name_present IN (0,1)),name_language TEXT,name_community TEXT,name_role TEXT,name_validity INTEGER REFERENCES "${BodyCatalog.instance.model('Validity').table}"(__row_id),name_temporal INTEGER REFERENCES entity_temporal(id),
 CHECK(name_present=1 OR (name_language IS NULL AND name_community IS NULL AND name_role IS NULL AND name_validity IS NULL AND name_temporal IS NULL)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE entity_form_world (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES entity_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE) STRICT;
CREATE TABLE entity_form_association (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world TEXT NOT NULL,role TEXT NOT NULL,original_ordinal INTEGER CHECK(original_ordinal>=0),validity_root INTEGER REFERENCES "${BodyCatalog.instance.model('Validity').table}"(__row_id),temporal_root INTEGER REFERENCES entity_temporal(id),qualifiers_present INTEGER NOT NULL CHECK(qualifiers_present IN (0,1)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES entity_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE) STRICT;
CREATE TABLE entity_form_qualifier (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,association_ordinal INTEGER NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_root INTEGER NOT NULL REFERENCES entity_qualifier(id),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,association_ordinal,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,association_ordinal) REFERENCES entity_form_association(instance,profile,universe,continuity,context,editor_key,ordinal)) STRICT;
${RecoveryValueInputs.schema('entity')}
${_domains.statements.join('\n')}
PRAGMA user_version=9;
""";
String _projection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'association_edits_present',
            'name_present',
            'name_validity',
            'name_temporal',
            'original_ordinal',
            'validity_root',
            'temporal_root',
            'qualifiers_present',
            'input_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private incomplete entity input, separate from canon and other editors.
final class EntityFormRecoveryStore {
  EntityFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'entity');

  static EntityFormRecoveryStore open(String path) {
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
      return EntityFormRecoveryStore._(db);
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
    final version =
        db.select('PRAGMA user_version').single.values.single as int;
    String columns(String table) =>
        db.select('PRAGMA table_info($table)').map((r) => r['name']).join(',');
    final expected = {
      'entity_form': _columns,
      'entity_form_world': '$_keys,ordinal,world',
      'entity_form_association': _associationColumns,
      'entity_form_qualifier': '$_keys,association_ordinal,ordinal,input_root',
      ...RecoveryValueInputs.columns('entity'),
    };
    final current =
        version == 9 &&
        tables.length == expected.length + _domains.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domains.matches(db);
    if (!current) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return version;
  }

  List<String> _binding(EditorFormScope scope) {
    final target = scope.entityNameRecord ?? scope.entityClassificationRecord;
    if (scope.representedContext == null ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.typeClientRef != null ||
        scope.entityClientRef == '' ||
        (scope.entityClientRef != null && target != null) ||
        (scope.entityNameRecord != null &&
            scope.entityClassificationRecord != null) ||
        (scope.entityOperationIndex != null &&
            (target == null || scope.entityOperationIndex! < 0))) {
      throw const FormatException('Choose the entity form context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
      target == null
          ? scope.entityClientRef ?? ''
          : '${scope.entityNameRecord == null ? 'classification' : 'name'}:${target.value}${scope.entityOperationIndex == null ? '' : ':edit:${scope.entityOperationIndex}'}',
    ];
  }

  List<Row> _ordered(
    String table,
    String columns,
    List<String> binding, {
    int? association,
  }) {
    final rows = _db.select(
      'SELECT ordinal,${_projection(columns)} FROM entity_form_$table WHERE $_where${association == null ? '' : ' AND association_ordinal=?'} ORDER BY ordinal',
      [...binding, ?association],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete entity input order');
      }
    }
    return rows;
  }

  Validity? _validity(Row r, String column) => r[column] == null
      ? null
      : Validity.fromWire(RelationalCodec(_db).get('Validity', r[column]));
  TemporalValidityInput? _temporal(Row r, String column) =>
      r[column] == null ? null : _inputs.readTemporal(r[column] as int, 0);
  SavedEntityForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_projection(_columns)} FROM entity_form WHERE $_where',
          _binding(scope),
        );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedEntityForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedEntityForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        name: _text(r, 'name'),
        classification: _text(r, 'classification'),
        worldRole: _text(r, 'world_role'),
        rationale: _text(r, 'rationale'),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        nameDetails: r['name_present'] == 0
            ? null
            : EntityNameForm(
                language: r['name_language'] == null
                    ? null
                    : _text(r, 'name_language'),
                community: r['name_community'] == null
                    ? null
                    : _text(r, 'name_community'),
                role: r['name_role'] == null ? null : _text(r, 'name_role'),
                validity: _validity(r, 'name_validity'),
                temporalValidity: _temporal(r, 'name_temporal'),
              ),
        worlds: _ordered(
          'world',
          'world',
          binding,
        ).map((w) => WorldId.parse(_text(w, 'world'))),
        associations: r['association_edits_present'] == 0
            ? null
            : _ordered(
                'association',
                'world,role,original_ordinal,validity_root,temporal_root,qualifiers_present',
                binding,
              ).map(
                (a) => EntityAssociationForm(
                  world: _text(a, 'world'),
                  role: _text(a, 'role'),
                  originalOrdinal: a['original_ordinal'] as int?,
                  validity: _validity(a, 'validity_root'),
                  temporalValidity: _temporal(a, 'temporal_root'),
                  qualifiers: a['qualifiers_present'] == 0
                      ? null
                      : _ordered(
                              'qualifier',
                              'input_root',
                              binding,
                              association: a['ordinal'] as int,
                            )
                            .map(
                              (q) => _inputs.readQualifier(
                                q['input_root'] as int,
                                0,
                              ),
                            )
                            .toList(),
                ),
              ),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedEntityForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        n = f.nameDetails,
        codec = RelationalCodec(_db);
    final old = _db.select(
          'SELECT name_validity,name_temporal FROM entity_form WHERE $_where',
          binding,
        ),
        oldAssociations = _db.select(
          'SELECT validity_root,temporal_root FROM entity_form_association WHERE $_where',
          binding,
        ),
        oldQualifiers = _db.select(
          'SELECT input_root FROM entity_form_qualifier WHERE $_where',
          binding,
        );
    final validity = n?.validity == null
            ? null
            : codec.put('Validity', n!.validity!.toWire()),
        temporal = n?.temporalValidity == null
            ? null
            : _inputs.writeTemporal(n!.temporalValidity!, 0),
        columns = _columns.split(',');
    _db.execute(
      'INSERT INTO entity_form VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.name,
        f.classification,
        f.worldRole,
        f.rationale,
        f.draftVersion?.toString(),
        f.associations == null ? 0 : 1,
        f.expectedRecordVersion?.value,
        n == null ? 0 : 1,
        n?.language,
        n?.community,
        n?.role,
        validity,
        temporal,
      ],
    );
    for (final table in ['qualifier', 'association', 'world']) {
      _db.execute('DELETE FROM entity_form_$table WHERE $_where', binding);
    }
    for (var i = 0; i < f.worlds.length; i++) {
      _db.execute('INSERT INTO entity_form_world VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.worlds[i].value,
      ]);
    }
    final associations = f.associations ?? <EntityAssociationForm>[];
    for (var i = 0; i < associations.length; i++) {
      final a = associations[i],
          validity = a.validity == null
              ? null
              : codec.put('Validity', a.validity!.toWire()),
          temporal = a.temporalValidity == null
              ? null
              : _inputs.writeTemporal(a.temporalValidity!, 0);
      _db.execute(
        'INSERT INTO entity_form_association VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...binding,
          i,
          a.world,
          a.role,
          a.originalOrdinal,
          validity,
          temporal,
          a.qualifiers == null ? 0 : 1,
        ],
      );
      final qualifiers = a.qualifiers ?? <QualifierInput>[];
      for (var j = 0; j < qualifiers.length; j++) {
        final root = _inputs.writeQualifier(qualifiers[j], 0);
        _db.execute(
          'INSERT INTO entity_form_qualifier VALUES(?,?,?,?,?,?,?,?,?)',
          [...binding, i, j, root],
        );
      }
    }
    for (final q in oldQualifiers) {
      _inputs.deleteQualifier(q['input_root'] as int);
    }
    for (final a in oldAssociations) {
      _domains.deleteOwned(_db, 'Validity', a['validity_root']);
      if (a['temporal_root'] case final int t) _inputs.deleteTemporal(t);
    }
    if (old.isNotEmpty) {
      _domains.deleteOwned(_db, 'Validity', old.single['name_validity']);
      if (old.single['name_temporal'] case final int t) {
        _inputs.deleteTemporal(t);
      }
    }
  }

  SavedEntityForm? load(EditorFormScope scope) {
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

  void _validate(EditorFormScope scope, UnfinishedEntityForm form) {
    if (scope.representedContext != form.representedContext ||
        (scope.entityClientRef != null &&
            scope.entityClientRef != form.clientRef) ||
        ((scope.entityNameRecord ?? scope.entityClassificationRecord) != null &&
            (scope.entityNameRecord ?? scope.entityClassificationRecord)!
                    .value !=
                form.clientRef)) {
      throw const FormatException('Entity form context does not match.');
    }
    for (final text in [
      if (form.nameDetails != null) ...form.nameDetails!.exactTexts,
      form.clientRef,
      form.name,
      form.classification,
      form.worldRole,
      form.rationale,
      for (final a in form.associations ?? <EntityAssociationForm>[]) ...[
        a.world,
        a.role,
        for (final q in a.qualifiers ?? <QualifierInput>[]) ...q.exactTexts,
        if (a.temporalValidity != null) ...[
          a.temporalValidity!.kind,
          a.temporalValidity!.calendar,
          a.temporalValidity!.relation,
          a.temporalValidity!.targetUniverse,
          a.temporalValidity!.targetRecord,
          for (final b in [
            a.temporalValidity!.start,
            a.temporalValidity!.end,
          ]) ...[
            if (b.amount != null) ...b.amount!.exactTexts,
            b.kind,
            b.value,
            b.upper,
            b.uncertaintyKind,
            b.uncertainty,
            b.denominator,
            b.unit,
          ],
        ],
      ],
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedEntityForm save(
    EditorFormScope scope,
    UnfinishedEntityForm form,
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
      final saved = SavedEntityForm(
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
