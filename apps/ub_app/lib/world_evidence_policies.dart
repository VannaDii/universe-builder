import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_browser.dart';

enum WorldPolicyOrigin { universe, selectedWorld, unresolved }

WorldPolicyOrigin? worldEvidencePolicyOrigin(RuleRecord rule, WorldId world) {
  if (rule.requiredEvidence == null) return null;
  return switch (rule.applicability) {
    UniverseApplicability() => WorldPolicyOrigin.universe,
    WorldsApplicability(:final worldIds) =>
      worldIds.contains(world) ? WorldPolicyOrigin.selectedWorld : null,
    ConditionalApplicability() ||
    UnspecifiedApplicability() => WorldPolicyOrigin.unresolved,
  };
}

final class WorldEvidencePolicy {
  const WorldEvidencePolicy(this.record, this.origin);
  final RecordVersion record;
  final WorldPolicyOrigin origin;
  RuleRecord get rule => record.payload as RuleRecord;
  String get originLabel => switch (origin) {
    WorldPolicyOrigin.universe => 'Inherited from the universe',
    WorldPolicyOrigin.selectedWorld => 'Selected for this world',
    WorldPolicyOrigin.unresolved => 'World applicability needs resolution',
  };
}

final class WorldEvidencePolicies {
  WorldEvidencePolicies({
    required Iterable<WorldEvidencePolicy> policies,
    required Map<RecordId, RecordVersion> categories,
    required this.complete,
  }) : policies = List.unmodifiable(policies),
       categories = Map.unmodifiable(categories);
  final List<WorldEvidencePolicy> policies;
  final Map<RecordId, RecordVersion> categories;

  /// Complete delivery of the visible collection, not a grant or reality verdict.
  final bool complete;
}

/// All pages and display names use the supplied immutable context. The service
/// retains its ordinary read permissions; this view never selects a policy.
Future<WorldEvidencePolicies> readWorldEvidencePolicies({
  required AppSession session,
  required LibraryEntry universe,
  required OpenedContext context,
  required WorldId world,
}) async {
  final rows = <RecordVersion>[];
  var complete = true;
  Future<List<RecordVersion>> read(Iterable<RecordId> requested) async {
    final ids = requested.toSet().toList(), rows = <RecordVersion>[];
    for (var offset = 0; offset < ids.length; offset += 50) {
      final batch = ids.skip(offset).take(50).toSet();
      try {
        final result = Envelope<Records>.fromWire(
          await session.call(
            ToolEngineRequest(
              request: GetRequest(
                universe: Selector(universe.name),
                universeId: universe.id,
                contextId: context.contextId,
                recordIds: batch,
                fieldGroups: [FieldGroup.payload],
              ),
            ),
          ),
          Records.fromWire,
        );
        final delivered = result.result.records
            .where(
              (r) =>
                  r.identity.universeId == universe.id &&
                  batch.contains(r.identity.recordId),
            )
            .toList();
        complete =
            complete &&
            result.delivery.complete &&
            delivered
                .map((r) => r.identity.recordId)
                .toSet()
                .containsAll(batch);
        rows.addAll(delivered);
      } on Object {
        complete = false;
      }
    }
    return rows;
  }

  for (final kind in [RecordKind.rule, RecordKind.domainPack]) {
    String? cursor;
    final cursors = <String>{};
    do {
      final page = await searchContextRecords(
        session: session,
        universe: universe,
        context: context,
        query: '',
        kind: kind,
        cursor: cursor,
      );
      rows.addAll(await read(page.result.hits.map((r) => r.recordId)));
      cursor = page.delivery.cursor;
      if (page.delivery.complete) {
        break;
      }
      if (cursor == null || !cursors.add(cursor)) {
        complete = false;
        break;
      }
    } while (true);
  }
  Set<RecordId> inactive = const {};
  var rootResolved = complete;
  try {
    inactive = UniversePolicySelection.fromRecords(
      universe.id,
      rows,
    ).inactiveRuleIds;
  } on FormatException {
    // Missing/restricted root metadata cannot establish which rules are active.
    rootResolved = false;
    complete = false;
  }
  final policies = <WorldEvidencePolicy>[
    for (final row in rows)
      if (!inactive.contains(row.identity.recordId))
        if (row.payload case RuleRecord rule)
          if (worldEvidencePolicyOrigin(rule, world) case final origin?)
            WorldEvidencePolicy(
              row,
              rootResolved ? origin : WorldPolicyOrigin.unresolved,
            ),
  ];
  final categoryIds = <RecordId>{
    for (final policy in policies)
      for (final ref in policy.rule.requiredEvidence!.sourceCategories)
        if (ref.universe == null || ref.universe == universe.id) ref.record,
  };
  final categories = await read(categoryIds);
  return WorldEvidencePolicies(
    policies: policies,
    categories: {for (final row in categories) row.identity.recordId: row},
    complete: complete,
  );
}
