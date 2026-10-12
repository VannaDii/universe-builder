import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'definition_index_rows.dart';
import 'journal.dart' show Membership;
import 'postgres_journal.dart';
import 'postgres_values.dart';
import 'revision_input.dart';

/// Semantic projections within the caller's publication transaction. Indexing
/// does not authorize publication or replace initialization/admission checks.
final class PostgresDefinitionIndex {
  PostgresDefinitionIndex(this._session, this.universe);
  final TxSession _session;
  final UniverseId universe;

  Future<void> index(StoredVersion record, Membership membership) async {
    if (record.identity.universeId != universe) {
      throw const FormatException('Definition index universe mismatch');
    }
    final journal = PostgresJournal(_session, universe);
    await journal.lockUniverse();
    final loaded = <RecordVersionId, StoredVersion>{};
    if (record.identity.recordKind == RecordKind.assertion) {
      final assertion = AssertionRecord.fromWire(record.payload);
      if (assertion.attributeMode != AttributeMode.instance) {
        final version = membership[assertion.proposition.record];
        if (version == null) {
          throw const FormatException('Missing definition proposition');
        }
        loaded[version] = await journal.load(version);
      }
    }
    final schema = postgresUniverseSchema(universe);
    for (final (table, values) in definitionIndexRows(
      record,
      membership,
      (version) => loaded[version]!,
    )) {
      if (table == 'type_definition') {
        values[3] = postgresAuthoredText(values[3] as String);
      }
      final placeholders = [for (var i = 1; i <= values.length; i++) '\$$i']
          .join(',');
      await _session.execute(
        'INSERT INTO $schema.$table VALUES($placeholders)',
        parameters: values,
      );
    }
  }
}
