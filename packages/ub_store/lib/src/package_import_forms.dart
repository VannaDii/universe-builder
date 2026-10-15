import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _columns =
    'instance,profile,generation,operation,name,mode,phase,file_name,review,receipt';

const _reviewStrings = [
  'preview_id',
  'digest',
  'source_universe',
  'target_universe',
  'name',
  'record_ids',
  'version_ids',
  'references',
  'workflow_and_approvals',
];
const _reviewNumbers = ['omitted_records', 'record_count'];
const _reviewBools = [
  'complete',
  'includes_history',
  'includes_workflow',
  'canonical',
];
const _receiptStrings = ['preview_id', 'digest', 'universe_id', 'name'];
const _receiptNumbers = ['omitted_records'];
const _receiptBools = ['complete', 'imported'];
const _keys = 'instance,profile';
List<String> _fields(bool review) => review
    ? [
        ..._reviewStrings,
        ..._reviewNumbers,
        ..._reviewBools,
        'conflicts_present',
      ]
    : [..._receiptStrings, ..._receiptNumbers, ..._receiptBools];
String _projection(Iterable<String> columns) =>
    columns.map((c) => 'CAST("$c" AS BLOB) AS "$c"').join(',');
String _text(Row r, String c) => decodeExactUtf8(r[c] as List<int>);
final _schema =
    """
CREATE TABLE package_import_form (instance TEXT NOT NULL,profile TEXT NOT NULL,generation TEXT NOT NULL,operation TEXT NOT NULL,name TEXT NOT NULL,mode TEXT NOT NULL,phase TEXT NOT NULL,file_name TEXT NOT NULL,PRIMARY KEY(instance,profile)) STRICT;
${[true, false].map((review) {
      final strings = review ? _reviewStrings : _receiptStrings, numbers = review ? _reviewNumbers : _receiptNumbers, bools = review ? _reviewBools : _receiptBools;
      return 'CREATE TABLE package_import_${review ? 'review' : 'receipt'}(instance TEXT NOT NULL,profile TEXT NOT NULL,${[...strings, ...numbers].map((c) => '"$c" TEXT').join(',')},${bools.map((c) => '$c INTEGER CHECK($c IN (0,1))').join(',')}${review ? ',conflicts_present INTEGER NOT NULL CHECK(conflicts_present IN (0,1))' : ''},PRIMARY KEY(instance,profile),FOREIGN KEY(instance,profile) REFERENCES package_import_form(instance,profile) ON DELETE CASCADE) STRICT;';
    }).join('\n')}
CREATE TABLE package_import_conflict(instance TEXT NOT NULL,profile TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),conflict TEXT NOT NULL,PRIMARY KEY(instance,profile,ordinal),FOREIGN KEY(instance,profile) REFERENCES package_import_review(instance,profile) ON DELETE CASCADE) STRICT;
PRAGMA user_version=2;
""";

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
        'PRAGMA foreign_keys=ON; PRAGMA busy_timeout=1000; PRAGMA synchronous=FULL; PRAGMA journal_mode=WAL',
      );
      db.execute('BEGIN IMMEDIATE');
      try {
        final version = _checkSchema(db);
        if (version == 0) {
          db.execute(_schema);
        } else if (version == 1) {
          db.execute(
            'ALTER TABLE package_import_form RENAME TO legacy_package_import_form',
          );
          db.execute(_schema);
          final store = PackageImportFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_projection(_columns.split(','))} FROM legacy_package_import_form',
          )) {
            final scope = (
              OperationId.parse(_text(row, 'instance')),
              ProfileId.parse(_text(row, 'profile')),
            );
            final saved = SavedPackageImport(
              generation: BigInt.parse(_text(row, 'generation')),
              form: PackageImportDraft(
                operation: OperationId.parse(_text(row, 'operation')),
                name: _text(row, 'name'),
                mode: ImportMode.fromName(_text(row, 'mode')),
                phase: PackageImportPhase.values.byName(_text(row, 'phase')),
                fileName: _text(row, 'file_name'),
                review: row['review'] == null
                    ? null
                    : CanonicalValue.parseWireJson(_text(row, 'review'))
                          as CanonicalObject,
                receipt: row['receipt'] == null
                    ? null
                    : CanonicalValue.parseWireJson(_text(row, 'receipt'))
                          as CanonicalObject,
              ),
            );
            store._write(scope, saved);
          }
          db.execute('DROP TABLE legacy_package_import_form');
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

  static int _checkSchema(Database db) {
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    if (tables.isEmpty) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    String columns(String table) =>
        db.select('PRAGMA table_info($table)').map((r) => r['name']).join(',');
    final expected = {
      'package_import_form': _columns.split(',').take(8).join(','),
      'package_import_review': '$_keys,${_fields(true).join(',')}',
      'package_import_receipt': '$_keys,${_fields(false).join(',')}',
      'package_import_conflict': '$_keys,ordinal,conflict',
    };
    if (version == 1 &&
        tables.length == 1 &&
        columns('package_import_form') == _columns) {
      return 1;
    }
    if (version == 2 &&
        tables.length == expected.length &&
        expected.entries.every((e) => columns(e.key) == e.value)) {
      return 2;
    }
    throw const EditorRecoveryException(
      EditorRecoveryFailure.incompatibleSchema,
    );
  }

  CanonicalObject? _readReport((OperationId, ProfileId) scope, bool review) {
    final strings = review ? _reviewStrings : _receiptStrings,
        numbers = review ? _reviewNumbers : _receiptNumbers,
        bools = review ? _reviewBools : _receiptBools;
    final rows = _db.select(
      'SELECT ${_projection([...strings, ...numbers])},${[...bools, if (review) 'conflicts_present'].join(',')} FROM package_import_${review ? 'review' : 'receipt'} WHERE instance=? AND profile=?',
      [scope.$1.value, scope.$2.value],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final fields = <MapEntry<String, CanonicalValue>>[
      for (final c in strings)
        if (r[c] != null) MapEntry(c, CanonicalString(_text(r, c))),
      for (final c in numbers)
        if (r[c] != null) MapEntry(c, CanonicalNumber(_text(r, c))),
      for (final c in bools)
        if (r[c] != null) MapEntry(c, CanonicalBool(r[c] == 1)),
    ];
    if (review && r['conflicts_present'] == 1) {
      final conflicts = _db.select(
        'SELECT ordinal,CAST(conflict AS BLOB) AS conflict FROM package_import_conflict WHERE instance=? AND profile=? ORDER BY ordinal',
        [scope.$1.value, scope.$2.value],
      );
      for (var i = 0; i < conflicts.length; i++) {
        if (conflicts[i]['ordinal'] != i) {
          throw const FormatException('Incomplete import conflicts');
        }
      }
      fields.add(
        MapEntry(
          'conflicts',
          CanonicalArray(
            conflicts.map((r) => CanonicalString(_text(r, 'conflict'))),
          ),
        ),
      );
    }
    return CanonicalObject(fields);
  }

  SavedPackageImport? _read((OperationId, ProfileId) scope) {
    final rows = _db.select(
      'SELECT ${_projection(_columns.split(',').take(8))} FROM package_import_form WHERE instance=? AND profile=?',
      [scope.$1.value, scope.$2.value],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedPackageImport(
      generation: BigInt.parse(_text(r, 'generation')),
      form: PackageImportDraft(
        operation: OperationId.parse(_text(r, 'operation')),
        name: _text(r, 'name'),
        mode: ImportMode.fromName(_text(r, 'mode')),
        phase: PackageImportPhase.values.byName(_text(r, 'phase')),
        fileName: _text(r, 'file_name'),
        review: _readReport(scope, true),
        receipt: _readReport(scope, false),
      ),
    );
  }

  SavedPackageImport? load((OperationId, ProfileId) scope) {
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

  void _writeReport(
    (OperationId, ProfileId) scope,
    CanonicalObject? report,
    bool review,
  ) {
    if (report == null) return;
    final strings = review ? _reviewStrings : _receiptStrings,
        numbers = review ? _reviewNumbers : _receiptNumbers,
        bools = review ? _reviewBools : _receiptBools;
    final fields = Map.fromEntries(report.fields);
    if (fields.keys.any(
      (k) => ![
        ...strings,
        ...numbers,
        ...bools,
        if (review) 'conflicts',
      ].contains(k),
    )) {
      throw const FormatException('Unsupported import report field');
    }
    final values = <Object?>[
      scope.$1.value,
      scope.$2.value,
      for (final c in strings)
        fields.containsKey(c) ? (fields[c] as CanonicalString).value : null,
      for (final c in numbers)
        fields.containsKey(c) ? (fields[c] as CanonicalNumber).digits : null,
      for (final c in bools)
        fields.containsKey(c)
            ? ((fields[c] as CanonicalBool).value ? 1 : 0)
            : null,
      if (review) fields.containsKey('conflicts') ? 1 : 0,
    ];
    _db.execute(
      'INSERT INTO package_import_${review ? 'review' : 'receipt'} VALUES(${List.filled(values.length, '?').join(',')})',
      values,
    );
    if (review && fields.containsKey('conflicts')) {
      final conflicts = (fields['conflicts'] as CanonicalArray).items;
      for (var i = 0; i < conflicts.length; i++) {
        _db.execute('INSERT INTO package_import_conflict VALUES(?,?,?,?)', [
          scope.$1.value,
          scope.$2.value,
          i,
          (conflicts[i] as CanonicalString).value,
        ]);
      }
    }
  }

  void _write((OperationId, ProfileId) scope, SavedPackageImport saved) {
    final f = saved.form;
    _db.execute(
      'INSERT INTO package_import_form VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(instance,profile) DO UPDATE SET generation=excluded.generation,operation=excluded.operation,name=excluded.name,mode=excluded.mode,phase=excluded.phase,file_name=excluded.file_name',
      [
        scope.$1.value,
        scope.$2.value,
        saved.generation.toString(),
        f.operation.value,
        f.name,
        f.mode.name,
        f.phase.name,
        f.fileName,
      ],
    );
    for (final table in ['conflict', 'review', 'receipt']) {
      _db.execute(
        'DELETE FROM package_import_$table WHERE instance=? AND profile=?',
        [scope.$1.value, scope.$2.value],
      );
    }
    _writeReport(scope, f.review, true);
    _writeReport(scope, f.receipt, false);
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
      final saved = SavedPackageImport(
        form: form,
        generation: generation + BigInt.one,
      );
      _write(scope, saved);
      _db.execute('COMMIT');
      return saved;
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();
}
