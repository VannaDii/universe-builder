import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show temporalApplies;

import 'effective_objects.dart';
import 'record_reading.dart';

/// Builds a deterministic page from an already admitted snapshot. Purpose text
/// cannot remove rules, effective object evidence or required dependencies.
({ContextBrief brief, bool complete, int next}) buildContextBrief({
  required List<RecordVersion> all,
  required List<RecordVersion> accessible,
  required Set<RecordId> visibility,
  required List<RecordId> focusIds,
  required Frame frame,
  required WorldId? world,
  required bool restricted,
  required int byteBudget,
  required int offset,
}) {
  const denied = NotFoundOrNotAccessibleError(message: 'resource');
  final byId = {for (final row in accessible) row.identity.recordId: row};
  for (final id in focusIds) {
    if (!byId.containsKey(id)) throw denied;
  }
  final policy = all.any(isUniversePolicyRecord)
      ? UniversePolicySelection.fromRecords(frame.universe, all)
      : null;
  final excludedRules = policy?.inactiveRuleIds ?? const <RecordId>{};
  final rules = all
      .where((row) => row.payload is RuleRecord &&
          !excludedRules.contains(row.identity.recordId))
      .map((row) => row.identity.recordId)
      .toList();
  final hiddenRule = rules.any((id) => !byId.containsKey(id));
  final hiddenPolicy = policy != null &&
      (!byId.containsKey(policy.selection.identity.recordId) ||
       !byId.containsKey(policy.definition.identity.recordId));
  final objects = assembleEffectiveObjects(
    records: accessible,
    ids: focusIds,
    frame: frame,
    world: world,
    restricted: restricted,
    excludedRules: excludedRules,
  );
  final seeds = [
    if (policy != null) ...[
      if (byId.containsKey(policy.selection.identity.recordId))
        policy.selection.identity.recordId,
      if (byId.containsKey(policy.definition.identity.recordId))
        policy.definition.identity.recordId,
    ],
    ...rules.where(byId.containsKey),
    ...focusIds,
    for (final object in objects)
      for (final evidence in [
        ...object.sharedAttributes,
        ...object.instanceFacts,
        ...object.initialValueCandidates,
        ...object.behavioralRequirements,
        ...object.rules,
      ])
        evidence.record.identity.recordId,
  ];
  final appearanceRecords = accessible
      .where(
        (row) =>
            row.payload is! AppearanceRecord ||
            temporalApplies(
                  (row.payload as AppearanceRecord).validity,
                  frame.time,
                ) !=
                false,
      )
      .toList();
  final (needed, closed) = readResearchSelection(appearanceRecords, seeds);
  final hiddenAppearance = all.any(
    (row) => switch (row.payload) {
      AppearanceRecord(:final validity, :final target) =>
        temporalApplies(validity, frame.time) != false &&
            !visibility.contains(row.identity.recordId) &&
            switch (target) {
              UniverseAppearance() => true,
              EntryAppearance(:final entry) => needed.contains(entry.record),
            },
      _ => false,
    },
  );
  final sorted = needed.toList()..sort((a, b) => a.value.compareTo(b.value));
  final seen = <RecordId>{};
  final ordered = [
    for (final id in [...seeds, ...sorted])
      if (seen.add(id) && byId.containsKey(id)) byId[id]!,
  ];
  if (offset < 0 || offset > ordered.length) throw denied;
  final selected = <RecordVersion>[];
  final dependencies = <RecordId>[];
  var end = offset;
  for (final row in ordered.skip(offset)) {
    selected.add(row);
    final dependency = !focusIds.contains(row.identity.recordId);
    if (dependency) dependencies.add(row.identity.recordId);
    final trial = ContextBrief(
      records: selected,
      requiredDependencies: dependencies,
      coverage: Coverage.partial,
    );
    if (trial.toWire().toBytes().length > byteBudget) {
      selected.removeLast();
      if (dependency) dependencies.removeLast();
      break;
    }
    end++;
  }
  if (end == offset && offset < ordered.length) {
    throw const EvaluationLimitReachedError(
      message: 'context budget cannot fit the next mandatory record and dependency manifest; increase byte_budget',
    );
  }
  final complete = end == ordered.length;
  final brief = ContextBrief(
    records: selected,
    requiredDependencies: dependencies,
    coverage:
        closed &&
            !hiddenRule &&
            !hiddenPolicy &&
            !hiddenAppearance &&
            !restricted &&
            complete &&
            offset == 0
        ? Coverage.complete
        : Coverage.partial,
  );
  if (brief.toWire().toBytes().length > byteBudget) {
    throw const EvaluationLimitReachedError(
      message: 'mandatory dependency manifest exceeds the context byte budget',
    );
  }
  return (brief: brief, complete: complete, next: end);
}
