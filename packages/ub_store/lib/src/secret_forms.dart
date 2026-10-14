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
    'generation,base_revision,client_ref,reader_disclosed,has_concealment,concealment,validity_kind,calendar,start,end,start_unbounded,end_unbounded,rationale,target_record,target_universe,expected_record_version,original,draft_version';
const _schema = """
CREATE TABLE secret_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 reader_disclosed INTEGER CHECK(reader_disclosed IN (0,1)), has_concealment INTEGER NOT NULL CHECK(has_concealment IN (0,1)),
 concealment TEXT NOT NULL, validity_kind TEXT NOT NULL, calendar TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL,
 start_unbounded INTEGER NOT NULL CHECK(start_unbounded IN (0,1)), end_unbounded INTEGER NOT NULL CHECK(end_unbounded IN (0,1)),
 rationale TEXT NOT NULL, target_record TEXT, target_universe TEXT, expected_record_version TEXT, original TEXT, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE secret_reference (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('scope','fictional_knowers')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), record_input TEXT NOT NULL, universe_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES secret_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=1;
""";

/// Device-private named fields and ordered references. Only the retained original
/// is a canonical domain record; incomplete form state is never a JSON blob.
final class SecretFormRecoveryStore {
  SecretFormRecoveryStore._(this._db);
  final Database _db;
  static SecretFormRecoveryStore open(String path) {
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
      return SecretFormRecoveryStore._(db);
    } on EditorRecoveryException {
      db?.close();
      rethrow;
    } on Object {
      db?.close();
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  static int _checkSchema(Database db) {
    final names = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row['name'])
        .toSet();
    if (names.isEmpty) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    if (version != 1 ||
        names.length != 2 ||
        !names.containsAll(['secret_form', 'secret_reference']) ||
        db
                .select('PRAGMA table_info(secret_form)')
                .map((row) => row['name'])
                .join(',') !=
            '$_keys,$_fields' ||
        db
                .select('PRAGMA table_info(secret_reference)')
                .map((row) => row['name'])
                .join(',') !=
            '$_keys,list_kind,ordinal,record_input,universe_input') {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return 1;
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
      throw const FormatException('Choose the story secret context.');
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

  SavedSecretForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select('SELECT * FROM secret_form WHERE $_where', binding);
    if (rows.isEmpty) return null;
    final row = rows.single;
    List<ExpressionReferenceInput> references(String kind) => _db
        .select(
          'SELECT record_input,universe_input FROM secret_reference WHERE $_where AND list_kind=? ORDER BY ordinal',
          [...binding, kind],
        )
        .map(
          (child) => ExpressionReferenceInput(
            record: child['record_input'] as String,
            universe: child['universe_input'] as String,
          ),
        )
        .toList();
    return SavedSecretForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedSecretForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: scope.representedContext!,
        clientRef: row['client_ref'] as String,
        scope: references('scope'),
        fictionalKnowers: references('fictional_knowers'),
        readerDisclosed: row['reader_disclosed'] == null
            ? null
            : row['reader_disclosed'] == 1,
        hasConcealment: row['has_concealment'] == 1,
        concealment: row['concealment'] as String,
        validityKind: row['validity_kind'] as String,
        calendar: row['calendar'] as String,
        start: row['start'] as String,
        end: row['end'] as String,
        startUnbounded: row['start_unbounded'] == 1,
        endUnbounded: row['end_unbounded'] == 1,
        rationale: row['rationale'] as String,
        revisionTarget: row['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: row['target_record'] as String,
                universe: row['target_universe'] as String,
              ),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(row['expected_record_version'] as String),
        original: row['original'] == null
            ? null
            : SecretRecord.fromWire(
                CanonicalValue.parseWireJson(row['original'] as String),
              ),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(row['draft_version'] as String),
      ),
    );
  }

  SavedSecretForm? load(EditorFormScope scope) {
    _db.execute('BEGIN');
    try {
      final form = _read(scope);
      _db.execute('COMMIT');
      return form;
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  SavedSecretForm save(
    EditorFormScope scope,
    UnfinishedSecretForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= (BigInt.one << 64)) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (form.representedContext != scope.representedContext ||
        scope.typeClientRef != null &&
            scope.typeClientRef != form.recoveryKey) {
      throw const FormatException('Story secret form scope does not match.');
    }
    void exact(CanonicalValue value) {
      switch (value) {
        case CanonicalString(:final value):
          if (decodeExactUtf8(utf8.encode(value)) != value) {
            throw const EditorRecoveryException(
              EditorRecoveryFailure.invalidText,
            );
          }
        case CanonicalArray(:final items):
          for (final child in items) {
            exact(child);
          }
        case CanonicalObject(:final fields):
          for (final field in fields) {
            exact(field.value);
          }
        default:
          break;
      }
    }

    exact(form.toWire());
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = _read(scope), generation = currentGeneration(current);
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
      final next = generation + BigInt.one;
      final values = <Object?>[
        ...binding,
        next.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.readerDisclosed == null
            ? null
            : form.readerDisclosed!
            ? 1
            : 0,
        form.hasConcealment ? 1 : 0,
        form.concealment,
        form.validityKind,
        form.calendar,
        form.start,
        form.end,
        form.startUnbounded ? 1 : 0,
        form.endUnbounded ? 1 : 0,
        form.rationale,
        form.revisionTarget?.record,
        form.revisionTarget?.universe,
        form.expectedRecordVersion?.value,
        form.original?.toWire().toText(),
        form.draftVersion?.toString(),
      ];
      final columns = '$_keys,$_fields'.split(',');
      _db.execute(
        'INSERT INTO secret_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((field) => '$field=excluded.$field').join(',')}',
        values,
      );
      _db.execute('DELETE FROM secret_reference WHERE $_where', binding);
      for (final (kind, refs) in [
        ('scope', form.scope),
        ('fictional_knowers', form.fictionalKnowers),
      ]) {
        for (var i = 0; i < refs.length; i++) {
          _db.execute(
            'INSERT INTO secret_reference VALUES(?,?,?,?,?,?,?,?,?,?)',
            [...binding, kind, i, refs[i].record, refs[i].universe],
          );
        }
      }
      _db.execute('COMMIT');
      return SavedSecretForm(generation: next, form: form);
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  BigInt currentGeneration(SavedSecretForm? current) =>
      current?.generation ?? BigInt.zero;
  void close() => _db.close();
}
