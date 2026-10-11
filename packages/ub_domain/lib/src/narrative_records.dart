part of 'records.dart';

enum WorkKind {
  novel('novel'),
  story('story'),
  seriesChapter('series_chapter'),
  play('play'),
  film('film'),
  other('other');

  const WorkKind(this.wireName);
  final String wireName;
  static WorkKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown work kind'),
  );
}

/// Universe-owned metadata for an external work; this does not store manuscript prose.
final class WorkRecord extends RecordPayload {
  WorkRecord({
    required this.kind,
    required this.title,
    required Map<String, String> labels,
    required Iterable<RecordRef> sourceRefs,
    required Iterable<RecordId> versions,
    required Iterable<WorldAssociation> worldAssociations,
  }) : labels = Map.unmodifiable(labels),
       sourceRefs = List.unmodifiable(sourceRefs),
       versions = List.unmodifiable(versions),
       worldAssociations = List.unmodifiable(worldAssociations);
  final WorkKind kind;
  final String title;
  final Map<String, String> labels;
  final List<RecordRef> sourceRefs;
  final List<RecordId> versions;
  final List<WorldAssociation> worldAssociations;
  factory WorkRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.work, {
      'kind',
      'title',
      'labels',
      'sourceRefs',
      'versions',
      'worldAssociations',
    });
    return WorkRecord(
      kind: WorkKind.fromName(f.string('kind')),
      title: f.string('title'),
      labels: _strings(f, 'labels'),
      sourceRefs: f.array('sourceRefs').map(RecordRef.fromCanonical),
      versions: _ids(f.array('versions')),
      worldAssociations: f
          .array('worldAssociations')
          .map(WorldAssociation.fromWire),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.work;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('title', CanonicalString(title)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry(
      'sourceRefs',
      CanonicalArray(sourceRefs.map((r) => r.toCanonical())),
    ),
    MapEntry('versions', _idArray(versions)),
    MapEntry(
      'worldAssociations',
      CanonicalArray(worldAssociations.map((w) => w.toWire())),
    ),
  ]);
}

/// Several continuities remain explicitly bound per segment, never merged.
sealed class WorkBinding {
  const WorkBinding();
  CanonicalObject toWire();
  static WorkBinding fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'bound':
        f.allow({'kind', 'continuity', 'revision'});
        return BoundWork(
          ContinuityId.parse(f.string('continuity')),
          RevisionId.parse(f.string('revision')),
        );
      case 'unbound':
        f.allow({'kind'});
        return const UnboundWork();
      case 'segments':
        f.allow({'kind', 'segments'});
        return SegmentedWork(f.array('segments').map(WorkSegment.fromWire));
      default:
        throw const FormatException('Unknown work binding');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WorkBinding && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toWire().toText().hashCode;
}

final class BoundWork extends WorkBinding {
  const BoundWork(this.continuity, this.revision);
  final ContinuityId continuity;
  final RevisionId revision;
  @override
  CanonicalObject toWire() => tagged('bound', [
    MapEntry('continuity', CanonicalString(continuity.value)),
    MapEntry('revision', CanonicalString(revision.value)),
  ]);
}

final class UnboundWork extends WorkBinding {
  const UnboundWork();
  @override
  CanonicalObject toWire() => tagged('unbound', []);
}

final class SegmentedWork extends WorkBinding {
  SegmentedWork(Iterable<WorkSegment> segments)
    : segments = List.unmodifiable(segments);
  final List<WorkSegment> segments;
  @override
  CanonicalObject toWire() => tagged('segments', [
    MapEntry('segments', CanonicalArray(segments.map((s) => s.toWire()))),
  ]);
}

final class WorkSegment {
  const WorkSegment({
    required this.segment,
    required this.continuity,
    required this.revision,
  });
  final String segment;
  final ContinuityId continuity;
  final RevisionId revision;
  factory WorkSegment.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'segment', 'continuity', 'revision'});
    return WorkSegment(
      segment: f.string('segment'),
      continuity: ContinuityId.parse(f.string('continuity')),
      revision: RevisionId.parse(f.string('revision')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('segment', CanonicalString(segment)),
    MapEntry('continuity', CanonicalString(continuity.value)),
    MapEntry('revision', CanonicalString(revision.value)),
  ]);
}

final class WorkVersionRecord extends RecordPayload {
  const WorkVersionRecord({
    required this.work,
    required this.versionLabel,
    required this.binding,
  });
  final RecordRef work;
  final String versionLabel;
  final WorkBinding binding;
  factory WorkVersionRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.workVersion, {
      'work',
      'versionLabel',
      'binding',
    });
    return WorkVersionRecord(
      work: RecordRef.fromCanonical(f.require('work')),
      versionLabel: f.string('versionLabel'),
      binding: WorkBinding.fromWire(f.require('binding')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.workVersion;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('work', work.toCanonical()),
    MapEntry('versionLabel', CanonicalString(versionLabel)),
    MapEntry('binding', binding.toWire()),
  ]);
}

