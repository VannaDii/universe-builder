import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _baseColumns =
    'instance,profile,generation,name,calendar,date,time,offset,calendarName,initialTick,tickLabel,ticksPerMonth,creationPending';
const _columns = '$_baseColumns,realWorld';

/// Private, instance/profile-scoped creation input; never creates a universe.
final class UniverseCreationFormRecoveryStore {
  UniverseCreationFormRecoveryStore._(this._db);
  final Database _db;

  static UniverseCreationFormRecoveryStore open(String path) {
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
CREATE TABLE universe_creation_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, generation TEXT NOT NULL,
 "name" TEXT NOT NULL,
 "calendar" TEXT NOT NULL,
 "date" TEXT NOT NULL,
 "time" TEXT NOT NULL,
 "offset" TEXT NOT NULL,
 "calendarName" TEXT NOT NULL,
 "initialTick" TEXT NOT NULL,
 "tickLabel" TEXT NOT NULL,
 "ticksPerMonth" TEXT NOT NULL,
 "creationPending" INTEGER NOT NULL CHECK("creationPending" IN (0,1)),
 "realWorld" INTEGER NOT NULL CHECK("realWorld" IN (0,1)),
 PRIMARY KEY(instance,profile)
) STRICT;
PRAGMA user_version=2;
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
      return UniverseCreationFormRecoveryStore._(db);
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
    final version = db.select('PRAGMA user_version').single.values.single;
    if (version != 2 ||
        tables.length != 1 ||
        tables.single['name'] != 'universe_creation_form' ||
        db
                .select('PRAGMA table_info(universe_creation_form)')
                .map((r) => r['name'])
                .join(',') !=
            _columns) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return true;
  }

  SavedUniverseCreationForm? load((OperationId, ProfileId) scope) {
    final rows = _db.select(
      'SELECT *, CAST("name" AS BLOB) AS exact_name, CAST("date" AS BLOB) AS exact_date, CAST("time" AS BLOB) AS exact_time, CAST("offset" AS BLOB) AS exact_offset, CAST("calendarName" AS BLOB) AS exact_calendarName, CAST("initialTick" AS BLOB) AS exact_initialTick, CAST("tickLabel" AS BLOB) AS exact_tickLabel, CAST("ticksPerMonth" AS BLOB) AS exact_ticksPerMonth FROM universe_creation_form WHERE instance=? AND profile=?',
      [scope.$1.value, scope.$2.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedUniverseCreationForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UniverseCreationForm(
        name: decodeExactUtf8(row['exact_name'] as List<int>),
        calendar: CreationCalendar.values.byName(row['calendar'] as String),
        date: decodeExactUtf8(row['exact_date'] as List<int>),
        time: decodeExactUtf8(row['exact_time'] as List<int>),
        offset: decodeExactUtf8(row['exact_offset'] as List<int>),
        calendarName: decodeExactUtf8(row['exact_calendarName'] as List<int>),
        initialTick: decodeExactUtf8(row['exact_initialTick'] as List<int>),
        tickLabel: decodeExactUtf8(row['exact_tickLabel'] as List<int>),
        ticksPerMonth: decodeExactUtf8(row['exact_ticksPerMonth'] as List<int>),
        creationPending: row['creationPending'] == 1,
        realWorld: row['realWorld'] == 1,
      ),
    );
  }

  SavedUniverseCreationForm save(
    (OperationId, ProfileId) scope,
    UniverseCreationForm form,
    BigInt expectedGeneration,
  ) {
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    for (final text in [
      form.name,
      form.date,
      form.time,
      form.offset,
      form.calendarName,
      form.initialTick,
      form.tickLabel,
      form.ticksPerMonth,
    ]) {
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
      final saved = SavedUniverseCreationForm(
        form: form,
        generation: generation + BigInt.one,
      );
      _db.execute(
        'INSERT OR REPLACE INTO universe_creation_form($_columns) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          scope.$1.value,
          scope.$2.value,
          saved.generation.toString(),
          form.name,
          form.calendar.name,
          form.date,
          form.time,
          form.offset,
          form.calendarName,
          form.initialTick,
          form.tickLabel,
          form.ticksPerMonth,
          form.creationPending ? 1 : 0,
          form.realWorld ? 1 : 0,
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
