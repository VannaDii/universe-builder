import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _v1Columns =
    'instance,profile,universe,continuity,context,editor_key,generation,base_revision,draft_version,value_input';
const _columns = '$_v1Columns,evidence_input';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE attribute_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, draft_version TEXT NOT NULL,
 value_input TEXT NOT NULL, evidence_input TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";

/// Device-private incomplete attribute value input, separate from canon.
final class AttributeFormRecoveryStore {
  AttributeFormRecoveryStore._(this._db);
  final Database _db;

  static AttributeFormRecoveryStore open(String path) {
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
            'ALTER TABLE attribute_form ADD COLUMN evidence_input TEXT',
          );
          db.execute('PRAGMA user_version=2');
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
      return AttributeFormRecoveryStore._(db);
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
    if (tables.length != 1 ||
        (version != 1 && version != 2) ||
        db
                .select('PRAGMA table_info(attribute_form)')
                .map((row) => row['name'])
                .join(',') !=
            (version == 1 ? _v1Columns : _columns)) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return version as int;
  }

  List<String> _binding(EditorFormScope scope) {
    if (scope.representedContext == null ||
        scope.attributeClientRef == null ||
        scope.attributeClientRef!.isEmpty ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.typeClientRef != null ||
        scope.entityClientRef != null ||
        scope.entityNameRecord != null ||
        scope.entityClassificationRecord != null ||
        scope.entityOperationIndex != null) {
      throw const FormatException('Choose the attribute edit context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
      scope.attributeClientRef!,
    ];
  }

  SavedAttributeForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT * FROM attribute_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedAttributeForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedAttributeForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: RecordId.parse(row['context'] as String),
        clientRef: row['editor_key'] as String,
        draftVersion: BigInt.parse(row['draft_version'] as String),
        evidenceInput: row['evidence_input'] == null
            ? null
            : AttributeEvidenceInput.fromWire(
                CanonicalValue.parseWireJson(row['evidence_input'] as String),
              ),
        value: QualifierInput.fromWire(
          CanonicalValue.parseWireJson(row['value_input'] as String),
        ),
      ),
    );
  }

  SavedAttributeForm? load(EditorFormScope scope) {
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

  SavedAttributeForm save(
    EditorFormScope scope,
    UnfinishedAttributeForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (scope.representedContext != form.representedContext ||
        scope.attributeClientRef != form.clientRef) {
      throw const FormatException('Attribute form context does not match.');
    }
    for (final text in [
      form.clientRef,
      ...form.value.exactTexts,
      if (form.evidenceInput != null) ...form.evidenceInput!.exactTexts,
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
      final saved = SavedAttributeForm(
        generation: generation + BigInt.one,
        form: form,
      );
      _db.execute(
        'INSERT INTO attribute_form VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(instance,profile,universe,continuity,context,editor_key) DO UPDATE SET generation=excluded.generation,base_revision=excluded.base_revision,draft_version=excluded.draft_version,value_input=excluded.value_input,evidence_input=excluded.evidence_input',
        [
          ...binding,
          saved.generation.toString(),
          form.baseRevision.value,
          form.draftVersion.toString(),
          form.value.toWire().toText(),
          form.evidenceInput?.toWire().toText(),
        ],
      );
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