/// Reader position, viewpoint and depicted events do not establish occurrences
/// or knowledge. Their source edition remains an exact immutable version pin.
final class SceneRecord extends RecordPayload {
  SceneRecord({
    required this.workVersion,
    required this.sceneId,
    Iterable<RecordRef> disclosedRecords = const [],
    this.viewpoint,
    BigInt? narrativePosition,
    required Iterable<RecordRef> depictedEvents,
    this.narrationFrame,
    required Iterable<WorldAssociation> worldAssociations,
  }) : disclosedRecords = List.unmodifiable(disclosedRecords),
       narrativePosition = narrativePosition == null
           ? null
           : _checkedU64(narrativePosition),
       depictedEvents = List.unmodifiable(depictedEvents),
       worldAssociations = List.unmodifiable(worldAssociations);
  final VersionRef workVersion;
  final String sceneId;
  final List<RecordRef> disclosedRecords, depictedEvents;
  final RecordRef? viewpoint, narrationFrame;
  final BigInt? narrativePosition;
  final List<WorldAssociation> worldAssociations;
  factory SceneRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.sceneRef, {
      'workVersion',
      'sceneId',
      'disclosedRecords',
      'viewpoint',
      'narrativePosition',
      'depictedEvents',
      'narrationFrame',
      'worldAssociations',
    });
    return SceneRecord(
      workVersion: VersionRef.fromCanonical(f.require('workVersion')),
      sceneId: f.string('sceneId'),
      disclosedRecords: _array(
        f,
        'disclosedRecords',
      ).map(RecordRef.fromCanonical),
      viewpoint: _optionalRef(f, 'viewpoint'),
      narrativePosition: _optionalU64(f, 'narrativePosition'),
      depictedEvents: f.array('depictedEvents').map(RecordRef.fromCanonical),
      narrationFrame: _optionalRef(f, 'narrationFrame'),
      worldAssociations: f
          .array('worldAssociations')
          .map(WorldAssociation.fromWire),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.sceneRef;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('workVersion', workVersion.toCanonical()),
    MapEntry('sceneId', CanonicalString(sceneId)),
    if (disclosedRecords.isNotEmpty)
      MapEntry(
        'disclosedRecords',
        CanonicalArray(disclosedRecords.map((r) => r.toCanonical())),
      ),
    MapEntry('viewpoint', _nullableRef(viewpoint)),
    MapEntry('narrativePosition', _nullableU64(narrativePosition)),
    MapEntry(
      'depictedEvents',
      CanonicalArray(depictedEvents.map((r) => r.toCanonical())),
    ),
    MapEntry('narrationFrame', _nullableRef(narrationFrame)),
    MapEntry(
      'worldAssociations',
      CanonicalArray(worldAssociations.map((w) => w.toWire())),
    ),
  ]);
}

final class PassageRecord extends RecordPayload {
  const PassageRecord({
    required this.workVersion,
    required this.passageId,
    this.anchor,
  });
  final VersionRef workVersion;
  final String passageId;
  final RecordRef? anchor;
  factory PassageRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.passageRef, {
      'workVersion',
      'passageId',
      'anchor',
    });
    return PassageRecord(
      workVersion: VersionRef.fromCanonical(f.require('workVersion')),
      passageId: f.string('passageId'),
      anchor: _optionalRef(f, 'anchor'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.passageRef;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('workVersion', workVersion.toCanonical()),
    MapEntry('passageId', CanonicalString(passageId)),
    MapEntry('anchor', _nullableRef(anchor)),
  ]);
}

final class SagaRecord extends RecordPayload {
  SagaRecord({
    required this.title,
    required Map<String, String> labels,
    required Iterable<SagaMembership> memberships,
  }) : labels = Map.unmodifiable(labels),
       memberships = List.unmodifiable(memberships);
  final String title;
  final Map<String, String> labels;
  final List<SagaMembership> memberships;
  factory SagaRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.saga, {
      'title',
      'labels',
      'memberships',
    });
    return SagaRecord(
      title: f.string('title'),
      labels: _strings(f, 'labels'),
      memberships: f.array('memberships').map(SagaMembership.fromWire),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.saga;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('title', CanonicalString(title)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('memberships', CanonicalArray(memberships.map((m) => m.toWire()))),
  ]);
}

final class SagaMembership {
  SagaMembership({required this.work, required this.role, BigInt? order})
    : order = order == null ? null : _checkedU64(order);
  final RecordRef work;
  final String role;
  final BigInt? order;
  factory SagaMembership.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'work', 'role', 'order'});
    return SagaMembership(
      work: RecordRef.fromCanonical(f.require('work')),
      role: f.string('role'),
      order: _optionalU64(f, 'order'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('work', work.toCanonical()),
    MapEntry('role', CanonicalString(role)),
    MapEntry('order', _nullableU64(order)),
  ]);
}
