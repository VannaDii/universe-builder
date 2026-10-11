import 'package:ub_domain/ub_domain.dart';

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
      switch (record.identity.recordKind) {
        case RecordKind.workVersion:
          final binding = WorkVersionRecord.fromWire(record.payload).binding;
          switch (binding) {
            case BoundWork(:final continuity, :final revision):
              _binding(continuity, revision);
            case SegmentedWork(:final segments):
              for (final segment in segments) {
                _binding(segment.continuity, segment.revision);
              }
            case UnboundWork():
              break;
          }
        case RecordKind.sceneRef:
          _edition(SceneRecord.fromWire(record.payload).workVersion);
        case RecordKind.passageRef:
          _edition(PassageRecord.fromWire(record.payload).workVersion);
        default:
          break;
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

  void _edition(VersionRef edition) {
    if (journal.load(edition.version).identity.recordKind !=
        RecordKind.workVersion) {
      throw const FormatException(
        'Editorial edition reference must pin a work version',
      );
    }
  }

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
