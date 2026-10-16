import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';
import 'catalog.dart';
import 'relational.dart';
import 'recovery_domain_rows.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _fields =
    'generation,base_revision,value,mode,reason,rationale,target_record,target_universe,expected_record_version,original,draft_version';
final _originalModel = 'Chronology';
final _domainStorage = RecoveryDomainSchema([_originalModel]);
final _schema =
    """
CREATE TABLE story_time_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, value TEXT NOT NULL, mode TEXT NOT NULL, reason TEXT NOT NULL, rationale TEXT NOT NULL,
 target_record TEXT NOT NULL, target_universe TEXT NOT NULL, expected_record_version TEXT NOT NULL, original INTEGER NOT NULL REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id), draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";

String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) => <String>{}.contains(c) || c == 'original'
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named input fields and the pinned original domain chronology.
final class StoryTimeFormRecoveryStore {
  StoryTimeFormRecoveryStore._(this._db);
  final Database _db;
  static StoryTimeFormRecoveryStore open(String path) {
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
      return StoryTimeFormRecoveryStore._(db);
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
        .map((r) => r['name'])
        .toSet();
    if (names.isEmpty) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    final expected = {'story_time_form': '$_keys,$_fields'};
    final columnsMatch = expected.entries.every(
      (e) =>
          db
              .select('PRAGMA table_info(${e.key})')
              .map((r) => r['name'])
              .join(',') ==
          e.value,
    );
    final current =
        version == 2 &&
        names.length == expected.length + _domainStorage.statements.length &&
        columnsMatch &&
        db
                .select('PRAGMA table_info(story_time_form)')
                .singleWhere((r) => r['name'] == 'original')['type'] ==
            'INTEGER' &&
        _domainStorage.matches(db);
    if (!current) {
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
      throw const FormatException('Choose the story time context.');
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

  SavedStoryTimeForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM story_time_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedStoryTimeForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedStoryTimeForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        target: ExpressionReferenceInput(
          record: _text(row, 'target_record'),
          universe: _text(row, 'target_universe'),
        ),
        expectedRecordVersion: RecordVersionId.parse(
          _text(row, 'expected_record_version'),
        ),
        original: Chronology.fromWire(
          RelationalCodec(_db).get(_originalModel, row['original']),
        ),
        value: _text(row, 'value'),
        mode: _text(row, 'mode'),
        reason: _text(row, 'reason'),
        rationale: _text(row, 'rationale'),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
      ),
    );
  }

  SavedStoryTimeForm? load(EditorFormScope scope) {
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

  void _validate(EditorFormScope scope, UnfinishedStoryTimeForm form) {
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
  }

  SavedStoryTimeForm save(
    EditorFormScope scope,
    UnfinishedStoryTimeForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= (BigInt.one << 64)) {
      throw const FormatException('Invalid expected editor generation');
    }
    _validate(scope, form);
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
      final old = _db.select(
        'SELECT original FROM story_time_form WHERE $_where',
        binding,
      );
      final original = RelationalCodec(_db)
          .put(_originalModel, form.original.toWire());
      final values = <Object?>[
        ...binding,
        next.toString(),
        form.baseRevision.value,
        form.value,
        form.mode,
        form.reason,
        form.rationale,
        form.target.record,
        form.target.universe,
        form.expectedRecordVersion.value,
        original,
        form.draftVersion?.toString(),
      ];
      final columns = '$_keys,$_fields'.split(',');
      _db.execute(
        'INSERT INTO story_time_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((field) => '$field=excluded.$field').join(',')}',
        values,
      );
      if (old.isNotEmpty) {
        _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
      }
      _db.execute('COMMIT');
      return SavedStoryTimeForm(generation: next, form: form);
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  BigInt currentGeneration(SavedStoryTimeForm? current) =>
      current?.generation ?? BigInt.zero;
  void close() => _db.close();
}
