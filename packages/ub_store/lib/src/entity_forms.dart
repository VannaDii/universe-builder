import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _legacyColumns =
    'instance,profile,universe,continuity,context,generation,base_revision,client_ref,name,classification,world_role,rationale';
const _v2Columns =
    'instance,profile,universe,continuity,context,editor_key,generation,base_revision,client_ref,name,classification,world_role,rationale,draft_version';
const _v6Columns = '$_v2Columns,association_edits_present';
const _v7Columns = '$_v6Columns,name_input';
const _columns = '$_v7Columns,expected_record_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema =
    '''
CREATE TABLE entity_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, generation TEXT NOT NULL,
 base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, name TEXT NOT NULL,
 classification TEXT NOT NULL, world_role TEXT NOT NULL, rationale TEXT NOT NULL, draft_version TEXT,
 association_edits_present INTEGER NOT NULL DEFAULT 0 CHECK(association_edits_present IN (0,1)),
 name_input TEXT, expected_record_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE entity_form_world (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES entity_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE
) STRICT;
$_associationSchema
PRAGMA user_version=8;
''';

const _associationSchema = '''
CREATE TABLE entity_form_association (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL, role TEXT NOT NULL,
 original_ordinal INTEGER CHECK(original_ordinal>=0), validity TEXT, temporal_input TEXT, qualifier_input TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES entity_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE
) STRICT;
''';

