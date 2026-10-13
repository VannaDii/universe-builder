import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _legacyColumns =
    'instance,profile,universe,continuity,context,generation,base_revision,client_ref,name,classification,world_role,rationale';
const _columns =
    'instance,profile,universe,continuity,context,editor_key,generation,base_revision,client_ref,name,classification,world_role,rationale,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = '''
CREATE TABLE entity_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, generation TEXT NOT NULL,
 base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, name TEXT NOT NULL,
 classification TEXT NOT NULL, world_role TEXT NOT NULL, rationale TEXT NOT NULL, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE entity_form_world (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES entity_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE
) STRICT;
PRAGMA user_version=2;
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
            "INSERT INTO entity_form SELECT instance,profile,universe,continuity,context,'',generation,base_revision,client_ref,name,classification,world_role,rationale,NULL FROM legacy_entity_form",
          );
          db.execute(
            "INSERT INTO entity_form_world SELECT instance,profile,universe,continuity,context,'',ordinal,world FROM legacy_entity_form_world",
          );
          db.execute(
            'DROP TABLE legacy_entity_form_world; DROP TABLE legacy_entity_form',
          );
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
    final version = db.select('PRAGMA user_version').single.values.single;
    if (tables.length != 2 ||
        (version != 1 && version != 2) ||
        db
                .select('PRAGMA table_info(entity_form)')
                .map((row) => row['name'])
                .join(',') !=
            (version == 1 ? _legacyColumns : _columns) ||
        db
                .select('PRAGMA table_info(entity_form_world)')
                .map((row) => row['name'])
                .join(',') !=
            (version == 1
                ? 'instance,profile,universe,continuity,context,ordinal,world'
                : 'instance,profile,universe,continuity,context,editor_key,ordinal,world')) {
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
        scope.typeClientRef != null ||
        scope.entityClientRef == '') {
      throw const FormatException('Choose the entity form context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
      scope.entityClientRef ?? '',
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
        name: row['name'] as String,
        classification: row['classification'] as String,
        worldRole: row['world_role'] as String,
        rationale: row['rationale'] as String,
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
            scope.entityClientRef != form.clientRef)) {
      throw const FormatException('Entity form context does not match.');
    }
    for (final text in [
      form.clientRef,
      form.name,
      form.classification,
      form.worldRole,
      form.rationale,
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
        'INSERT INTO entity_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(instance,profile,universe,continuity,context,editor_key) DO UPDATE SET generation=excluded.generation,base_revision=excluded.base_revision,client_ref=excluded.client_ref,name=excluded.name,classification=excluded.classification,world_role=excluded.world_role,rationale=excluded.rationale,draft_version=excluded.draft_version',
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
