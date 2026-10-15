import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

import 'required_evidence_checks.dart';
import 'required_evidence_reviews.dart';
import 'rule_checks.dart';

/// An explicit authored departure affects eligibility, never factual support.
RecordVersion? fictionalDepartureForClaim(
  protocol.Finding finding,
  List<RecordVersion> records,
  rules.RecordIndex index,
  Iterable<RecordVersion> exceptions,
) {
  if (finding.records.length != 1 ||
      finding.coverage != protocol.Coverage.complete) {
    return null;
  }
  final target = index.get(finding.ruleId);
  if (target?.payload is! RuleRecord) return null;
  final policy = target!.payload as RuleRecord;
  if (policy.requiredEvidence == null) return null;
  final universe = target.identity.universeId;
  bool local(RecordRef ref) => ref.universe == null || ref.universe == universe;
  bool same(RecordRef a, RecordRef b) =>
      local(a) && local(b) && a.record == b.record;
  final ref = finding.records.single;
  final claim = local(ref) ? index.get(ref.record) : null;
  if (claim == null) return null;
  final scope = requiredEvidenceScope(claim.payload, index);
  if (scope == null) return null;
  final validity = switch (claim.payload) {
    AssertionRecord(:final validity) => validity,
    EventRecord(:final time) => InstantValidity(time),
    _ => null,
  };
  if (validity == null) return null;
  final worlds = switch ((policy.applicability, scope.applicability)) {
    (UniverseApplicability(), UniverseApplicability()) => <WorldId>[],
    (UniverseApplicability(), WorldsApplicability(:final worldIds)) ||
    (WorldsApplicability(:final worldIds), UniverseApplicability()) => worldIds,
    (
      WorldsApplicability(worldIds: final a),
      WorldsApplicability(worldIds: final b),
    ) =>
      a.where(b.contains).toList(),
    _ => null,
  };
  if (worlds == null) return null;
  for (final row in exceptions.where(
    (r) =>
        (r.payload as ExceptionRecord).rule.record == target.identity.recordId,
  )) {
    final e = row.payload as ExceptionRecord;
    if (!e.fictionalDeparture ||
        !local(e.rule) ||
        !local(e.authorizingDecision) ||
        !validException(e, records) ||
        !same(e.scope.context, scope.context) ||
        (e.scope.realm == null
            ? scope.realm != null
            : scope.realm == null || !same(e.scope.realm!, scope.realm!))) {
      continue;
    }
    final coveredWorlds = switch (e.scope.applicability) {
      UniverseApplicability() => true,
      WorldsApplicability(:final worldIds) =>
        worlds.isNotEmpty && worlds.every(worldIds.contains),
      _ => false,
    };
    if (!coveredWorlds) continue;
    final time = rules.validityExpression(e.validity);
    if (e.validity is! UnspecifiedValidity &&
        (time == null ||
            coversRequiredEvidenceTime(validity, policy.validity, [time]) !=
                true)) {
      continue;
    }
    return row;
  }
  return null;
}

protocol.Finding withFictionalDeparture(
  protocol.Finding finding,
  Iterable<RecordVersion> departures,
  rules.RecordIndex? index,
) {
  final selected = departures.toList();
  if (selected.isEmpty) return finding;
  final decisions = selected
      .map((r) => (r.payload as ExceptionRecord).authorizingDecision.record)
      .toSet();
  return protocol.Finding(
    ruleId: finding.ruleId,
    records: finding.records,
    fingerprint: finding.fingerprint,
    outcome: finding.outcome,
    coverage: finding.coverage,
    evidence: {
      ...finding.evidence,
      ...selected.map((r) => r.recordVersionId),
      for (final decision in decisions)
        if (index?.get(decision) case final row?) row.recordVersionId,
    },
    message:
        'Fictional departure: ${selected.map((r) => (r.payload as ExceptionRecord).rationale).join('; ')}. The factual check outcome is retained.${finding.message == null ? '' : ' ${finding.message}'}',
  );
}
