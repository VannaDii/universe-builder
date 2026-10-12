import 'definition_index_rows.dart';
import 'journal.dart';
import 'revision_input.dart';

/// Immutable semantic indexes over admitted versions.
final class DefinitionIndex {
  DefinitionIndex(this.journal);
  final SqliteJournal journal;

  void index(StoredVersion record, Membership membership) {
    final database = journal.database;
    if (database.autocommit) {
      throw StateError('Definition indexes require an owned transaction');
    }
    if (record.identity.universeId != journal.universe) {
      throw const FormatException('Definition index universe mismatch');
    }
    for (final (table, values) in definitionIndexRows(
      record,
      membership,
      journal.load,
    )) {
      final placeholders = List.filled(values.length, '?').join(',');
      database.execute('INSERT INTO $table VALUES($placeholders)', values);
    }
  }
}
