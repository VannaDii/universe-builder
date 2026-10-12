import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

StoredVersion _stored(RecordVersion r) => StoredVersion(
  versionId: r.recordVersionId,
  identity: r.identity,
  payload: r.payload.toWire(),
  digest: r.payloadDigest,
);
Set<RecordId> _dependencies(RecordVersion r) => recordDependencies(_stored(r));
Set<WorldId> _applicability(Applicability a) =>
    a is WorldsApplicability ? a.worldIds.toSet() : {};

/// Direct world assignments are authored, never inferred from prose or metadata.
Set<WorldId> recordWorlds(RecordVersion record) => Set.unmodifiable(
  switch (record.payload) {
    WorldRecord() => {recordWorld(record.identity.recordId)},
    EntityRecord(:final worldAssociations) => {
      for (final w in worldAssociations) w.world,
    },
    WorkRecord(:final worldAssociations) => {
      for (final w in worldAssociations) w.world,
    },
    AssertionRecord(:final scope) => _applicability(scope.applicability),
    EventRecord(:final worlds) => worlds.toSet(),
    ItemPowerRecord(:final scope) => _applicability(scope.applicability),
    ActionDefinitionRecord(:final scope) => _applicability(scope.applicability),
    RuleRecord(:final applicability) => _applicability(applicability),
    _ => <WorldId>{},
  },
);

bool protectedRecord(RecordPayload payload) =>
    !(payload is AppearanceRecord ||
        payload is ImageAssetRecord ||
        payload is EntityRecord ||
        payload is WorldRecord ||
        payload is WorkRecord ||
        payload is SagaRecord ||
        payload is PropositionRecord ||
        payload is AssertionRecord ||
        payload is AnchorRecord ||
        payload is SourceRecord ||
        payload is SourceVersionRecord ||
        payload is WorkVersionRecord ||
        payload is SceneRecord ||
        payload is PassageRecord);

/// Frozen proposal scope, not a permission or approval grant.
final class WriteFootprint {
  WriteFootprint({
    Iterable<WorldId> worlds = const [],
    this.shared = false,
    this.protected = false,
  }) : worlds = Set.unmodifiable(
         worlds.toSet().toList()..sort((a, b) => a.value.compareTo(b.value)),
       );
  final Set<WorldId> worlds;
  final bool shared, protected;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'worlds',
      CanonicalArray(worlds.map((w) => CanonicalString(w.value))),
    ),
    MapEntry('shared', CanonicalBool(shared)),
    MapEntry('protected', CanonicalBool(protected)),
  ]);
}

WriteFootprint writeFootprint({
  required List<RecordVersion> base,
  required List<Assignment> changes,
}) {
  final worlds = <WorldId>{};
  var shared = false, protected = false;
  for (final change in changes) {
    final roots = [
      for (final r in base)
        if (r.identity.recordId == change.recordId) r,
      if (change.next != null)
        RecordVersion.fromWire(change.next!.toCanonical()),
    ];
    for (final r in roots) {
      final direct = recordWorlds(r);
      shared |= direct.isEmpty;
      worlds.addAll(direct);
      protected |= protectedRecord(r.payload);
    }
    final pending = [...roots], visited = <RecordVersionId>{};
    while (pending.isNotEmpty) {
      final r = pending.removeLast();
      if (!visited.add(r.recordVersionId)) {
        continue;
      }
      Set<RecordId> deps;
      try {
        deps = _dependencies(r);
      } on FormatException {
        shared = true;
        continue;
      }
      for (final id in deps) {
        Assignment? candidate;
        for (final c in changes) {
          if (c.recordId == id) {
            candidate = c;
            break;
          }
        }
        RecordVersion? next;
        if (candidate?.next != null) {
          next = RecordVersion.fromWire(candidate!.next!.toCanonical());
        }
        next ??= base.where((r) => r.identity.recordId == id).firstOrNull;
        if (next == null) {
          continue;
        }
        worlds.addAll(recordWorlds(next));
        pending.add(next);
      }
    }
    protected |= change.next == null;
  }
  return WriteFootprint(worlds: worlds, shared: shared, protected: protected);
}

