import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'record_browser.dart';

String reviewMethodLabel(EvidenceReviewMethod method) => switch (method) {
  EvidenceReviewMethod.humanReview => 'Human review',
  EvidenceReviewMethod.externalModelReview => 'External writer review',
};

/// Presentation of the authored requirement, never an independent verdict.
final class EvidencePolicySummary {
  EvidencePolicySummary(RuleRecord rule, Map<RecordId, RecordVersion> records)
    : categories = [
        for (final ref in rule.requiredEvidence!.sourceCategories)
          _category(ref, records),
      ],
      review = rule.requiredEvidence!.reviewMethods.isEmpty
          ? 'No interpretation review required by this policy.'
          : 'Required interpretation review: ${rule.requiredEvidence!.reviewMethods.map(reviewMethodLabel).join(' or ')}.',
      scope =
          switch (rule.applicability) {
            UniverseApplicability() => 'Applies across the universe',
            WorldsApplicability(:final worldIds) =>
              'Applies to ${worldIds.length} selected world${worldIds.length == 1 ? '' : 's'}',
            ConditionalApplicability() => 'World applicability is conditional',
            UnspecifiedApplicability() => 'World applicability is unspecified',
          } +
          (rule.subjectTypes.isEmpty ? '' : '; selected subject types') +
          (rule.targetPredicates.isEmpty
              ? '; facts and occurrences'
              : '; selected predicates') +
          (rule.validity is UnspecifiedValidity
              ? '.'
              : '; authored time limits apply.');
  final List<String> categories;
  final String review, scope;
}

String _category(VersionRef ref, Map<RecordId, RecordVersion> records) {
  final row = records[ref.record];
  if (row == null ||
      ref.universe != null && row.identity.universeId != ref.universe ||
      row.payload is! DomainPackRecord) {
    return 'Published source selection (name unavailable)';
  }
  final pack = row.payload as DomainPackRecord;
  final name = pack.key == 'real_world.sources' ? 'Selected sources' : pack.key;
  return row.recordVersionId == ref.version
      ? '$name (${pack.version})'
      : '$name (earlier published selection retained)';
}

final class FindingReviewSummary {
  FindingReviewSummary({
    required Finding finding,
    required UniverseId universe,
    required Map<RecordId, RecordVersion> records,
  }) {
    final material = Records(records: records.values);
    String label(RecordRef ref, String fallback) => dossierReferenceLabel(
      material,
      universe,
      ref,
      unavailableLabel: fallback,
    );
    final policyRow = records[finding.ruleId];
    final policy = policyRow?.identity.universeId == universe
        ? policyRow?.payload
        : null;
    title =
        'Rule check · ${label(RecordRef(record: finding.ruleId), 'Policy name unavailable')}';
    requirement = policy is RuleRecord && policy.requiredEvidence != null
        ? EvidencePolicySummary(policy, records)
        : null;
    claims = [
      if (finding.records.isEmpty)
        'No individual claim is identified by this finding.',
      for (final ref in finding.records) _claim(ref, universe, records, label),
    ];
  }
  late final String title;
  late final EvidencePolicySummary? requirement;
  late final List<String> claims;
}

String _claim(
  RecordRef ref,
  UniverseId universe,
  Map<RecordId, RecordVersion> records,
  String Function(RecordRef, String) label,
) {
  final row = records[ref.record];
  if ((ref.universe != null && ref.universe != universe) ||
      row?.identity.universeId != universe) {
    return 'Affected record (name unavailable)';
  }
  if (row!.payload case AssertionRecord(:final proposition)) {
    final p = (proposition.universe == null || proposition.universe == universe)
        ? records[proposition.record]?.payload
        : null;
    if (p is PropositionRecord) {
      return '${label(p.subject, 'Subject name unavailable')} · ${label(p.predicate, 'Property or relation name unavailable')}';
    }
    return 'Affected fact';
  }
  return label(
    ref,
    row.payload is EventRecord ? 'Affected event' : 'Affected record',
  );
}
