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

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,holder_record,holder_universe,content_record,content_universe,altered,validity_root,alleged_enabled,alleged_record,alleged_universe,accessibility,rationale,original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('memory');
final _domainStorage = RecoveryDomainSchema([_originalModel]);
final _schema =
    """
CREATE TABLE memory_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,holder_record TEXT NOT NULL,holder_universe TEXT NOT NULL,content_record TEXT NOT NULL,content_universe TEXT NOT NULL,altered INTEGER CHECK(altered IN (0,1)),validity_root INTEGER NOT NULL REFERENCES memory_temporal(id),alleged_enabled INTEGER NOT NULL CHECK(alleged_enabled IN (0,1)),alleged_record TEXT NOT NULL,alleged_universe TEXT NOT NULL,accessibility TEXT NOT NULL,rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('memory')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'alleged_enabled',
            'altered',
            'ordinal',
            'original',
            'validity_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named memory fields, separate from canon.
final class MemoryFormRecoveryStore {
  MemoryFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'memory');

  static MemoryFormRecoveryStore open(String path) {
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
      return MemoryFormRecoveryStore._(db);
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
    final expected = {
      'memory_form': '$_keys,$_fields',
      ...RecoveryValueInputs.columns('memory'),
    };
    final current =
        version == 2 &&
        tables.length == expected.length + _domainStorage.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
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
      throw const FormatException('Choose the memory context.');
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

  ExpressionReferenceInput _ref(Row r, String prefix) =>
      ExpressionReferenceInput(
        record: _text(r, '${prefix}_record'),
        universe: _text(r, '${prefix}_universe'),
      );
  SavedMemoryForm? _read(EditorFormScope scope) {
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM memory_form WHERE $_where',
      _binding(scope),
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedMemoryForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedMemoryForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        holder: _ref(r, 'holder'),
        content: _ref(r, 'content'),
        altered: r['altered'] == null ? null : r['altered'] == 1,
        validity: _inputs.readTemporal(r['validity_root'] as int, 0),
        allegedEnabled: r['alleged_enabled'] == 1,
        alleged: _ref(r, 'alleged'),
        accessibility: _text(r, 'accessibility'),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : MemoryRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedMemoryForm saved) {
    final binding = _binding(scope), f = saved.form;
    final old = _db.select(
      'SELECT original,validity_root FROM memory_form WHERE $_where',
      binding,
    );
    final validityRoot = _inputs.writeTemporal(f.validity, 0),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO memory_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.holder.record,
        f.holder.universe,
        f.content.record,
        f.content.universe,
        f.altered == null
            ? null
            : f.altered!
            ? 1
            : 0,
        validityRoot,
        f.allegedEnabled ? 1 : 0,
        f.alleged.record,
        f.alleged.universe,
        f.accessibility,
        f.rationale,
        original,
        f.draftVersion?.toString(),
      ],
    );
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['validity_root'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedMemoryForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Memory form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedMemoryForm? load(EditorFormScope scope) {
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

  SavedMemoryForm save(
    EditorFormScope scope,
    UnfinishedMemoryForm form,
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
      final saved = SavedMemoryForm(
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
