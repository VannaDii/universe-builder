import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;
import 'package:ub_store/ub_store.dart' show StoredVersion, recordDependencies;

/// Checks source eligibility only, after the owning workflow has verified
/// retained source bytes. A supported result does not discharge review duties.
/// Unrelated edits do not reopen unchanged claims; changed dependencies do.
List<protocol.Finding> assessRequiredEvidenceSources({
  required List<RecordVersion> records,
  required List<RecordVersion> base,
  required Set<RecordId> changed,
  List<RecordVersion> categories = const [],
}) {
  if (!records.any(
    (r) =>
        r.payload is RuleRecord &&
        (r.payload as RuleRecord).requiredEvidence != null,
  )) {
    return const [];
  }
  final index = rules.RecordIndex(records);
  final categoryVersions = {
    for (final r in [...records, ...categories]) r.recordVersionId: r,
  };
  final universe = records.first.identity.universeId;
  final opposing = rules.detectOpposing(
    universe: universe,
    records: records,
    indexed: true,
    budget: 10000,
  );
  final historicalPairs =
      base.any(
        (r) =>
            changed.contains(r.identity.recordId) &&
            r.payload is AssertionRecord,
      )
      ? rules
            .detectOpposing(
              universe: universe,
              records: base,
              indexed: true,
              budget: 10000,
            )
            .pairs
      : const <rules.OpposingPair>[];
  final dependents = <RecordId, Set<RecordId>>{};
  for (final row in [...base, ...records]) {
    for (final dependency in recordDependencies(
      StoredVersion(
        versionId: row.recordVersionId,
        identity: row.identity,
        payload: row.payload.toWire(),
        digest: row.payloadDigest,
      ),
    )) {
      (dependents[dependency] ??= {}).add(row.identity.recordId);
    }
  }
  for (final pair in [...opposing.pairs, ...historicalPairs]) {
    final a = pair.support.assertion.identity.recordId;
    final b = pair.refutation.assertion.identity.recordId;
    (dependents[a] ??= {}).add(b);
    (dependents[b] ??= {}).add(a);
  }
  final affected = <RecordId>{};
  final pending = changed.toList();
  while (pending.isNotEmpty) {
    final next = pending.removeLast();
    if (!affected.add(next)) continue;
    pending.addAll(dependents[next] ?? const <RecordId>{});
  }
  final findings = <protocol.Finding>[];
  for (final policy in records) {
    final rule = policy.payload;
    if (rule is! RuleRecord || rule.requiredEvidence == null) continue;
    final requirement = rule.requiredEvidence!;
    final categories = <RecordVersion>[];
    var categoriesResolved = requirement.sourceCategories.isNotEmpty;
    for (final ref in requirement.sourceCategories) {
      final category = categoryVersions[ref.version];
      if (category == null ||
          ref.universe != null && ref.universe != policy.identity.universeId ||
          category.recordVersionId != ref.version ||
          category.identity.recordId != ref.record ||
          category.payload is! DomainPackRecord) {
        categoriesResolved = false;
      } else {
        categories.add(category);
      }
    }
    for (final row in records) {
      final payload = row.payload;
      if (payload is! AssertionRecord && payload is! EventRecord ||
          !affected.contains(row.identity.recordId) &&
              !affected.contains(policy.identity.recordId)) {
        continue;
      }
      final scope = requiredEvidenceScope(payload, index);
      final applicability =
          scope?.applicability ??
          (payload is EventRecord
              ? (payload.worlds.isEmpty
                    ? const UniverseApplicability()
                    : WorldsApplicability(payload.worlds))
              : const UnspecifiedApplicability());
      final validity = payload is AssertionRecord
          ? payload.validity
          : InstantValidity((payload as EventRecord).time);
      final basis = requiredEvidenceBasis(payload, index);
      final List<RecordId> subjects;
      String? predicateKey;
      var occurrenceUnresolved = false;
      if (payload is AssertionRecord) {
        final proposition = index.get(payload.proposition.record)?.payload;
        if (proposition is! PropositionRecord) continue;
        subjects = [proposition.subject.record];
        final predicate = index.get(proposition.predicate.record)?.payload;
        predicateKey = switch (predicate) {
          PropertyRecord(:final namespace, :final key) ||
          RelationRecord(:final namespace, :final key) => '$namespace:$key',
          _ => null,
        };
      } else {
        final event = payload as EventRecord;
        if (rule.targetPredicates.isNotEmpty) continue;
        if (event.occurrence case SimpleOccurrence(:final kind)) {
          if (kind != OccurrenceKind.occurred) continue;
        } else {
          occurrenceUnresolved = true;
        }
        subjects = event.participants.map((p) => p.record.record).toList();
      }
      final context = scope == null
          ? null
          : index.get(scope.context.record)?.payload;
      if (context is RepresentedContextRecord &&
          context.kind is! ObjectiveContext) {
        continue;
      }
      if (rule.targetPredicates.isNotEmpty &&
          !rule.targetPredicates.contains(predicateKey)) {
        continue;
      }
      final worldMatch = _overlaps(rule.applicability, applicability);
      final worlds = switch ((rule.applicability, applicability)) {
        (
          WorldsApplicability(worldIds: final left),
          WorldsApplicability(worldIds: final right),
        ) =>
          left
              .where(right.contains)
              .map((w) => RecordId.parse('rec_${w.value.substring(4)}'))
              .toList(),
        (WorldsApplicability(:final worldIds), _) ||
        (_, WorldsApplicability(:final worldIds)) =>
          worldIds
              .map((w) => RecordId.parse('rec_${w.value.substring(4)}'))
              .toList(),
        _ => null,
      };
      final matches = subjects
          .map((subject) => index.matches(subject, rule.subjectTypes, worlds))
          .toList();
      final bool? typeMatch =
          rule.subjectTypes.isEmpty || matches.contains(true)
          ? true
          : subjects.isEmpty || matches.contains(null)
          ? null
          : false;
      final timeMatch = rule.validity is UnspecifiedValidity
          ? true
          : rules.temporalOverlaps(rule.validity, validity);
      if (worldMatch == false || typeMatch == false || timeMatch == false) {
        continue;
      }
      var outcome = protocol.EvidenceOutcome.notEstablished;
      var coverage = protocol.Coverage.complete;
      var message =
          'This required claim needs an anchor to a source in an authored qualifying category.';
      final evidence = <RecordVersionId>[
        policy.recordVersionId,
        row.recordVersionId,
        ...categories.map((c) => c.recordVersionId),
        if (payload is AssertionRecord &&
            payload.establishedBy != null &&
            index.get(payload.establishedBy!.event.record) != null)
          index.get(payload.establishedBy!.event.record)!.recordVersionId,
        if (payload is EventRecord &&
            payload.action != null &&
            index.get(payload.action!.record) != null)
          index.get(payload.action!.record)!.recordVersionId,
      ];
      if (worldMatch == null ||
          typeMatch == null ||
          timeMatch == null ||
          scope == null ||
          context is! RepresentedContextRecord ||
          occurrenceUnresolved) {
        coverage = protocol.Coverage.unsupported;
        message = payload is EventRecord
            ? 'Resolve this event’s declared action, context, world, subject scope, occurrence or time before applying its evidence policy.'
            : 'Resolve this claim’s world, subject classification or time before applying its evidence policy.';
      } else if (!categoriesResolved) {
        message = 'Select nonempty qualifying source categories at their exact published versions.';
      } else if (payload is AssertionRecord &&
          (payload.precision == Precision.unresolved ||
              payload.precision == Precision.oneOf ||
              payload.alternatives.isNotEmpty)) {
        message = 'This required fact still has unresolved alternatives; a qualifying source does not resolve them by itself.';
      } else if (basis case SourceAnchorBasis(:final anchor)) {
        final anchorRow = index.get(anchor.record);
        final payload = anchorRow?.payload;
        if (payload is AnchorRecord &&
            (anchor.universe == null ||
                anchor.universe == row.identity.universeId)) {
          final source = index.get(payload.sourceVersion.record);
          if (source != null &&
              source.payload is SourceVersionRecord &&
              source.recordVersionId == payload.sourceVersion.version &&
              (payload.sourceVersion.universe == null ||
                  payload.sourceVersion.universe == row.identity.universeId) &&
              categories.any(
                (c) => (c.payload as DomainPackRecord).records.contains(
                  source.identity.recordId,
                ),
              )) {
            outcome = protocol.EvidenceOutcome.supported;
            message = 'The retained source belongs to an authored qualifying category; interpretation review is evaluated separately when required.';
            evidence.addAll([
              anchorRow!.recordVersionId,
              source.recordVersionId,
            ]);
          }
        }
      } else if (basis is DerivationBasis || basis is EventEffectBasis) {
        coverage = protocol.Coverage.unsupported;
        message = 'Derived and event-effect source admission requires its evidence evaluator.';
      }
      for (final pair in opposing.pairs.where(
        (p) =>
            p.support.assertion.identity.recordId == row.identity.recordId ||
            p.refutation.assertion.identity.recordId == row.identity.recordId,
      )) {
        final applies = pair.applicability == null
            ? null
            : _overlaps(rule.applicability, pair.applicability!);
        final bool? overlaps = rule.validity is UnspecifiedValidity
            ? true
            : switch (pair.intersection) {
                rules.ExactIntersection(:final validity) =>
                  rules.temporalOverlaps(rule.validity, validity),
                _ => null,
              };
        if (applies == false || overlaps == false) continue;
        outcome = protocol.EvidenceOutcome.conflicting;
        if (applies == null || overlaps == null || !pair.definite) {
          coverage = protocol.Coverage.unsupported;
        }
        message = 'Opposing evidence remains in this required claim’s scope; resolve the disagreement without discarding its attribution.';
        evidence.addAll([
          pair.support.assertion.recordVersionId,
          pair.refutation.assertion.recordVersionId,
        ]);
      }
      if (opposing.gaps.contains(rules.OpposingGap.budget)) {
        outcome = protocol.EvidenceOutcome.notEstablished;
        coverage = protocol.Coverage.unsupported;
        message = 'The existing opposing-evidence comparison limit prevented a complete check of this required claim.';
      }
      findings.add(
        protocol.Finding(
          ruleId: policy.identity.recordId,
          records: [
            RecordRef(
              universe: row.identity.universeId,
              record: row.identity.recordId,
            ),
          ],
          fingerprint: const FindingFingerprint(''),
          outcome: outcome,
          evidence: evidence,
          coverage: coverage,
          message: message,
        ),
      );
    }
  }
  return findings;
}

