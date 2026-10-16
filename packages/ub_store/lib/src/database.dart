import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'schema.g.dart';

const maxPackageBytes = 8 * 1024 * 1024 * 1024;

/// Internal connection policy, matching the current native package rules.
/// Package ownership and authorization belong to the kernel/service boundary.
final class SqliteDatabase {
  static Database open(String path, {bool existing = false}) {
    if (!existing) File(path).parent.createSync(recursive: true);
    final db = sqlite3.open(
      path,
      mode: existing ? OpenMode.readWrite : OpenMode.readWriteCreate,
    );
    try {
      final populated =
          db
              .select(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%') AS populated",
              )
              .single['populated'] ==
          1;
      // Inspect before journal-mode changes. Incompatible existing packages
      // are refused without modifying their contents.
      if (populated) _checkSchema(db);
      _policy(db);
      db.execute('PRAGMA journal_mode=WAL');
      if (!populated) {
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(sqliteSchema);
          db.execute('COMMIT');
        } catch (_) {
          if (!db.autocommit) db.execute('ROLLBACK');
          rethrow;
        }
      }
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static void _checkSchema(Database db) {
    final columns = db
        .select('PRAGMA table_info(record_versions)')
        .map((row) => row['name'])
        .toList();
    if (columns.join(',') !=
        'universe_id,id,record_id,kind,payload_row,digest') {
      throw const FormatException(
        'Package schema is incompatible with the current v0 format',
      );
    }
    final workflow = db
        .select('PRAGMA table_info(workflow_entries)')
        .map((row) => row['name'])
        .toList();
    if (workflow.contains('payload') || !workflow.contains('StoredProposal')) {
      throw const FormatException(
        'Package schema is incompatible with the current v0 format',
      );
    }
    final boundary = db
        .select(
          "SELECT count(*) AS n FROM sqlite_master WHERE name IN ('historical_workflow','historical_receipt','active_workflow_index')",
        )
        .single['n'];
    if (boundary != 3) {
      throw const FormatException(
        'Package schema is incompatible with the current v0 format',
      );
    }
  }

  static void _policy(Database db) {
    if (sqlite3.version.versionNumber < 3051003) {
      throw StateError('SQLite WAL patch baseline not met');
    }
    db.execute('PRAGMA busy_timeout=2000');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA synchronous=FULL');
    final pageSize = db.select('PRAGMA page_size').single.values.single as int;
    db.execute('PRAGMA max_page_count=${maxPackageBytes ~/ pageSize}');
    db.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS temp.fts_probe USING fts5(text)',
    );
    db.execute('DROP TABLE temp.fts_probe');
  }
}
