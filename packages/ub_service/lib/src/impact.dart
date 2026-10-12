import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'proposal_authorization.dart';

/// Conservative closure includes every accessible record, since a change can
/// affect conclusions based on absence or cardinality outside its direct edges.
Impact conservativeImpact({
  required List<RecordVersion> records,
  required Iterable<RecordId> changedRecords,
  required Set<WorldId>? worldScope,
  required int byteBudget,
}) {
  final visible = visibleRecordIds(records: records, worldScope: worldScope);
  for (final id in changedRecords) {
    if (!visible.contains(id)) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
  }
  final ids = visible.toList()..sort((a, b) => a.value.compareTo(b.value));
  final worlds = {
    for (final row in records)
      if (visible.contains(row.identity.recordId)) ...recordWorlds(row),
  }.toList()..sort((a, b) => a.value.compareTo(b.value));
  final result = Impact(
    records: ids,
    coverage: records.any((row) => !visible.contains(row.identity.recordId))
        ? Coverage.restricted
        : Coverage.complete,
    worldIds: worlds,
  );
  if (result.toWire().toBytes().length > byteBudget) {
    throw const EvaluationLimitReachedError(
      message: 'conservative impact closure exceeds the requested byte budget',
    );
  }
  return result;
}
