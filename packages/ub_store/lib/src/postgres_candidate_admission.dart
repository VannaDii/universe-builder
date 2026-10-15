import 'package:ub_domain/ub_domain.dart';

import 'candidate_foundation.dart';
import 'candidate_reference_policy.dart';
import 'journal.dart' show Membership;
import 'postgres_journal.dart';
import 'references.dart';

/// Foundation/reference portion of PostgreSQL candidate admission. Authorization,
/// exact approval, initialization, definition indexes and projections remain
/// separate required publication work in the caller's owned transaction.
final class PostgresCandidateAdmission {
  PostgresCandidateAdmission(this._journal);
  final PostgresJournal _journal;

  Future<void> validate(Membership membership) async {
    final records = await _journal.loadMany(membership.values).toList();
    validateCandidateFoundationRecords(records);
    final pinned = {for (final record in records) record.versionId: record};
    final bindings = <(ContinuityId, RevisionId), bool>{};
    for (final record in records) {
      final refs = ReferenceScan.collect(record.payload, _journal.universe);
      final versions = {
        for (final ref in refs.records)
          if (ref.version != null) ref.version!,
        if (candidateEditionReference(record) case final edition?)
          edition.version,
      };
      for (final version in versions) {
        if (!pinned.containsKey(version)) {
          pinned[version] = await _journal.load(version);
        }
      }
      for (final binding in candidateWorkBindings(record)) {
        if (!bindings.containsKey(binding)) {
          bindings[binding] = await _journal.revisionExists(
            binding.$1,
            binding.$2,
          );
        }
      }
    }
    validateCandidateReferenceRecords(
      universe: _journal.universe,
      records: records,
      membership: membership,
      load: (id) =>
          pinned[id] ??
          (throw const FormatException('Missing pinned candidate dependency')),
      binding: (continuity, revision) {
        if (bindings[(continuity, revision)] != true) {
          throw const FormatException(
            'Work binding must name an existing revision in its continuity',
          );
        }
      },
    );
  }
}
