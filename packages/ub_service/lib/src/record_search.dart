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
    return target == null ||
            target.identity.universeId !=
                (reference.universe ?? row.identity.universeId)
        ? null
        : recordReadLabel(target);
  }

  String? propositionLabel(RecordRef reference) {
    final target = visible[reference.record];
    if (target == null ||
        target.identity.universeId !=
            (reference.universe ?? row.identity.universeId)) {
      return null;
    }
    final payload = target.payload;
    if (payload is! PropositionRecord) return null;
    final subject = label(payload.subject),
        predicate = label(payload.predicate);
    return subject == null || predicate == null ? null : '$subject.$predicate';
  }

  String? valueLabel(DomainValue value) => switch (value) {
    TextValue(:final text) =>
      text.runes.length > 160
          ? '${String.fromCharCodes(text.runes.take(160))}…'
          : text,
    BooleanValue(:final value) => value ? 'Yes' : 'No',
    IntegerValue(:final digits) || DecimalValue(:final digits) => digits,
    RationalValue(:final numerator, :final denominator) =>
      '$numerator / $denominator',
    ReferenceValue(:final record) => label(record),
    _ => 'Typed value',
  };
  switch (row.payload) {
    case PropositionRecord(
      :final subject,
      :final predicate,
      :final context,
      :final roles,
      :final value,
      :final quantification,
    ):
      final subjectLabel = label(subject),
          predicateLabel = label(predicate),
          contextLabel = label(context);
      if (subjectLabel == null ||
          predicateLabel == null ||
          contextLabel == null) {
        break;
      }
      final roleLabels = <String>[];
      for (final role in roles) {
        final participant = label(role.participant);
        if (participant == null) return recordReadLabel(row);
        roleLabels.add('${role.role}: $participant');
      }
      final amount = value == null ? null : valueLabel(value);
      if (value != null && amount == null) break;
      final quantifier = switch (quantification) {
        Quantification.particular => 'Particular',
        Quantification.universal => 'Universal',
        Quantification.exists => 'Exists',
      };
      return '$quantifier: $subjectLabel.$predicateLabel'
          '${value == null ? '' : ' = $amount'}'
          '${roleLabels.isEmpty ? '' : ' — ${roleLabels.join('; ')}'} [$contextLabel]';
    case IssueDecisionRecord(:final mode, :final scope):
      final target = visible.values
          .where(
            (target) =>
                target.identity.recordId.value == scope &&
                target.identity.universeId == row.identity.universeId,
          )
          .firstOrNull;
      if (target != null) {
        final state = mode.name;
        return '${state[0].toUpperCase()}${state.substring(1)} decision: ${recordReadLabel(target)}';
      }
    case ObservationRecord(:final observer, :final observed):
      final observerLabel = label(observer),
          observedLabel = propositionLabel(observed) ?? label(observed);
      if (observerLabel != null && observedLabel != null) {
        return '$observerLabel — observation of $observedLabel';
      }
    case MemoryRecord(:final holder, :final content):
      final holderLabel = label(holder),
          contentLabel = propositionLabel(content) ?? label(content);
      if (holderLabel != null && contentLabel != null) {
        return '$holderLabel — memory of $contentLabel';
      }
    case GoalRecord(:final actor, :final desired, :final status):
      final actorLabel = label(actor),
          desiredLabel = desired == null
              ? null
              : propositionLabel(desired) ?? label(desired);
      if (actorLabel != null && (desired == null || desiredLabel != null)) {
        final state = status.name;
        return '$actorLabel — ${state[0].toUpperCase()}${state.substring(1)} plan${desired == null ? '' : ': $desiredLabel'}';
      }
    case CommitmentRecord(:final parties, :final obligated, :final status):
      final obligation = propositionLabel(obligated) ?? label(obligated);
      if (obligation == null) break;
      final partyLabels = <String>[];
      for (final party in parties) {
        final partyLabel = label(party.record);
        if (partyLabel == null) return recordReadLabel(row);
        partyLabels.add('${party.role}: $partyLabel');
      }
      final state = status.name;
      return '${state[0].toUpperCase()}${state.substring(1)} commitment'
          '${partyLabels.isEmpty ? '' : ': ${partyLabels.join('; ')}'} — $obligation';
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
    final label = recordSearchLabel(row, visible, author: author);
    if (query.isNotEmpty &&
        !label.toLowerCase().contains(query.toLowerCase()) &&
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
        label: label,
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
