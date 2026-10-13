import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _columns =
    'instance,profile,universe,continuity,context,generation,base_revision,client_ref,namespace,key,name,parent_choice,applicability_choice,rationale,classification_executable';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=?';
const _schema = '''
CREATE TABLE type_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, generation TEXT NOT NULL,
 base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, namespace TEXT NOT NULL,
 key TEXT NOT NULL, name TEXT NOT NULL, parent_choice TEXT NOT NULL,
 applicability_choice TEXT NOT NULL, rationale TEXT NOT NULL,
 classification_executable INTEGER CHECK(classification_executable IN (0,1)),
 PRIMARY KEY(instance,profile,universe,continuity,context)
) STRICT;
CREATE TABLE type_form_world (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context) REFERENCES type_form(instance,profile,universe,continuity,context) ON DELETE CASCADE
) STRICT;
PRAGMA user_version=1;
''';

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
        if (_checkSchema(db)) {
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

  static bool _checkSchema(Database db) {
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    if (tables.isEmpty) return true;
    if (tables.length != 2 ||
        db.select('PRAGMA user_version').single.values.single != 1 ||
        db
                .select('PRAGMA table_info(type_form)')
                .map((row) => row['name'])
                .join(',') !=
            _columns ||
        db
                .select('PRAGMA table_info(type_form_world)')
                .map((row) => row['name'])
                .join(',') !=
            'instance,profile,universe,continuity,context,ordinal,world') {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return false;
  }

  List<String> _binding(EditorFormScope scope) {
    if (scope.representedContext == null ||
        scope.worldClientRef != null ||
        scope.worldRecord != null) {
      throw const FormatException('Choose the type form context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
    ];
  }

  SavedTypeForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select('SELECT * FROM type_form WHERE $_where', binding);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedTypeForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedTypeForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: RecordId.parse(row['context'] as String),
        clientRef: row['client_ref'] as String,
        namespace: row['namespace'] as String,
        key: row['key'] as String,
        name: row['name'] as String,
        parentChoice: row['parent_choice'] as String,
        applicabilityChoice: row['applicability_choice'] as String,
        rationale: row['rationale'] as String,
        classificationExecutable: row['classification_executable'] == null
            ? null
            : row['classification_executable'] == 1,
        worlds: _db
            .select(
              'SELECT world FROM type_form_world WHERE $_where ORDER BY ordinal',
              binding,
            )
            .map((row) => WorldId.parse(row['world'] as String)),
      ),
    );
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

  SavedTypeForm save(
    EditorFormScope scope,
    UnfinishedTypeForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext) {
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
      final saved = SavedTypeForm(
        generation: generation + BigInt.one,
        form: form,
      );
      _db.execute(
        'INSERT INTO type_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(instance,profile,universe,continuity,context) DO UPDATE SET generation=excluded.generation,base_revision=excluded.base_revision,client_ref=excluded.client_ref,namespace=excluded.namespace,key=excluded.key,name=excluded.name,parent_choice=excluded.parent_choice,applicability_choice=excluded.applicability_choice,rationale=excluded.rationale,classification_executable=excluded.classification_executable',
        [
          ...binding,
          saved.generation.toString(),
          form.baseRevision.value,
          form.clientRef,
          form.namespace,
          form.key,
          form.name,
          form.parentChoice,
          form.applicabilityChoice,
          form.rationale,
          form.classificationExecutable == null
              ? null
              : (form.classificationExecutable! ? 1 : 0),
        ],
      );
      _db.execute('DELETE FROM type_form_world WHERE $_where', binding);
      for (var i = 0; i < form.worlds.length; i++) {
        _db.execute('INSERT INTO type_form_world VALUES(?,?,?,?,?,?,?)', [
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
