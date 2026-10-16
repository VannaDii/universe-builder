import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,principal,mode,decision_scope,rationale,draft_version,has_original,original_mode,original_scope,original_rationale,original_principal';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE issue_decision_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 principal TEXT NOT NULL, mode TEXT NOT NULL, decision_scope TEXT NOT NULL,
 rationale TEXT NOT NULL, draft_version TEXT,
 has_original INTEGER NOT NULL CHECK(has_original IN (0,1)),
 original_mode TEXT, original_scope TEXT, original_rationale TEXT, original_principal TEXT,
 CHECK((has_original=0 AND original_mode IS NULL AND original_scope IS NULL AND original_rationale IS NULL AND original_principal IS NULL)
    OR (has_original=1 AND original_mode IS NOT NULL AND original_scope IS NOT NULL AND original_rationale IS NOT NULL AND original_principal IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE issue_decision_fingerprint (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')),
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), fingerprint_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key)
 REFERENCES issue_decision_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map((c) => c == 'has_original' ? c : 'CAST($c AS BLOB) AS $c')
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Named private fields and ordered fingerprints, separate from canon.
final class IssueDecisionFormRecoveryStore {
  IssueDecisionFormRecoveryStore._(this._db);
  final Database _db;

  static IssueDecisionFormRecoveryStore open(String path) {
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
      return IssueDecisionFormRecoveryStore._(db);
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
    final main = db
        .select('PRAGMA table_info(issue_decision_form)')
        .map((row) => row['name'])
        .join(',');
    final current =
        version == 2 &&
        tables.length == 2 &&
        main == '$_keys,$_fields' &&
        db
                .select('PRAGMA table_info(issue_decision_fingerprint)')
                .map((row) => row['name'])
                .join(',') ==
            '$_keys,list_kind,ordinal,fingerprint_input';
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
      throw const FormatException('Choose the issue_decision context.');
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

  SavedIssueDecisionForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection('$_keys,$_fields')} FROM issue_decision_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    List<String> fingerprints(String kind) => _db
        .select(
          'SELECT CAST(fingerprint_input AS BLOB) AS fingerprint_input FROM issue_decision_fingerprint WHERE $_where AND list_kind=? ORDER BY ordinal',
          [...binding, kind],
        )
        .map((r) => _text(r, 'fingerprint_input'))
        .toList();
    return SavedIssueDecisionForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedIssueDecisionForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        principal: PrincipalId.parse(_text(row, 'principal')),
        mode: _text(row, 'mode'),
        fingerprints: fingerprints('input'),
        scope: _text(row, 'decision_scope'),
        rationale: _text(row, 'rationale'),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
        original: row['has_original'] == 0
            ? null
            : IssueDecisionRecord(
                fingerprints: fingerprints('original')
                    .map(FindingFingerprint.new),
                mode: IssueDecisionMode.fromName(_text(row, 'original_mode')),
                scope: _text(row, 'original_scope'),
                rationale: _text(row, 'original_rationale'),
                principal: PrincipalId.parse(_text(row, 'original_principal')),
              ),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedIssueDecisionForm saved) {
    final binding = _binding(scope),
        form = saved.form,
        original = form.original;
    final values = <Object?>[
      ...binding,
      saved.generation.toString(),
      form.baseRevision.value,
      form.clientRef,
      form.principal.value,
      form.mode,
      form.scope,
      form.rationale,
      form.draftVersion?.toString(),
      original == null ? 0 : 1,
      original?.mode.name,
      original?.scope,
      original?.rationale,
      original?.principal.value,
    ];
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO issue_decision_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      values,
    );
    _db.execute(
      'DELETE FROM issue_decision_fingerprint WHERE $_where',
      binding,
    );
    final lists = {
      'input': form.fingerprints,
      'original':
          original?.fingerprints.map((f) => f.value).toList() ?? <String>[],
    };
    for (final list in lists.entries) {
      for (var i = 0; i < list.value.length; i++) {
        _db.execute(
          'INSERT INTO issue_decision_fingerprint VALUES(?,?,?,?,?,?,?,?,?)',
          [...binding, list.key, i, list.value[i]],
        );
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedIssueDecisionForm form) {
    if (form.principal.value !=
            scope.profile.value.replaceFirst('prf_', 'prn_') ||
        scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException(
        'Issue decision form context does not match.',
      );
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
  }

  SavedIssueDecisionForm? load(EditorFormScope scope) {
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

  SavedIssueDecisionForm save(
    EditorFormScope scope,
    UnfinishedIssueDecisionForm form,
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
      final saved = SavedIssueDecisionForm(
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
