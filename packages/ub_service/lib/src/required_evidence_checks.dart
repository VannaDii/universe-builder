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
}) {
  if (!records.any(
    (r) =>
        r.payload is RuleRecord &&
        (r.payload as RuleRecord).requiredEvidence != null,
  )) {
    return const [];
  }
  final index = rules.RecordIndex(records);
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
      final category = index.get(ref.record);
      if (category == null ||
          ref.universe != null && ref.universe != policy.identity.universeId ||
          category.recordVersionId != ref.version ||
          category.payload is! DomainPackRecord) {
        categoriesResolved = false;
      } else {
        categories.add(category);
      }
    }
    for (final row in records) {
      final assertion = row.payload;
      if (assertion is! AssertionRecord ||
          !affected.contains(row.identity.recordId) &&
              !affected.contains(policy.identity.recordId)) {
        continue;
      }
      final proposition = index.get(assertion.proposition.record)?.payload;
      if (proposition is! PropositionRecord) {
        continue; // Structural check owns this.
      }
      final context = index.get(assertion.scope.context.record)?.payload;
      if (context is! RepresentedContextRecord ||
          context.kind is! ObjectiveContext) {
        continue;
      }
      final predicate = index.get(proposition.predicate.record)?.payload;
      final predicateKey = switch (predicate) {
        PropertyRecord(:final namespace, :final key) ||
        RelationRecord(:final namespace, :final key) => '$namespace:$key',
        _ => null,
      };
      if (rule.targetPredicates.isNotEmpty &&
          !rule.targetPredicates.contains(predicateKey)) {
        continue;
      }
      final worldMatch = _overlaps(
        rule.applicability,
        assertion.scope.applicability,
      );
      final worlds = switch ((
        rule.applicability,
        assertion.scope.applicability,
      )) {
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
      final typeMatch = index.matches(
        proposition.subject.record,
        rule.subjectTypes,
        worlds,
      );
      final timeMatch = rule.validity is UnspecifiedValidity
          ? true
          : rules.temporalOverlaps(rule.validity, assertion.validity);
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
      ];
      if (worldMatch == null || typeMatch == null || timeMatch == null) {
        coverage = protocol.Coverage.unsupported;
        message = 'Resolve this claim’s world, subject classification or time before applying its evidence policy.';
      } else if (!categoriesResolved) {
        message = 'Select nonempty qualifying source categories at their exact current published versions.';
      } else if (assertion.basis case SourceAnchorBasis(:final anchor)) {
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
      } else if (assertion.basis is DerivationBasis ||
          assertion.basis is EventEffectBasis) {
        coverage = protocol.Coverage.unsupported;
        message = 'Derived and event-effect source admission requires its evidence evaluator.';
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
