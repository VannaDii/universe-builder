import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'archive_checksum.dart';
import 'journal.dart';
import 'owned_database.dart';
import 'postgres_relational.dart';
import 'postgres_values.dart';
import 'postgres_workflow_storage.dart';
import 'relational.dart' show quoteIdentifier;
import 'workflow_storage.dart';

/// Translate a trusted, staged SQLite package into a fresh normative namespace.
/// Archive SQL and private row pointers are never installed in PostgreSQL.
final class PostgresLogicalImport {
  PostgresLogicalImport(this._session, this.universe);
  final TxSession _session;
  final UniverseId universe;

  Future<void> copy(OwnedSqliteDatabase package) async {
    if (package.universeId != universe) {
      throw const FormatException('Staged universe mismatch');
    }
    final schema = postgresUniverseSchema(universe);
    final db = package.database;
    var count = 0;
    void budget() {
      if (++count > maxArchiveRows) {
        throw const FormatException('Archive row budget exceeded');
      }
    }

    Future<void> copyTable(String table) async {
      // Column names and types come from the freshly provisioned trusted schema.
      final columns = await _session.execute(
        'SELECT a.attname, t.typname FROM pg_catalog.pg_attribute a '
        'JOIN pg_catalog.pg_type t ON t.oid=a.atttypid '
        'WHERE a.attrelid=\$1::regclass AND a.attnum>0 AND NOT a.attisdropped '
        'ORDER BY a.attnum',
        parameters: ['$schema.$table'],
      );
      final names = [for (final column in columns) column[0] as String];
      final selected = names.map(quoteIdentifier).join(',');
      final statement = db.prepare(
        'SELECT $selected FROM ${quoteIdentifier(table)}',
      );
      try {
        final cursor = statement.selectCursor();
        while (cursor.moveNext()) {
          final row = cursor.current;
          budget();
          await _session.execute(
            'INSERT INTO $schema.${quoteIdentifier(table)} ($selected) VALUES '
            '(${List.generate(names.length, (i) => '\$${i + 1}').join(',')})',
            parameters: [
              for (var i = 0; i < names.length; i++)
                if (row[names[i]] is String && columns[i][1] == 'bytea')
                  postgresAuthoredText(row[names[i]] as String)
                else
                  row[names[i]],
            ],
          );
        }
      } finally {
        statement.close();
      }
    }

    await copyTable('universes');
    await copyTable('record_identities');
    final journal = SqliteJournal(db, universe);
    final codec = PostgresRelationalCodec(_session, universe);
    final versions = db.prepare('SELECT id FROM record_versions');
    try {
      Iterable<RecordVersionId> ids() sync* {
        final cursor = versions.selectCursor();
        while (cursor.moveNext()) {
          budget();
          yield RecordVersionId.parse(cursor.current['id'] as String);
        }
      }

      for (final record in journal.loadMany(ids())) {
        if (record.toCanonical().toBytes().length > 1048576) {
          throw const FormatException('Archive record too large');
        }
        final payload = await codec.put('Payload', record.payload);
        await _session.execute(
          'INSERT INTO $schema.record_versions VALUES(\$1,\$2,\$3,\$4,\$5,\$6)',
          parameters: [
            universe.value,
            record.versionId.value,
            record.identity.recordId.value,
            record.identity.recordKind.wireName,
            payload,
            record.digest,
          ],
        );
      }
    } finally {
      versions.close();
    }
    for (final table in [
      'import_record_digest',
      'continuities',
      'commits',
      'commit_changes',
      'world_name_reservations',
      'type_definition',
      'type_world',
      'instance_classification',
      'classification_evidence',
      'definition_attribute',
      'initialization_receipt',
      'operation_receipts',
      'historical_receipt',
    ]) {
      await copyTable(table);
    }
    final workflow = WorkflowStorage(db);
    final output = PostgresWorkflowStorage(_session, universe);
    final keys = db.prepare('SELECT key FROM workflow_index');
    try {
      final cursor = keys.selectCursor();
      while (cursor.moveNext()) {
        final row = cursor.current;
        budget();
        final key = row['key'] as String;
        final value = workflow.evidence(key);
        if (value == null) {
          throw const FormatException('Missing workflow evidence');
        }
        await output.put(key, value);
      }
    } finally {
      keys.close();
    }
    await copyTable('historical_workflow');
    await copyTable('import_workflow_digest');
  }
}