/// Device-private incomplete entity input, separate from canon and other editors.
final class EntityFormRecoveryStore {
  EntityFormRecoveryStore._(this._db);
  final Database _db;

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
        } else if (version == 1) {
          db.execute(
            'ALTER TABLE entity_form_world RENAME TO legacy_entity_form_world',
          );
          db.execute('ALTER TABLE entity_form RENAME TO legacy_entity_form');
          db.execute(_schema);
          db.execute(
            "INSERT INTO entity_form SELECT instance,profile,universe,continuity,context,'',generation,base_revision,client_ref,name,classification,world_role,rationale,NULL,0,NULL,NULL FROM legacy_entity_form",
          );
          db.execute(
            "INSERT INTO entity_form_world SELECT instance,profile,universe,continuity,context,'',ordinal,world FROM legacy_entity_form_world",
          );
          db.execute(
            'DROP TABLE legacy_entity_form_world; DROP TABLE legacy_entity_form',
          );
        }
        if (version == 2) {
          db.execute(
            'ALTER TABLE entity_form ADD COLUMN association_edits_present INTEGER NOT NULL DEFAULT 0 CHECK(association_edits_present IN (0,1))',
          );
          db.execute(_associationSchema);
          db.execute('PRAGMA user_version=6');
        }
        if (version == 3) {
          db.execute(
            'ALTER TABLE entity_form_association ADD COLUMN validity TEXT',
          );
          db.execute('PRAGMA user_version=6');
        }
        if (version == 3 || version == 4) {
          db.execute(
            'ALTER TABLE entity_form_association ADD COLUMN temporal_input TEXT',
          );
          db.execute('PRAGMA user_version=6');
        }
        if (version >= 3 && version <= 5) {
          db.execute(
            'ALTER TABLE entity_form_association ADD COLUMN qualifier_input TEXT',
          );
          db.execute('PRAGMA user_version=6');
        }
        if (version >= 2 && version <= 6) {
          db.execute('ALTER TABLE entity_form ADD COLUMN name_input TEXT');
          db.execute('PRAGMA user_version=7');
        }
        if (version >= 2 && version <= 7) {
          db.execute(
            'ALTER TABLE entity_form ADD COLUMN expected_record_version TEXT',
          );
          db.execute('PRAGMA user_version=8');
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
    if (tables.length != ((version >= 3 && version <= 8) ? 3 : 2) ||
        (version != 1 &&
            version != 2 &&
            version != 3 &&
            version != 4 &&
            version != 5 &&
            version != 6 &&
            version != 7 &&
            version != 8) ||
        db
                .select('PRAGMA table_info(entity_form)')
                .map((row) => row['name'])
                .join(',') !=
            (version == 1
                ? _legacyColumns
                : version == 2
                ? _v2Columns
                : version <= 6
                ? _v6Columns
                : version == 7
                ? _v7Columns
                : _columns) ||
        db
                .select('PRAGMA table_info(entity_form_world)')
                .map((row) => row['name'])
                .join(',') !=
            (version == 1
                ? 'instance,profile,universe,continuity,context,ordinal,world'
                : 'instance,profile,universe,continuity,context,editor_key,ordinal,world') ||
        ((version >= 3 && version <= 8) &&
            db
                    .select('PRAGMA table_info(entity_form_association)')
                    .map((r) => r['name'])
                    .join(',') !=
                (version == 3
                    ? 'instance,profile,universe,continuity,context,editor_key,ordinal,world,role,original_ordinal'
                    : version == 4
                    ? 'instance,profile,universe,continuity,context,editor_key,ordinal,world,role,original_ordinal,validity'
                    : version == 5
                    ? 'instance,profile,universe,continuity,context,editor_key,ordinal,world,role,original_ordinal,validity,temporal_input'
                    : 'instance,profile,universe,continuity,context,editor_key,ordinal,world,role,original_ordinal,validity,temporal_input,qualifier_input'))) {
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

  SavedEntityForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select('SELECT * FROM entity_form WHERE $_where', binding);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedEntityForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedEntityForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: RecordId.parse(row['context'] as String),
        clientRef: row['client_ref'] as String,
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(row['draft_version'] as String),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(row['expected_record_version'] as String),
        nameDetails: row['name_input'] == null
            ? null
            : EntityNameForm.fromWire(
                CanonicalValue.parseWireJson(row['name_input'] as String),
              ),
        name: row['name'] as String,
        classification: row['classification'] as String,
        worldRole: row['world_role'] as String,
        rationale: row['rationale'] as String,
        associations: row['association_edits_present'] == 0
            ? null
            : _db
                  .select(
                    'SELECT * FROM entity_form_association WHERE $_where ORDER BY ordinal',
                    binding,
                  )
                  .map(
                    (r) => EntityAssociationForm(
                      world: r['world'] as String,
                      role: r['role'] as String,
                      originalOrdinal: r['original_ordinal'] as int?,
                      qualifiers: r['qualifier_input'] == null
                          ? null
                          : (CanonicalValue.parseWireJson(
                                  r['qualifier_input'] as String,
                                ) as CanonicalArray).items
                                .map(QualifierInput.fromWire)
                                .toList(),
                      temporalValidity: r['temporal_input'] == null
                          ? null
                          : TemporalValidityInput.fromWire(
                              CanonicalValue.parseWireJson(
                                r['temporal_input'] as String,
                              ),
                            ),
                      validity: r['validity'] == null
                          ? null
                          : Validity.fromWire(
                              CanonicalValue.parseWireJson(
                                r['validity'] as String,
                              ),
                            ),
                    ),
                  ),
        worlds: _db
            .select(
              'SELECT world FROM entity_form_world WHERE $_where ORDER BY ordinal',
              binding,
            )
            .map((row) => WorldId.parse(row['world'] as String)),
      ),
    );
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

  SavedEntityForm save(
    EditorFormScope scope,
    UnfinishedEntityForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
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
      _db.execute(
        'INSERT INTO entity_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(instance,profile,universe,continuity,context,editor_key) DO UPDATE SET generation=excluded.generation,base_revision=excluded.base_revision,client_ref=excluded.client_ref,name=excluded.name,classification=excluded.classification,world_role=excluded.world_role,rationale=excluded.rationale,draft_version=excluded.draft_version,association_edits_present=excluded.association_edits_present,name_input=excluded.name_input,expected_record_version=excluded.expected_record_version',
        [
          ...binding,
          saved.generation.toString(),
          form.baseRevision.value,
          form.clientRef,
          form.name,
          form.classification,
          form.worldRole,
          form.rationale,
          form.draftVersion?.toString(),
          form.associations == null ? 0 : 1,
          form.nameDetails?.toWire().toText(),
          form.expectedRecordVersion?.value,
        ],
      );
      _db.execute('DELETE FROM entity_form_world WHERE $_where', binding);
      for (var i = 0; i < form.worlds.length; i++) {
        _db.execute('INSERT INTO entity_form_world VALUES(?,?,?,?,?,?,?,?)', [
          ...binding,
          i,
          form.worlds[i].value,
        ]);
      }
      _db.execute('DELETE FROM entity_form_association WHERE $_where', binding);
      final associations = form.associations ?? <EntityAssociationForm>[];
      for (var i = 0; i < associations.length; i++) {
        final a = associations[i];
        _db.execute(
          'INSERT INTO entity_form_association VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            ...binding,
            i,
            a.world,
            a.role,
            a.originalOrdinal,
            a.validity?.toWire().toText(),
            a.temporalValidity?.toWire().toText(),
            a.qualifiers == null
                ? null
                : CanonicalArray(a.qualifiers!.map((q) => q.toWire())).toText(),
          ],
        );
      }
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
