import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'journal.dart' show maxVersions;
import 'postgres_candidate_admission.dart';
import 'postgres_journal.dart';
import 'postgres_projections.dart';
import 'postgres_values.dart';
import 'revision_input.dart';

/// Internal disposable-index recovery in a caller-owned transaction. Startup
/// must also verify canonical bodies, workflow and initialization history.
final class PostgresProjectionRecovery {
  PostgresProjectionRecovery(this._session, this.universe)
    : _schema = postgresUniverseSchema(universe),
      _journal = PostgresJournal(_session, universe);
  final TxSession _session;
  final UniverseId universe;
  final String _schema;
  final PostgresJournal _journal;

  Future<void> rebuild({
    void Function()? afterProjection,
    void Function()? beforeCompletion,
  }) async {
    await _journal.lockUniverse();
    final next = (await _session.execute(
      'SELECT generation+1 FROM $_schema.projection_state',
    )).single.single;
    if (next is! int || next <= 0) {
      throw const FormatException('Invalid projection generation');
    }
    final rows = await _session.execute(
      'SELECT id FROM $_schema.record_versions WHERE universe_id=\$1 ORDER BY id',
      parameters: [universe.value],
    );
    if (rows.length > maxVersions) {
      throw const FormatException('Projection rebuild budget exceeded');
    }
    final projections = PostgresRecordProjections(_session, universe);
    for (final row in rows) {
      await projections.project(
        next,
        await _journal.load(RecordVersionId.parse(row[0] as String)),
      );
      afterProjection?.call();
    }
    final heads = await _session.execute(
      'SELECT id,head_commit FROM $_schema.continuities WHERE universe_id=\$1 ORDER BY id',
      parameters: [universe.value],
    );
    final verified = <String>{};
    for (final head in heads) {
      final continuity = ContinuityId.parse(head[0] as String);
      final revision = RevisionId.parse(head[1] as String);
      final membership = await _journal.snapshot(continuity, revision);
      final digest = canonicalDigest(
        CanonicalObject([
          for (final entry in membership.entries)
            MapEntry(entry.key.value, CanonicalString(entry.value.value)),
        ]),
      );
      if (verified.add(digest)) {
        await PostgresCandidateAdmission(_journal).validate(membership);
      }
      await _journal.setHeadProjection(continuity, revision, membership);
    }
    await _session.execute(
      'UPDATE $_schema.projection_state SET generation=\$1',
      parameters: [next],
    );
    for (final table in [
      'reference_index',
      'typed_projection',
      'world_projection',
      'narrative_projection',
      'search_index',
    ]) {
      await _session.execute(
        'DELETE FROM $_schema.$table WHERE generation!=\$1',
        parameters: [next],
      );
    }
    beforeCompletion?.call();
  }

  /// Internal literal-phrase candidates, intersected with immutable membership
  /// before loading/disclosure. The service still applies grants, perspective,
  /// pagination and coverage. Search does not drive factual validation.
  Future<List<StoredVersion>> search(
    ContinuityId continuity,
    RevisionId revision,
    String query,
  ) async {
    if (postgresAuthoredText(query).length > 1024) {
      throw const FormatException('Search too long');
    }
    // Serialize against projection generation switches. The immutable revision
    // pin does not by itself make a multi-query disposable-index read consistent.
    await _journal.lockUniverse();
    final membership = await _journal.snapshot(continuity, revision);
    final ids = membership.keys.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final Set<String>? matches;
    if (query.isEmpty) {
      matches = null;
    } else if (membership.isEmpty) {
      matches = const {};
    } else {
      matches = {
        for (final row in await _session.execute(
          "SELECT version_id FROM $_schema.search_index WHERE generation=(SELECT generation FROM $_schema.projection_state) AND version_id=ANY(\$1::text[]) AND document OPERATOR(pg_catalog.@@) pg_catalog.phraseto_tsquery('pg_catalog.simple',\$2)",
          parameters: [
            membership.values.map((v) => v.value).toList(),
            postgresSearchDocument(query),
          ],
        ))
          row[0] as String,
      };
    }
    return List.unmodifiable([
      for (final id in ids)
        if (matches == null || matches.contains(membership[id]!.value))
          await _journal.load(membership[id]!),
    ]);
  }
}
