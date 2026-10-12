import 'package:ub_domain/ub_domain.dart';

import 'journal.dart';
import 'candidate_reference_policy.dart';
import 'references.dart';
import 'revision_input.dart';

/// Reference portion of candidate admission. Foundation/value/ancestry gates
/// remain separate required kernel work. Selected world names use the pinned
/// shared selector policy; durable reservations are checked during append.
final class CandidateReferences {
  CandidateReferences(this.journal);
  final SqliteJournal journal;

  void validate(Membership membership) {
    final records = [
      for (final version in membership.values) journal.load(version),
    ];
    validateCandidateReferenceRecords(
      universe: journal.universe,
      records: records,
      membership: membership,
      load: journal.load,
      binding: _binding,
    );
  }

  Set<RecordId> dependencies(StoredVersion record) =>
      recordDependencies(record);

  void _binding(ContinuityId continuity, RevisionId revision) {
    final rows = journal.database.select(
      'SELECT EXISTS(SELECT 1 FROM commits WHERE universe_id=? AND continuity_id=? AND id=?) AS present',
      [journal.universe.value, continuity.value, revision.value],
    );
    if (rows.single['present'] != 1) {
      throw const FormatException(
        'Work binding must name an existing revision in its continuity',
      );
    }
  }
}
