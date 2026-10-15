import 'dart:convert';

import 'package:ub_domain/ub_domain.dart';

import 'candidate_foundation.dart';
import 'candidate_references.dart';
import 'journal.dart';
import 'projections.dart';
import 'revision_input.dart';

/// Internal disposable-index recovery. Full startup must also verify canonical
/// content, workflow evidence and initialization history before calling this.
final class ProjectionRecovery {
  ProjectionRecovery(this.journal);
  final SqliteJournal journal;

  void rebuild({
    void Function()? afterProjection,
    void Function()? beforeCommit,
  }) {
    final database = journal.database;
    if (!database.autocommit) {
      throw StateError('Projection rebuild owns its transaction');
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      final next = database
          .select('SELECT generation+1 AS next FROM projection_state')
          .single['next'];
      if (next is! int || next <= 0) {
        throw const FormatException('Invalid projection generation');
      }
      final rows = database.select(
        'SELECT id FROM record_versions WHERE universe_id=? ORDER BY id',
        [journal.universe.value],
      );
      if (rows.length > maxVersions) {
        throw const FormatException('Projection rebuild budget exceeded');
      }
      final projections = RecordProjections(database);
      for (final record in journal.loadMany(
        rows.map((row) => RecordVersionId.parse(row['id'] as String)),
      )) {
        projections.project(next, record);
        afterProjection?.call();
      }
      final heads = database.select(
        'SELECT id,head_commit FROM continuities WHERE universe_id=? ORDER BY id',
        [journal.universe.value],
      );
      final verified = <String>{};
      for (final head in heads) {
        final continuity = ContinuityId.parse(head['id'] as String);
        final revision = RevisionId.parse(head['head_commit'] as String);
        final membership = journal.snapshot(continuity, revision);
        final digest = canonicalDigest(
          CanonicalObject([
            for (final entry in membership.entries)
              MapEntry(entry.key.value, CanonicalString(entry.value.value)),
          ]),
        );
        if (verified.add(digest)) {
          CandidateFoundation(journal).validate(membership);
          CandidateReferences(journal).validate(membership);
        }
        journal.setHeadProjection(continuity, revision, membership);
      }
      database.execute('UPDATE projection_state SET generation=?', [next]);
      for (final table in [
        'reference_index',
        'typed_projection',
        'world_projection',
        'narrative_projection',
        'search_index',
      ]) {
        database.execute('DELETE FROM $table WHERE generation!=?', [next]);
      }
      beforeCommit?.call();
      database.execute('COMMIT');
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Literal phrase search intersects the selected immutable membership. FTS
  /// matches from later revisions and other branches never leak into results.
  List<StoredVersion> search(
    ContinuityId continuity,
    RevisionId revision,
    String query,
  ) {
    if (utf8.encode(query).length > 1024) {
      throw const FormatException('Search too long');
    }
    final membership = journal.snapshot(continuity, revision);
    final ids = membership.keys.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final Set<String>? matches = query.isEmpty
        ? null
        : journal.database
              .select(
                'SELECT version_id FROM search_index WHERE search_index MATCH ? AND generation=(SELECT generation FROM projection_state)',
                ['"${query.replaceAll('"', '""')}"'],
              )
              .map((r) => r['version_id'] as String)
              .toSet();
    return List.unmodifiable([
      for (final id in ids)
        if (matches == null || matches.contains(membership[id]!.value))
          journal.load(membership[id]!),
    ]);
  }
}
