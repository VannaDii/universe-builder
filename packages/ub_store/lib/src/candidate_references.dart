import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'journal.dart';
import 'references.dart';
import 'revision_input.dart';
import 'world_names.dart';

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
    WorldNames.validateRecords(records);
    final kinds = {
      for (final record in records)
        record.identity.recordId: record.identity.recordKind,
    };
    for (final record in records) {
      final fields = objectFields(record.payload);
      if (record.identity.recordKind == RecordKind.workVersion) {
        final binding = objectFields(fields['binding']!);
        final kind = (binding['kind'] as CanonicalString).value;
        if (kind == 'bound') {
          _binding(binding);
        } else if (kind == 'segments') {
          for (final segment in (binding['segments'] as CanonicalArray).items) {
            _binding(objectFields(segment));
          }
        }
      }
      if ({
        RecordKind.sceneRef,
        RecordKind.passageRef,
      }.contains(record.identity.recordKind)) {
        final edition = objectFields(fields['workVersion']!);
        final version = RecordVersionId.parse(
          (edition['version'] as CanonicalString).value,
        );
        if (journal.load(version).identity.recordKind !=
            RecordKind.workVersion) {
          throw const FormatException(
            'Editorial edition reference must pin a work version',
          );
        }
      }
      final refs = ReferenceScan.collect(record.payload, journal.universe);
      for (final dependency in refs.records) {
        if (dependency.version != null) {
          final target = journal.load(dependency.version!);
          if (target.identity.recordId != dependency.record) {
            throw const FormatException('Version reference identity mismatch');
          }
        } else if (!membership.containsKey(dependency.record)) {
          throw const FormatException('Missing current record dependency');
        }
      }
      for (final dependency in refs.typed) {
        if (kinds[dependency.record] != dependency.kind) {
          throw const FormatException('Typed definition has wrong kind');
        }
      }
      for (final world in refs.worlds) {
        if (kinds[worldRecord(world)] != RecordKind.world) {
          throw const FormatException('World reference has wrong kind');
        }
      }
    }
  }

  Set<RecordId> dependencies(StoredVersion record) {
    final refs = ReferenceScan.collect(
      record.payload,
      record.identity.universeId,
    );
    return {
      for (final reference in refs.records) reference.record,
      for (final reference in refs.typed) reference.record,
      for (final world in refs.worlds) worldRecord(world),
    };
  }

  void _binding(Map<String, CanonicalValue> binding) {
    final continuity = ContinuityId.parse(
      (binding['continuity'] as CanonicalString).value,
    );
    final revision = RevisionId.parse(
      (binding['revision'] as CanonicalString).value,
    );
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
