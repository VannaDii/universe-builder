import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,namespace,relation_key,target_record,target_universe,expected_record_version,rationale,draft_version,has_original,original_namespace,original_key';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE relation_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 namespace TEXT NOT NULL, relation_key TEXT NOT NULL, target_record TEXT, target_universe TEXT, expected_record_version TEXT, rationale TEXT NOT NULL, draft_version TEXT,
 has_original INTEGER NOT NULL CHECK(has_original IN (0,1)), original_namespace TEXT, original_key TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 CHECK((has_original=0 AND original_namespace IS NULL AND original_key IS NULL) OR (has_original=1 AND original_namespace IS NOT NULL AND original_key IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE relation_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES relation_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE UNIQUE INDEX relation_original_language ON relation_label(instance,profile,universe,continuity,context,editor_key,language) WHERE list_kind='original';
CREATE TABLE relation_role (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), role_name TEXT NOT NULL, multiplicity_text TEXT NOT NULL, is_ordered INTEGER NOT NULL CHECK(is_ordered IN (0,1)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES relation_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE relation_participant (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), role_ordinal INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), participant_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,role_ordinal,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,list_kind,role_ordinal) REFERENCES relation_role(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) => {'ordinal', 'has_original', 'is_ordered'}.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named relation fields, separate from canon.
final class RelationFormRecoveryStore {
  RelationFormRecoveryStore._(this._db);
  final Database _db;

  static RelationFormRecoveryStore open(String path) {
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
            'ALTER TABLE relation_form RENAME TO legacy_relation_form',
          );
          db.execute(_schema);
          final store = RelationFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_relation_form',
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
            final form = UnfinishedRelationForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedRelationForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_relation_form');
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
      return RelationFormRecoveryStore._(db);
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
        columns('relation_form') == _legacyColumns;
    final current =
        version == 2 &&
        tables.length == 4 &&
        columns('relation_form') == '$_keys,$_fields' &&
        columns('relation_label') ==
            '$_keys,list_kind,ordinal,language,label_text' &&
        columns('relation_role') ==
            '$_keys,list_kind,ordinal,role_name,multiplicity_text,is_ordered' &&
        columns('relation_participant') ==
            '$_keys,list_kind,role_ordinal,ordinal,participant_input';
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
      throw const FormatException('Choose the relation context.');
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
    int? role,
  }) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM relation_$table WHERE $_where AND list_kind=?${role == null ? '' : ' AND role_ordinal=?'} ORDER BY ordinal',
      [...binding, kind, ?role],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete relation input order.');
      }
    }
    return rows;
  }

  SavedRelationForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_textProjection('$_keys,$_fields')} FROM relation_form WHERE $_where',
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
    List<RelationRoleInput> roles(String kind) =>
        _rows('role', 'role_name,multiplicity_text,is_ordered', binding, kind)
            .map(
              (r) => RelationRoleInput(
                name: _text(r, 'role_name'),
                multiplicity: _text(r, 'multiplicity_text'),
                ordered: r['is_ordered'] == 1,
                participantTypes: _rows(
                  'participant',
                  'participant_input',
                  binding,
                  kind,
                  role: r['ordinal'] as int,
                ).map((p) => _text(p, 'participant_input')),
              ),
            )
            .toList();
    return SavedRelationForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedRelationForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        namespace: _text(row, 'namespace'),
        key: _text(row, 'relation_key'),
        labels: labels('input'),
        roles: roles('input'),
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
            : RelationRecord(
                namespace: _text(row, 'original_namespace'),
                key: _text(row, 'original_key'),
                labels: {
                  for (final l in labels('original')) l.language: l.text,
                },
                roles: roles('original').map(
                  (r) => RoleDefinition(
                    name: r.name,
                    participantTypes: r.participantTypes.map(RecordId.parse),
                    multiplicity: Multiplicity.fromName(r.multiplicity),
                    ordered: r.ordered,
                  ),
                ),
              ),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedRelationForm saved) {
    final binding = _binding(scope),
        form = saved.form,
        original = form.original;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO relation_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
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
    for (final table in ['participant', 'role', 'label']) {
      _db.execute('DELETE FROM relation_$table WHERE $_where', binding);
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
        _db.execute('INSERT INTO relation_label VALUES(?,?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          label.language,
          label.text,
        ]);
      }
    }
    final originalRoles =
        original?.roles
            .map(
              (r) => RelationRoleInput(
                name: r.name,
                participantTypes: r.participantTypes.map((id) => id.value),
                multiplicity: r.multiplicity.name,
                ordered: r.ordered,
              ),
            )
            .toList() ??
        <RelationRoleInput>[];
    for (final list in {
      'input': form.roles,
      'original': originalRoles,
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final role = list.value[i];
        _db.execute('INSERT INTO relation_role VALUES(?,?,?,?,?,?,?,?,?,?,?)', [
          ...binding,
          list.key,
          i,
          role.name,
          role.multiplicity,
          role.ordered ? 1 : 0,
        ]);
        for (var j = 0; j < role.participantTypes.length; j++) {
          _db.execute(
            'INSERT INTO relation_participant VALUES(?,?,?,?,?,?,?,?,?,?)',
            [...binding, list.key, i, j, role.participantTypes[j]],
          );
        }
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedRelationForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Relation form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedRelationForm? load(EditorFormScope scope) {
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

  SavedRelationForm save(
    EditorFormScope scope,
    UnfinishedRelationForm form,
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
      final saved = SavedRelationForm(
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