/// Scoped reads close over hidden and missing dependencies. These IDs are only
/// one part of request admission; current installation grants still apply.
Set<RecordId> visibleRecordIds({
  required List<RecordVersion> records,
  required Set<WorldId>? worldScope,
}) {
  final all = {for (final r in records) r.identity.recordId};
  if (worldScope == null) {
    return Set.unmodifiable(all);
  }
  final hidden = <RecordId>{}, reverse = <RecordId, List<RecordId>>{};
  var edges = 0;
  for (final r in records) {
    final p = r.payload;
    if (!worldScope.containsAll(recordWorlds(r)) ||
        p is IssueDecisionRecord ||
        p is ImageAssetRecord ||
        p is AppearanceRecord && p.target is UniverseAppearance ||
        p is SourceRecord ||
        p is SourceVersionRecord ||
        p is AnchorRecord) {
      hidden.add(r.identity.recordId);
    }
    for (final dependency in _dependencies(r)) {
      if (++edges > 5000000) {
        throw const EvaluationLimitReachedError(
          message: 'Authorization dependency budget exceeded',
        );
      }
      if (!all.contains(dependency)) {
        hidden.add(r.identity.recordId);
      }
      (reverse[dependency] ??= []).add(r.identity.recordId);
    }
  }
  final pending = hidden.toList();
  while (pending.isNotEmpty) {
    for (final dependent
        in reverse[pending.removeLast()] ?? const <RecordId>[]) {
      if (hidden.add(dependent)) {
        pending.add(dependent);
      }
    }
  }
  return Set.unmodifiable(all.difference(hidden));
}

/// Exact old/new record boundaries. World permissions, expiry and delegation
/// must be checked separately against the current installation authority.
void checkWriteBoundaries({
  required List<RecordVersion> base,
  required List<Assignment> changes,
  required ContinuityId continuity,
  required GrantLimits limits,
}) {
  if (limits.continuities != null &&
      !limits.continuities!.contains(continuity)) {
    throw const NotFoundOrNotAccessibleError(message: 'resource');
  }
  if (limits.entities == null && limits.predicates == null) {
    return;
  }
  final versions = [
    ...base,
    for (final c in changes)
      if (c.next != null) RecordVersion.fromWire(c.next!.toCanonical()),
  ];
  final references = {
    for (final r in versions) r.recordVersionId: _dependencies(r),
  };
  final entities = {
    for (final r in versions)
      if (r.payload is EntityRecord) r.identity.recordId,
  };
  bool permitted(RecordVersion r) {
    PropositionRecord? p;
    if (r.payload is PropositionRecord) {
      p = r.payload as PropositionRecord;
    }
    if (r.payload case AssertionRecord(:final proposition)) {
      for (final other in versions) {
        if (other.identity.recordId == proposition.record &&
            other.payload is PropositionRecord) {
          p = other.payload as PropositionRecord;
          break;
        }
      }
    }
    if (p != null) {
      final ids = limits.entities;
      if (ids != null &&
          (!ids.contains(p.subject.record) ||
              !p.roles.every((role) => ids.contains(role.participant.record)) ||
              versions
                  .where(
                    (r) => r.payload is PropositionRecord && r.payload == p,
                  )
                  .any(
                    (r) => references[r.recordVersionId]!
                        .where(entities.contains)
                        .any((id) => !ids.contains(id)),
                  ))) {
        return false;
      }
      return limits.predicates == null ||
          limits.predicates!.contains(p.predicate.record);
    }
    return r.payload is EntityRecord &&
        limits.predicates == null &&
        (limits.entities == null ||
            limits.entities!.contains(r.identity.recordId));
  }

  for (final change in changes) {
    if (versions
        .where((r) => r.identity.recordId == change.recordId)
        .any((r) => !permitted(r))) {
      throw const PolicyDeniedError(
        message: 'write exceeds entity or predicate grant boundaries',
      );
    }
  }
}
