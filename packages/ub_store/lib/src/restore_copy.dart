import 'package:sqlite3/sqlite3.dart';

/// Copy a protected snapshot into a freshly created trusted schema. Input SQL
/// is compared only; it is never installed or executed as application schema.
void copyRestoreRows(String source, Database target) =>
    copyTrustedPackageRows(source, target, historicalEvidence: true);

/// Shared physical row transfer into a fresh normative package or archive.
/// Archive targets install the normative archive schema before this call.
void copyTrustedPackageRows(
  String source,
  Database target, {
  bool historicalEvidence = false,
  bool archive = false,
}) {
  if (!target.autocommit ||
      target.select('SELECT count(*) AS n FROM universes').single['n'] != 0) {
    throw StateError('Transfer requires a new uninitialized target');
  }
  final input = sqlite3.open(source, mode: OpenMode.readOnly);
  try {
    input.execute('PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; BEGIN;');
    List<(String, String, String, String)> schema(Database db) => [
      for (final row in db.select(
        "SELECT type,name,tbl_name,coalesce(sql,'') AS sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
      ))
        (
          row['type'] as String,
          row['name'] as String,
          row['tbl_name'] as String,
          row['sql'] as String,
        ),
    ];
    final from = schema(input), to = schema(target);
    if (from.length != to.length ||
        Iterable<int>.generate(from.length).any((i) => from[i] != to[i])) {
      throw const FormatException(
        'Untrusted or incompatible package/archive schema',
      );
    }
    final checks = input.select('PRAGMA integrity_check');
    if (checks.length != 1 || checks.single.values.single != 'ok') {
      throw const FormatException('Input SQLite integrity failure');
    }
    copyTrustedRows(
      input,
      target,
      historicalEvidence: historicalEvidence,
      archive: archive,
    );
  } finally {
    input.close();
  }
}

/// Transfer from an already verified, owned trusted schema. Only the target's
/// declared tables/columns are selected; archive metadata is omitted for packages.
void copyTrustedRows(
  Database input,
  Database target, {
  bool historicalEvidence = false,
  bool archive = false,
}) {
  if (!target.autocommit ||
      target.select('SELECT count(*) AS n FROM universes').single['n'] != 0 ||
      target.select('PRAGMA foreign_keys').single.values.single != 1) {
    throw StateError('Transfer requires a new uninitialized target');
  }
  String quote(String name) => '"${name.replaceAll('"', '""')}"';
  // Table order is not dependency order (recursive bodies also form cycles).
  // Deferred parent inserts repeatedly scan unindexed child references, making
  // large restores quadratic. This target is private and empty: copy its rows
  // atomically, then check every foreign key once before accepting the copy.
  target.execute('PRAGMA foreign_keys=OFF');
  try {
    target.execute('BEGIN IMMEDIATE');
    for (final table in target.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search_index%' ORDER BY name",
    )) {
      final name = table['name'] as String;
      if (!archive && name == 'r_archive_manifest') continue;
      final columns = target
          .select('PRAGMA table_info(${quote(name)})')
          .map((c) => c['name'] as String)
          .toList();
      if (name == 'projection_state') {
        target.execute('DELETE FROM projection_state');
      }
      final selected = columns.map(quote).join(',');
      final read = input.prepare('SELECT $selected FROM ${quote(name)}');
      try {
        final write = target.prepare(
          'INSERT INTO ${quote(name)} ($selected) VALUES (${List.filled(columns.length, '?').join(',')})',
        );
        try {
          final cursor = read.selectCursor();
          while (cursor.moveNext()) {
            write.execute([
              for (final column in columns) cursor.current[column],
            ]);
          }
        } finally {
          write.close();
        }
      } finally {
        read.close();
      }
    }
    // Preserve exact evidence while preventing imported authority and receipts
    // from satisfying an active approval, context or publication retry.
    if (historicalEvidence) {
      target.execute(
        'INSERT OR IGNORE INTO historical_workflow SELECT key FROM workflow_entries',
      );
      target.execute(
        'INSERT OR IGNORE INTO historical_receipt SELECT universe_id,principal,operation_kind,idempotency_key FROM operation_receipts',
      );
    }
    if (target
        .select('SELECT 1 FROM pragma_foreign_key_check LIMIT 1')
        .isNotEmpty) {
      throw SqliteException(
        extendedResultCode: SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY,
        message: 'FOREIGN KEY constraint failed',
        operation: 'checking transferred rows before commit',
      );
    }
    target.execute('COMMIT');
  } on Object {
    if (!target.autocommit) target.execute('ROLLBACK');
    rethrow;
  } finally {
    target.execute('PRAGMA foreign_keys=ON');
    if (target.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw StateError('Transfer could not restore foreign key enforcement');
    }
  }
}
