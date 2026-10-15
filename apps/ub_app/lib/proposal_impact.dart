import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'record_browser.dart';
import 'saved_changes.dart';

final class ProposalImpactRecord {
  const ProposalImpactRecord({
    required this.id,
    required this.label,
    this.summary,
    this.change,
  });
  final RecordId id;
  final String label;
  final RecordSummary? summary;
  final CompiledChange? change;
}

/// An immutable proposal and its service-reported conservative review scope.
/// Labels are read a page at a time at the same pinned frame.
final class ProposalImpactSnapshot {
  const ProposalImpactSnapshot({
    required this.proposal,
    required this.context,
    required this.impact,
  });
  final Proposal proposal;
  final OpenedContext context;
  final Impact impact;

  Future<List<ProposalImpactRecord>> page(
    SavedChanges changes, {
    required int offset,
    int limit = 25,
  }) async {
    if (offset < 0 || limit < 1 || limit > 50) {
      throw const FormatException('Invalid impact page.');
    }
    final ids = impact.records.skip(offset).take(limit).toList();
    if (ids.isEmpty) return [];
    final compiled = {
      for (final row in proposal.compiledChanges) row.recordId: row,
    };
    final candidates = Records(
      records: [
        for (final row in proposal.compiledChanges)
          if (row.next != null) row.next!,
      ],
    );
    final baseline = ids.where((id) => compiled[id]?.next == null).toSet();
    final summaries = <RecordId, RecordSummary>{};
    if (baseline.isNotEmpty) {
      final result = Envelope<Records>.fromWire(
        await changes.session.call(
          ToolEngineRequest(
            request: GetRequest(
              universe: changes.universe,
              universeId: changes.scope.universe,
              contextId: context.contextId,
              recordIds: baseline,
              fieldGroups: [FieldGroup.summary],
            ),
          ),
        ),
        Records.fromWire,
      );
      if (!result.delivery.complete) {
        throw const FormatException(
          'Impact names could not be read completely.',
        );
      }
      for (final summary in result.result.summaries) {
        summaries[summary.recordId] = summary;
      }
    }
    return [
      for (final id in ids)
        ProposalImpactRecord(
          id: id,
          summary: summaries[id],
          change: compiled[id],
          label: compiled[id]?.next != null
              ? dossierReferenceLabel(
                  candidates,
                  changes.scope.universe,
                  RecordRef(record: id),
                  unavailableLabel:
                      'Proposed ${compiled[id]!.next!.identity.recordKind.wireName.replaceAll('_', ' ')}',
                )
              : summaries[id]?.label ?? 'Name unavailable at this revision',
        ),
    ];
  }
}

Future<ProposalImpactSnapshot> readProposalImpact(
  SavedChanges changes,
  Proposal proposal, {
  int byteBudget = 65536,
}) async {
  final frame = proposal.baseFrame;
  final context = Envelope<OpenedContext>.fromWire(
    await changes.session.call(
      ToolEngineRequest(
        request: OpenContextRequest(
          universe: changes.universe,
          universeId: changes.scope.universe,
          continuityId: frame.continuity,
          revision: ExactRevisionSelector(revisionId: frame.revision),
          representedContext: ContextIdSelector(frame.context.record),
          temporalQuery: frame.time,
          temporalSystems: [],
          perspective: frame.perspective,
        ),
      ),
    ),
    OpenedContext.fromWire,
  ).result;
  final impact = Envelope<Impact>.fromWire(
    await changes.session.call(
      ToolEngineRequest(
        request: ProposalImpactRequest(
          universe: changes.universe,
          universeId: changes.scope.universe,
          contextId: context.contextId,
          proposalReference: changes.reference(proposal),
          scope: CheckScope.universe,
          byteBudget: byteBudget,
        ),
      ),
    ),
    Impact.fromWire,
  ).result;
  return ProposalImpactSnapshot(
    proposal: proposal,
    context: context,
    impact: impact,
  );
}
