import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _schema = '''
CREATE TABLE world_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, editor_key TEXT NOT NULL, generation TEXT NOT NULL,
 base_revision TEXT NOT NULL, represented_context TEXT NOT NULL,
 record_id TEXT NOT NULL, selector TEXT NOT NULL, setting_type TEXT NOT NULL,
 rationale TEXT NOT NULL, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,editor_key)
) STRICT;
CREATE TABLE world_form_alias (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, editor_key TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), value TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,editor_key) REFERENCES world_form(instance,profile,universe,continuity,editor_key) ON DELETE CASCADE
) STRICT;
CREATE TABLE world_form_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, editor_key TEXT NOT NULL, language TEXT NOT NULL, value TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,editor_key,language),
 FOREIGN KEY(instance,profile,universe,continuity,editor_key) REFERENCES world_form(instance,profile,universe,continuity,editor_key) ON DELETE CASCADE
) STRICT;
PRAGMA user_version=2;
''';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND editor_key=?';

/// Short, compared transactions permit competing windows without silently
/// overwriting each other's unfinished fields. No canon database is opened.
final class WorldFormRecoveryStore {
  WorldFormRecoveryStore._(this._db);
  final Database _db;
  static WorldFormRecoveryStore open(String path) {
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
        'PRAGMA busy_timeout=2000; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL',
      );
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('BEGIN IMMEDIATE');
      try {
        final populated = _checkSchema(db);
        if (populated == 0) {
          db.execute(_schema);
        } else if (db.select('PRAGMA user_version').single.values.single == 1) {
          // Preserve existing device work while adding separate operation edits.
          for (final table in [
            'world_form_alias',
            'world_form_label',
            'world_form',
          ]) {
            db.execute('ALTER TABLE $table RENAME TO legacy_$table');
          }
          db.execute(_schema);
          db.execute(
            "INSERT INTO world_form SELECT instance,profile,universe,continuity,'',generation,base_revision,represented_context,record_id,selector,setting_type,rationale,NULL FROM legacy_world_form",
          );
          db.execute(
            "INSERT INTO world_form_alias SELECT instance,profile,universe,continuity,'',ordinal,value FROM legacy_world_form_alias",
          );
          db.execute(
            "INSERT INTO world_form_label SELECT instance,profile,universe,continuity,'',language,value FROM legacy_world_form_label",
          );
          for (final table in [
            'world_form_alias',
            'world_form_label',
            'world_form',
          ]) {
            db.execute('DROP TABLE legacy_$table');
          }
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
      return WorldFormRecoveryStore._(db);
    } on EditorRecoveryException {
      db?.close();
      rethrow;
    } on Object {
      db?.close();
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  static int _checkSchema(Database db) {
    final count =
        db
                .select(
                  "SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
                )
                .single['n']
            as int;
    if (count == 0) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    const legacyColumns = {
      'world_form': 'instance,profile,universe,continuity,generation,base_revision,represented_context,record_id,selector,setting_type,rationale',
      'world_form_alias': 'instance,profile,universe,continuity,ordinal,value',
      'world_form_label': 'instance,profile,universe,continuity,language,value',
    };
    const currentColumns = {
      'world_form': 'instance,profile,universe,continuity,editor_key,generation,base_revision,represented_context,record_id,selector,setting_type,rationale,draft_version',
      'world_form_alias':
          'instance,profile,universe,continuity,editor_key,ordinal,value',
      'world_form_label':
          'instance,profile,universe,continuity,editor_key,language,value',
    };
    final columns = version == 1 ? legacyColumns : currentColumns;
    if (count != columns.length ||
        (version != 1 && version != 2) ||
        columns.entries.any(
          (entry) =>
              db
                  .select('PRAGMA table_info(${entry.key})')
                  .map((row) => row['name'])
                  .join(',') !=
              entry.value,
        )) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return count;
  }

  List<String> _binding(EditorFormScope scope) => [
    scope.instance.value,
    scope.profile.value,
    scope.universe.value,
    scope.continuity.value,
    scope.worldClientRef == null ? '' : 'edit:${scope.worldClientRef}',
  ];

  SavedWorldForm? _read(EditorFormScope scope) {
    final values = _binding(scope);
    final rows = _db.select('SELECT * FROM world_form WHERE $_where', values);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedWorldForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedWorldForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: RecordId.parse(
          row['represented_context'] as String,
        ),
        record: RecordId.parse(row['record_id'] as String),
        selector: row['selector'] as String,
        settingType: row['setting_type'] as String,
        rationale: row['rationale'] as String,
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(row['draft_version'] as String),
        aliases: _db
            .select(
              'SELECT value FROM world_form_alias WHERE $_where ORDER BY ordinal',
              values,
            )
            .map((row) => row['value'] as String),
        labels: {
          for (final label in _db.select(
            'SELECT language,value FROM world_form_label WHERE $_where ORDER BY language',
            values,
          ))
            label['language'] as String: label['value'] as String,
        },
      ),
    );
  }

  SavedWorldForm? load(EditorFormScope scope) {
    try {
      _db.execute('BEGIN');
      final result = _read(scope);
      _db.execute('COMMIT');
      return result;
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  SavedWorldForm save(
    EditorFormScope scope,
    UnfinishedWorldForm form,
    BigInt expectedGeneration,
  ) {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    for (final text in [
      if (scope.worldClientRef != null) scope.worldClientRef!,
      form.selector,
      form.settingType,
      form.rationale,
      ...form.aliases,
      ...form.labels.keys,
      ...form.labels.values,
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    try {
      _db.execute('BEGIN IMMEDIATE');
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
      final saved = SavedWorldForm(
        generation: generation + BigInt.one,
        form: form,
      );
      final binding = _binding(scope);
      _db.execute(
        'INSERT INTO world_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(instance,profile,universe,continuity,editor_key) DO UPDATE SET generation=excluded.generation,base_revision=excluded.base_revision,represented_context=excluded.represented_context,record_id=excluded.record_id,selector=excluded.selector,setting_type=excluded.setting_type,rationale=excluded.rationale,draft_version=excluded.draft_version',
        [
          ...binding,
          saved.generation.toString(),
          form.baseRevision.value,
          form.representedContext.value,
          form.record.value,
          form.selector,
          form.settingType,
          form.rationale,
          form.draftVersion?.toString(),
        ],
      );
      _db.execute('DELETE FROM world_form_alias WHERE $_where', binding);
      _db.execute('DELETE FROM world_form_label WHERE $_where', binding);
      for (var i = 0; i < form.aliases.length; i++) {
        _db.execute('INSERT INTO world_form_alias VALUES(?,?,?,?,?,?,?)', [
          ...binding,
          i,
          form.aliases[i],
        ]);
      }
      for (final label in form.labels.entries) {
        _db.execute('INSERT INTO world_form_label VALUES(?,?,?,?,?,?,?)', [
          ...binding,
          label.key,
          label.value,
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
