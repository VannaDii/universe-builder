import 'package:sqlite3/sqlite3.dart';

import 'projection_rows.dart';
import 'revision_input.dart';

/// Disposable indexes only. Revision history and typed bodies remain authority.
final class RecordProjections {
  RecordProjections(this.database);
  final Database database;

  void project(int generation, StoredVersion version) {
    if (database.autocommit) {
      throw StateError('Projection write requires an owned transaction');
    }
    for (final (table, values) in recordProjectionRows(generation, version)) {
      final placeholders = List.filled(values.length, '?').join(',');
      database.execute('INSERT INTO $table VALUES($placeholders)', values);
    }
  }
}
