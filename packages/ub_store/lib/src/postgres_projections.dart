import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'postgres_journal.dart';
import 'postgres_values.dart';
import 'projection_rows.dart';
import 'revision_input.dart';

/// The text parser receives NUL as a token separator. Exact authored bytes are
/// retained separately, so this disposable projection never changes canon.
String postgresSearchDocument(String text) => text.replaceAll('\u0000', ' ');

/// Disposable projections within the caller-owned publication/rebuild
/// transaction. Rights and exact approval are enforced by the complete kernel.
final class PostgresRecordProjections {
  PostgresRecordProjections(this._session, this.universe);
  final TxSession _session;
  final UniverseId universe;

  Future<void> project(int generation, StoredVersion version) async {
    if (version.identity.universeId != universe) {
      throw const FormatException('Projection universe mismatch');
    }
    await PostgresJournal(_session, universe).lockUniverse();
    final schema = postgresUniverseSchema(universe);
    for (final (table, values) in recordProjectionRows(generation, version)) {
      final byteColumns = switch (table) {
        'reference_index' => [4],
        'typed_projection' => [2, 3],
        'narrative_projection' => [3],
        'search_index' => [2],
        _ => const <int>[],
      };
      final searchText = table == 'search_index' ? values[2] as String : null;
      for (final index in byteColumns) {
        values[index] = postgresAuthoredText(values[index] as String);
      }
      if (searchText != null) {
        await _session.execute(
          "INSERT INTO $schema.search_index VALUES(\$1,\$2,\$3,pg_catalog.to_tsvector('pg_catalog.simple',\$4))",
          parameters: [...values, postgresSearchDocument(searchText)],
        );
      } else {
        final placeholders = [for (var i = 1; i <= values.length; i++) '\$$i']
            .join(',');
        await _session.execute(
          'INSERT INTO $schema.$table VALUES($placeholders)',
          parameters: values,
        );
      }
    }
  }
}
