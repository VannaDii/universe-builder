import 'package:ub_domain/ub_domain.dart';

import 'references.dart';
import 'revision_input.dart';
import 'world_names.dart';

Iterable<(ContinuityId, RevisionId)> candidateWorkBindings(
  StoredVersion record,
) sync* {
  if (record.identity.recordKind != RecordKind.workVersion) return;
  switch (WorkVersionRecord.fromWire(record.payload).binding) {
    case BoundWork(:final continuity, :final revision):
      yield (continuity, revision);
    case SegmentedWork(:final segments):
      for (final segment in segments) {
        yield (segment.continuity, segment.revision);
      }
    case UnboundWork():
      break;
  }
}

VersionRef? candidateEditionReference(StoredVersion record) =>
    switch (record.identity.recordKind) {
      RecordKind.sceneRef => SceneRecord.fromWire(record.payload).workVersion,
      RecordKind.passageRef => PassageRecord.fromWire(
        record.payload,
      ).workVersion,
      _ => null,
    };

/// Shared reference policy. Native SQLite supplies direct pinned lookups;
/// asynchronous stores load those same immutable dependencies before calling.
void validateCandidateReferenceRecords({
  required UniverseId universe,
  required List<StoredVersion> records,
  required Map<RecordId, RecordVersionId> membership,
  required StoredVersion Function(RecordVersionId) load,
  required void Function(ContinuityId, RevisionId) binding,
}) {
  WorldNames.validateRecords(records);
  final kinds = {
    for (final record in records)
      record.identity.recordId: record.identity.recordKind,
  };
  for (final record in records) {
    for (final (continuity, revision) in candidateWorkBindings(record)) {
      binding(continuity, revision);
    }
    final edition = candidateEditionReference(record);
    if (edition != null &&
        load(edition.version).identity.recordKind != RecordKind.workVersion) {
      throw const FormatException(
        'Editorial edition reference must pin a work version',
      );
    }
    final refs = ReferenceScan.collect(record.payload, universe);
    for (final dependency in refs.records) {
      if (dependency.version != null) {
        if (load(dependency.version!).identity.recordId != dependency.record) {
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
