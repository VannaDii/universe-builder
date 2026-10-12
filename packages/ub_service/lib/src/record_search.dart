import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'proposal_authorization.dart';
import 'record_reading.dart';

bool recordNameMatches(RecordVersion row, String query) {
  final lower = query.toLowerCase();
  if (recordReadLabel(row).toLowerCase().contains(lower)) return true;
  return switch (row.payload) {
    EntityRecord(:final names, :final labels) =>
      names.any((name) => name.text.toLowerCase().contains(lower)) ||
          labels.values.any((label) => label.toLowerCase().contains(lower)),
    WorldRecord(:final aliases) => aliases.any(
      (alias) => alias.toLowerCase().contains(lower),
    ),
    _ => false,
  };
}

String recordSearchLabel(
  RecordVersion row,
  Map<RecordId, RecordVersion> visible, {
  required bool author,
}) {
  if (!author) return recordReadLabel(row);
  String? label(RecordRef reference) {
    final target = visible[reference.record];
    return target == null ? null : recordReadLabel(target);
  }

  String? propositionLabel(RecordRef reference) {
    final payload = visible[reference.record]?.payload;
    if (payload is! PropositionRecord) return null;
    final subject = label(payload.subject),
        predicate = label(payload.predicate);
    return subject == null || predicate == null ? null : '$subject.$predicate';
  }

  switch (row.payload) {
    case ItemPowerRecord(:final item, :final powerPredicate):
      final itemLabel = label(item), powerLabel = label(powerPredicate);
      if (itemLabel != null && powerLabel != null) {
        return '$itemLabel — $powerLabel';
      }
    case CommunicationRecord(:final sender, :final content):
      final senderLabel = label(sender);
      if (senderLabel != null) {
        final labels = content
            .map(propositionLabel)
            .whereType<String>()
            .join(', ');
        return '$senderLabel — message $labels';
      }
    case EpistemicAttitudeRecord(
      :final holder,
      :final proposition,
      :final attitude,
    ):
      final holderLabel = label(holder),
          factLabel = propositionLabel(proposition);
      if (holderLabel != null && factLabel != null) {
        final kind = attitude.name;
        return '$holderLabel — ${kind[0].toUpperCase()}${kind.substring(1)} $factLabel';
      }
    default:
      break;
  }
  return recordReadLabel(row);
}

/// Indexed matches are intersected with already admitted records. Name/ID
/// fallback, filters, labels and categories never widen that visibility.
List<SearchHit> buildSearchHits({
  required List<RecordVersion> accessible,
  required Set<RecordId> indexed,
  required String query,
  required Filters filters,
  required WorldId? world,
  required bool author,
}) {
  final visible = {for (final row in accessible) row.identity.recordId: row};
  final hits = <SearchHit>[];
  for (final row in accessible) {
    if (filters.recordKinds.isNotEmpty &&
        !filters.recordKinds.contains(row.identity.recordKind)) {
      continue;
    }
    if (query.isNotEmpty &&
        !indexed.contains(row.identity.recordId) &&
        !recordNameMatches(row, query) &&
        row.identity.recordId.value != query) {
      continue;
    }
    final worlds = recordWorlds(row).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    hits.add(
      SearchHit(
        recordId: row.identity.recordId,
        kind: row.identity.recordKind,
        label: recordSearchLabel(row, visible, author: author),
        worldIds: worlds,
        scopeCategory: worlds.isEmpty
            ? ScopeCategory.unassigned
            : world != null && !worlds.contains(world)
            ? ScopeCategory.requiredDependency
            : worlds.length > 1
            ? ScopeCategory.shared
            : ScopeCategory.selectedWorld,
      ),
    );
  }
  hits.sort((a, b) => a.recordId.value.compareTo(b.recordId.value));
  return List.unmodifiable(hits);
}