/// Resolve exact published pins under the owning workflow's admitted universe.
/// A later category revision does not silently change the policy's membership.
Future<List<RecordVersion>> resolveRequiredEvidenceCategories({
  required List<RecordVersion> records,
  required FutureOr<RecordVersion> Function(RecordVersionId) readVersion,
}) async {
  final available = {for (final row in records) row.recordVersionId: row};
  final selected = <RecordVersionId, RecordVersion>{};
  for (final row in records) {
    final rule = row.payload;
    if (rule is! RuleRecord) continue;
    for (final ref
        in rule.requiredEvidence?.sourceCategories ?? <VersionRef>[]) {
      selected[ref.version] ??=
          available[ref.version] ?? await readVersion(ref.version);
    }
  }
  return List.unmodifiable(selected.values);
}

bool? _overlaps(Applicability a, Applicability b) => switch ((a, b)) {
  (ConditionalApplicability() || UnspecifiedApplicability(), _) ||
  (_, ConditionalApplicability() || UnspecifiedApplicability()) => null,
  (
    WorldsApplicability(worldIds: final left),
    WorldsApplicability(worldIds: final right),
  ) =>
    left.any(right.contains),
  (WorldsApplicability(:final worldIds), _) ||
  (_, WorldsApplicability(:final worldIds)) => worldIds.isNotEmpty,
  _ => true,
};

/// Event context/realm come from its existing declared action, never the UI focus.
Scope? requiredEvidenceScope(RecordPayload payload, rules.RecordIndex index) {
  if (payload is AssertionRecord) return payload.scope;
  if (payload is! EventRecord) return null;
  final reference = payload.action;
  if (reference == null) return null;
  final action = index.get(reference.record)?.payload;
  if (action is! ActionDefinitionRecord) return null;
  return Scope(
    context: action.scope.context,
    realm: action.scope.realm,
    applicability: payload.worlds.isEmpty
        ? const UniverseApplicability()
        : WorldsApplicability(payload.worlds),
  );
}

/// The caller must first verify generated effects against expandEvents.
EvidenceBasis? requiredEvidenceBasis(
  RecordPayload payload,
  rules.RecordIndex index,
) {
  if (payload is EventRecord) return payload.basis;
  if (payload is! AssertionRecord) return null;
  final established = payload.establishedBy;
  if (established == null) return payload.basis;
  final event = index.get(established.event.record)?.payload;
  return event is EventRecord ? event.basis : null;
}
