import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _fields =
    'generation,base_revision,client_ref,instance_record,instance_universe,start_record,start_universe,definition_record,definition_version,definition_universe,applicability,context_record,context_universe,has_realm,realm_record,realm_universe,end_kind,end_coordinate,rationale,draft_version';
const _schema = '''
CREATE TABLE initialization_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 instance_record TEXT NOT NULL, instance_universe TEXT NOT NULL,
 start_record TEXT NOT NULL, start_universe TEXT NOT NULL,
 definition_record TEXT, definition_version TEXT, definition_universe TEXT,
 applicability TEXT NOT NULL, context_record TEXT NOT NULL, context_universe TEXT NOT NULL,
 has_realm INTEGER NOT NULL CHECK(has_realm IN (0,1)), realm_record TEXT NOT NULL, realm_universe TEXT NOT NULL,
 end_kind TEXT NOT NULL, end_coordinate TEXT NOT NULL, rationale TEXT NOT NULL, draft_version TEXT,
 CHECK((definition_record IS NULL AND definition_version IS NULL AND definition_universe IS NULL)
       OR (definition_record IS NOT NULL AND definition_version IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE initialization_world (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), world_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key)
 REFERENCES initialization_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=1;
''';

/// Named private fields and ordered world inputs, separate from canonical work.
final class InitializationFormRecoveryStore {
  InitializationFormRecoveryStore._(this._db);
  final Database _db;

  static InitializationFormRecoveryStore open(String path) {
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
        if (_checkSchema(db) == 0) db.execute(_schema);
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
      return InitializationFormRecoveryStore._(db);
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
    if (version != 1 ||
        tables.length != 2 ||
        db
                .select('PRAGMA table_info(initialization_form)')
                .map((r) => r['name'])
                .join(',') !=
            '$_keys,$_fields' ||
        db
                .select('PRAGMA table_info(initialization_world)')
                .map((r) => r['name'])
                .join(',') !=
            '$_keys,ordinal,world_input') {
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
      throw const FormatException('Choose the initialization context.');
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

  SavedInitializationForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      "SELECT ${'$_keys,$_fields'.split(',').map((c) => c == 'has_realm' ? c : 'CAST($c AS BLOB) AS $c').join(',')} FROM initialization_form WHERE $_where",
      binding,
    );
    if (rows.isEmpty) return null;
    final row = <String, Object?>{
      for (final column in '$_keys,$_fields'.split(','))
        column: rows.single[column] is List<int>
            ? decodeExactUtf8(rows.single[column] as List<int>)
            : rows.single[column],
    };
    return SavedInitializationForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedInitializationForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: scope.representedContext!,
        clientRef: row['client_ref'] as String,
        instance: ExpressionReferenceInput(
          record: row['instance_record'] as String,
          universe: row['instance_universe'] as String,
        ),
        start: ExpressionReferenceInput(
          record: row['start_record'] as String,
          universe: row['start_universe'] as String,
        ),
        definition: row['definition_record'] == null
            ? null
            : VersionRef(
                record: RecordId.parse(row['definition_record'] as String),
                version: RecordVersionId.parse(
                  row['definition_version'] as String,
                ),
                universe: row['definition_universe'] == null
                    ? null
                    : UniverseId.parse(row['definition_universe'] as String),
              ),
        scope: ScopeInput(
          applicability: row['applicability'] as String,
          worlds: _db
              .select(
                'SELECT CAST(world_input AS BLOB) AS world_input FROM initialization_world WHERE $_where ORDER BY ordinal',
                binding,
              )
              .map((r) => decodeExactUtf8(r['world_input'] as List<int>))
              .toList(),
          contextRecord: row['context_record'] as String,
          contextUniverse: row['context_universe'] as String,
          hasRealm: row['has_realm'] == 1,
          realmRecord: row['realm_record'] as String,
          realmUniverse: row['realm_universe'] as String,
        ),
        endKind: row['end_kind'] as String,
        endCoordinate: row['end_coordinate'] as String,
        rationale: row['rationale'] as String,
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(row['draft_version'] as String),
      ),
    );
  }

  SavedInitializationForm? load(EditorFormScope scope) {
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

  SavedInitializationForm save(
    EditorFormScope scope,
    UnfinishedInitializationForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= (BigInt.one << 64)) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (form.representedContext != scope.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Initialization form scope does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = _read(scope),
          generation = current?.generation ?? BigInt.zero;
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
      final saved = SavedInitializationForm(
        generation: generation + BigInt.one,
        form: form,
      );
      final values = <Object?>[
        ...binding,
        saved.generation.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.instance.record,
        form.instance.universe,
        form.start.record,
        form.start.universe,
        form.definition?.record.value,
        form.definition?.version.value,
        form.definition?.universe?.value,
        form.scope.applicability,
        form.scope.contextRecord,
        form.scope.contextUniverse,
        form.scope.hasRealm ? 1 : 0,
        form.scope.realmRecord,
        form.scope.realmUniverse,
        form.endKind,
        form.endCoordinate,
        form.rationale,
        form.draftVersion?.toString(),
      ];
      final columns = '$_keys,$_fields'.split(',');
      _db.execute(
        'INSERT INTO initialization_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((field) => '$field=excluded.$field').join(',')}',
        values,
      );
      _db.execute('DELETE FROM initialization_world WHERE $_where', binding);
      for (var i = 0; i < form.scope.worlds.length; i++) {
        _db.execute(
          'INSERT INTO initialization_world VALUES(?,?,?,?,?,?,?,?)',
          [...binding, i, form.scope.worlds[i]],
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
