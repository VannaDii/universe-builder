import 'package:sqlite3/sqlite3.dart';

/// Copy a protected snapshot into a freshly created trusted schema. Input SQL
/// is compared only; it is never installed or executed as application schema.
void copyRestoreRows(String source, Database target) {
  if (!target.autocommit ||
      target.select('SELECT count(*) AS n FROM universes').single['n'] != 0) {
    throw StateError('Restore requires a new uninitialized target');
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
      throw const FormatException('Untrusted or incompatible restore schema');
    }
    final checks = input.select('PRAGMA integrity_check');
    if (checks.length != 1 || checks.single.values.single != 'ok') {
      throw const FormatException('Input SQLite integrity failure');
    }
    String quote(String name) => '"${name.replaceAll('"', '""')}"';
    target.execute('BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON;');
    try {
      for (final table in target.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search_index%' ORDER BY name",
      )) {
        final name = table['name'] as String;
        if (name == 'r_archive_manifest') continue;
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
      target.execute(
        'INSERT OR IGNORE INTO historical_workflow SELECT key FROM workflow_entries',
      );
      target.execute(
        'INSERT OR IGNORE INTO historical_receipt SELECT universe_id,principal,operation_kind,idempotency_key FROM operation_receipts',
      );
      target.execute('COMMIT');
    } on Object {
      if (!target.autocommit) target.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    input.close();
  }
}
