import 'dart:typed_data';

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

  Future<void> project(int generation, StoredVersion version) =>
      projectMany(generation, [version]);

  Future<void> projectMany(int generation, List<StoredVersion> versions) async {
    if (versions.length > 50) {
      throw RangeError('Projection batch exceeds 50 records');
    }
    for (final version in versions) {
      if (version.identity.universeId != universe) {
        throw const FormatException('Projection universe mismatch');
      }
    }
    await PostgresJournal(_session, universe).lockUniverse();
    final schema = postgresUniverseSchema(universe);
    final rows = <String, List<List<Object?>>>{};
    var bufferedRows = 0, bufferedBytes = 0;
    Future<void> flush() async {
      for (final entry in rows.entries) {
        final table = entry.key, batch = entry.value;
        final limit = (60000 ~/ batch.first.length).clamp(1, 64);
        for (var offset = 0; offset < batch.length; offset += limit) {
          final parameters = <Object?>[];
          final tuples = <String>[];
          final end = (offset + limit).clamp(0, batch.length);
          for (final row in batch.getRange(offset, end)) {
            final placeholders = <String>[];
            for (var i = 0; i < row.length; i++) {
              parameters.add(row[i]);
              final parameter = '\$${parameters.length}';
              placeholders.add(
                table == 'search_index' && i == row.length - 1
                    ? "pg_catalog.to_tsvector('pg_catalog.simple',$parameter)"
                    : parameter,
              );
            }
            tuples.add('(${placeholders.join(',')})');
          }
          await _session.execute(
            'INSERT INTO $schema.$table VALUES ${tuples.join(',')}',
            parameters: parameters,
          );
        }
      }
      rows.clear();
      bufferedRows = 0;
      bufferedBytes = 0;
    }

    for (final version in versions) {
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
          values.add(postgresSearchDocument(searchText));
        }
        final bytes = values.fold<int>(
          0,
          (total, value) =>
              total +
              switch (value) {
                Uint8List value => value.length,
                String value => value.length * 3,
                _ => 8,
              },
        );
        if (bufferedRows > 0 && bufferedBytes + bytes > 4 * 1024 * 1024) {
          await flush();
        }
        (rows[table] ??= []).add(values);
        bufferedRows++;
        bufferedBytes += bytes;
        if (bufferedRows >= 256 || bufferedBytes >= 4 * 1024 * 1024) {
          await flush();
        }
      }
    }
    await flush();
  }
}
