import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _columns =
    'instance,profile,generation,operation,name,mode,phase,file_name,review,receipt';

/// Private import choices. Review and receipt are canonical domain records;
/// unfinished input remains named fields, separate from admitted universe data.
final class PackageImportFormRecoveryStore {
  PackageImportFormRecoveryStore._(this._db);
  final Database _db;

  static PackageImportFormRecoveryStore open(String path) {
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
        'PRAGMA busy_timeout=1000; PRAGMA synchronous=FULL; PRAGMA journal_mode=WAL',
      );
      db.execute('BEGIN IMMEDIATE');
      try {
        if (!_checkSchema(db)) {
          db.execute('''
CREATE TABLE package_import_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, generation TEXT NOT NULL,
 operation TEXT NOT NULL, name TEXT NOT NULL, mode TEXT NOT NULL,
 phase TEXT NOT NULL, file_name TEXT NOT NULL, review TEXT, receipt TEXT,
 PRIMARY KEY(instance,profile)
) STRICT;
PRAGMA user_version=1;
''');
        }
        db.execute('COMMIT');
      } on Object {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
      for (final suffix in ['-wal', '-shm']) {
        if (File('$actual$suffix').existsSync()) {
          protectedFile('$actual$suffix');
        }
      }
      return PackageImportFormRecoveryStore._(db);
    } on Object {
      db?.close();
      rethrow;
    }
  }

  static bool _checkSchema(Database db) {
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    if (tables.isEmpty) return false;
    if (db.select('PRAGMA user_version').single.values.single != 1 ||
        tables.length != 1 ||
        tables.single['name'] != 'package_import_form' ||
        db
                .select('PRAGMA table_info(package_import_form)')
                .map((r) => r['name'])
                .join(',') !=
            _columns) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return true;
  }

  SavedPackageImport? load((OperationId, ProfileId) scope) {
    final rows = _db.select(
      'SELECT *,CAST(name AS BLOB) AS exact_name,CAST(file_name AS BLOB) AS exact_file_name FROM package_import_form WHERE instance=? AND profile=?',
      [scope.$1.value, scope.$2.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedPackageImport(
      generation: BigInt.parse(row['generation'] as String),
      form: PackageImportDraft(
        operation: OperationId.parse(row['operation'] as String),
        name: decodeExactUtf8(row['exact_name'] as List<int>),
        mode: ImportMode.fromName(row['mode'] as String),
        phase: PackageImportPhase.values.byName(row['phase'] as String),
        fileName: decodeExactUtf8(row['exact_file_name'] as List<int>),
        review: row['review'] == null
            ? null
            : CanonicalValue.parseWireJson(row['review'] as String)
                  as CanonicalObject,
        receipt: row['receipt'] == null
            ? null
            : CanonicalValue.parseWireJson(row['receipt'] as String)
                  as CanonicalObject,
      ),
    );
  }

  SavedPackageImport save(
    (OperationId, ProfileId) scope,
    PackageImportDraft form,
    BigInt expectedGeneration,
  ) {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    for (final text in [form.name, form.fileName, form.toWire().toText()]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = load(scope),
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
      final saved = SavedPackageImport(
        form: form,
        generation: generation + BigInt.one,
      );
      _db.execute(
        'INSERT OR REPLACE INTO package_import_form($_columns) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          scope.$1.value,
          scope.$2.value,
          saved.generation.toString(),
          form.operation.value,
          form.name,
          form.mode.name,
          form.phase.name,
          form.fileName,
          form.review?.toText(),
          form.receipt?.toText(),
        ],
      );
      _db.execute('COMMIT');
      return saved;
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();
}
