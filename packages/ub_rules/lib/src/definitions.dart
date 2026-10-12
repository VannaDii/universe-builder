import 'package:ub_domain/ub_domain.dart';

final class Ancestry {
  Ancestry({required Iterable<RecordId> types, required this.complete})
    : types = List.unmodifiable(types);
  final List<RecordId> types;
  final bool complete;
  @override
  bool operator ==(Object other) =>
      other is Ancestry &&
      complete == other.complete &&
      types.length == other.types.length &&
      Iterable<int>.generate(types.length)
          .every((i) => types[i] == other.types[i]);
  @override
  int get hashCode => Object.hash(complete, Object.hashAll(types));
}

/// One already-selected snapshot, with no revision or permission authority.
final class RecordIndex {
  RecordIndex(Iterable<RecordVersion> records)
    : _byId = {for (final r in records) r.identity.recordId: r};
  final Map<RecordId, RecordVersion> _byId;
  RecordVersion? get(RecordId id) => _byId[id];
  Ancestry ancestry(RecordId subject) => _ancestry(subject, get);
  bool? matches(
    RecordId subject,
    List<RecordId> targets,
    List<RecordId>? worlds,
  ) => _matches(subject, targets, worlds, get);
}

typedef _Lookup = RecordVersion? Function(RecordId);
_Lookup _referenceLookup(List<RecordVersion> records) => (id) {
  for (final r in records) {
    if (r.identity.recordId == id) return r;
  }
  return null;
};

Ancestry definitionAncestry(RecordId subject, List<RecordVersion> records) =>
    _ancestry(subject, _referenceLookup(records));

Ancestry _ancestry(RecordId subject, _Lookup get) {
  final record = get(subject);
  if (record == null) return Ancestry(types: [], complete: false);
  RecordId? next;
  switch (record.payload) {
    case EntityRecord(
      :final classification,
      classificationResolution: ClassificationResolution.resolved,
    ):
      next = classification;
    case EntityTypeRecord():
      next = subject;
    default:
      return Ancestry(types: [], complete: false);
  }
  final types = <RecordId>[], seen = <RecordId>{};
  var complete = true;
  while (next != null) {
    final id = next;
    if (!seen.add(id)) {
      complete = false;
      break;
    }
    final r = get(id);
    if (r == null ||
        r.identity.universeId != record.identity.universeId ||
        r.payload is! EntityTypeRecord) {
      complete = false;
      break;
    }
    final t = r.payload as EntityTypeRecord;
    if (!t.classificationExecutable ||
        t.parentResolution == ParentResolution.ambiguous) {
      complete = false;
      break;
    }
    types.add(id);
    if (t.parentResolution == ParentResolution.root && t.parent == null) {
      next = null;
    } else if (t.parentResolution == ParentResolution.resolved &&
        t.parent != null) {
      next = t.parent;
    } else {
      complete = false;
      break;
    }
  }
  return Ancestry(types: types, complete: complete && types.isNotEmpty);
}

/// Each ancestor retains independent applicability; a child cannot hide it.
bool? worldApplies(Applicability scope, List<RecordId> worlds) =>
    switch (scope) {
      UniverseApplicability() => true,
      WorldsApplicability(:final worldIds) when worldIds.isEmpty => false,
      WorldsApplicability() when worlds.isEmpty => null,
      WorldsApplicability(:final worldIds) => worlds.every(
        (r) =>
            worldIds.any((w) => r.value.substring(4) == w.value.substring(4)),
      ),
      _ => null,
    };

bool? definitionMatches(
  RecordId subject,
  List<RecordId> targets,
  List<RecordVersion> records,
  List<RecordId>? worlds,
) => _matches(subject, targets, worlds, _referenceLookup(records));

bool? _matches(
  RecordId subject,
  List<RecordId> targets,
  List<RecordId>? worlds,
  _Lookup get,
) {
  if (targets.isEmpty) return true;
  if (worlds != null && worlds.length > 1) {
    var unknown = false;
    for (final world in worlds) {
      final result = _matches(subject, targets, [world], get);
      if (result == false) return false;
      if (result == null) unknown = true;
    }
    return unknown ? null : true;
  }
  final chain = _ancestry(subject, get);
  var unknown = !chain.complete, matched = false;
  for (final id in chain.types.where(targets.contains)) {
    final r = get(id);
    if (r == null || r.payload is! EntityTypeRecord) return null;
    final t = r.payload as EntityTypeRecord;
    final applies = worlds == null
        ? true
        : worldApplies(t.applicability, worlds);
    if (applies == true && chain.complete) {
      matched = true;
    } else if (applies != false) {
      unknown = true;
    }
  }
  return unknown ? null : matched;
}

/// Type hints establish relevance, never select operands or quantifier members.
bool? ruleApplies(
  RuleRecord rule,
  List<RecordVersion> records,
  List<RecordId> worlds,
) => _ruleApplies(rule, records, worlds, _referenceLookup(records));
bool? ruleAppliesIndexed(
  RuleRecord rule,
  List<RecordVersion> records,
  RecordIndex index,
  List<RecordId> worlds,
) => _ruleApplies(rule, records, worlds, index.get);
bool? _ruleApplies(
  RuleRecord rule,
  List<RecordVersion> records,
  List<RecordId> worlds,
  _Lookup get,
) {
  if (rule.subjectTypes.isEmpty) return true;
  var unknown = false, relevant = false;
  for (final r in records.where((r) => r.payload is EntityRecord)) {
    final result = _matches(
      r.identity.recordId,
      rule.subjectTypes,
      worlds,
      get,
    );
    if (result == true) relevant = true;
    if (result == null) unknown = true;
  }
  return relevant
      ? true
      : unknown
      ? null
      : false;
}

/// Admission covers the whole authored scope, rather than one selected UI world.
bool? coversDefinitionScope(
  RecordId subject,
  List<RecordId> targets,
  List<RecordVersion> records,
  Applicability scope,
) {
  if (targets.isEmpty) return true;
  switch (scope) {
    case WorldsApplicability(:final worldIds):
      if (worldIds.isEmpty) return true;
      return definitionMatches(
        subject,
        targets,
        records,
        worldIds
            .map((w) => RecordId.parse('rec_${w.value.substring(4)}'))
            .toList(),
      );
    case UniverseApplicability():
      final match = definitionMatches(subject, targets, records, null);
      if (match != true) return match;
      final get = _referenceLookup(records);
      final chain = _ancestry(subject, get);
      var allowed = false;
      for (final id in chain.types.where(targets.contains)) {
        final r = get(id);
        if (r == null || r.payload is! EntityTypeRecord) return null;
        switch ((r.payload as EntityTypeRecord).applicability) {
          case UniverseApplicability():
            allowed = true;
          case WorldsApplicability():
            break;
          default:
            return null;
        }
      }
      return allowed;
    default:
      return null;
  }
}
