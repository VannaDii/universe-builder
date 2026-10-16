import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;
import 'package:ub_store/ub_store.dart' show Assignment;

import 'action_checks.dart';
import 'boundary_checks.dart';
import 'candidate_checks.dart';
import 'cardinality_checks.dart';
import 'communication_checks.dart';
import 'consequence_execution.dart';
import 'definition_registry.dart';
import 'knowledge_boundaries.dart';
import 'knowledge_checks.dart';
import 'opposing_diagnostics.dart';
import 'proposal_authorization.dart';
import 'resource_checks.dart';
import 'required_evidence_checks.dart';
import 'required_evidence_reviews.dart';
import 'fictional_departures.dart';
import 'rule_checks.dart';
import 'structural_checks.dart';
import 'validation_findings.dart';

const candidateEvaluatorVersion =
    'finite-policy-v22-root-required-for-publication';

/// Candidate assessment only. Approval, source staging, snapshot selection and
/// durable publication remain the responsibility of the author workflow.
final class CandidateValidationResult {
  const CandidateValidationResult({
    required this.validation,
    required this.admissible,
  });
  final protocol.Validation validation;
  final bool admissible;
}

protocol.EvidenceOutcome _outcome(rules.EvidenceOutcome outcome) =>
    switch (outcome) {
      rules.EvidenceOutcome.supported => protocol.EvidenceOutcome.supported,
      rules.EvidenceOutcome.refuted => protocol.EvidenceOutcome.refuted,
      rules.EvidenceOutcome.conflicting => protocol.EvidenceOutcome.conflicting,
      rules.EvidenceOutcome.notEstablished =>
        protocol.EvidenceOutcome.notEstablished,
    };

/// Evaluates an already-previewed complete candidate against its pinned base.
/// Author origin and installation author must come from trusted workflow state,
/// never from caller-supplied permission claims or an ordinary approval.
/// Every universe candidate must retain a valid selected root policy.
CandidateValidationResult evaluateCandidate({
  required List<RecordVersion> candidate,
  required List<RecordVersion> base,
  required List<Assignment> changes,
  required Frame frame,
  required String digest,
  required WriteFootprint footprint,
  required bool authorOrigin,
  required ProfileId approvalAuthor,
  protocol.AssessmentReview? selectedAssessment,
  List<RecordVersion> evidenceCategories = const [],
  void Function()? checkCancelled,
}) {
  final definitions = DefinitionRegistry();
  for (final r in candidate) {
    checkCancelled?.call();
    definitions.add(r);
  }
  definitions.validate();
  late final Set<RecordId> excludedRules;
  final activatedRules = <RecordId>{};
  try {
    final policy = UniversePolicySelection.fromRecords(
      frame.universe,
      candidate,
    );
    excludedRules = policy.inactiveRuleIds;
    final priorPolicy = UniversePolicySelection.fromRecords(
      frame.universe,
      base,
    );
    final previous = priorPolicy.rules.map((r) => r.identity.recordId).toSet();
    final managed = {
      ...policy.inactiveRuleIds,
      ...policy.rules.map((r) => r.identity.recordId),
    };
    final detached = {
      ...priorPolicy.inactiveRuleIds,
      ...previous,
    }.difference(managed);
    if (detached.isNotEmpty &&
        candidate.any((row) => detached.contains(row.identity.recordId))) {
      throw const FormatException(
        'A policy rule cannot become independent by removing its membership; '
        'keep it in a defined policy or retire the rule with its definition',
      );
    }
    activatedRules.addAll(
      policy.rules
          .map((r) => r.identity.recordId)
          .where((id) => !previous.contains(id)),
    );
  } on FormatException catch (error) {
    throw protocol.InvalidArgumentError(
      field: 'operations',
      message: error.message,
    );
  }
  validateStructuralCandidate(
    candidate,
    evidenceCategories: evidenceCategories,
  );
  final changedIds = changes.map((c) => c.recordId).toSet();
  validateActionRequirements(
    records: candidate,
    changed: changedIds,
    frame: frame,
  );
  final proposed = [
    for (final c in changes)
      if (c.next != null) RecordVersion.fromWire(c.next!.toCanonical()),
  ];
  for (final r in proposed) {
    final payload = r.payload;
    if (payload is EpistemicAttitudeRecord &&
        !authorOrigin &&
        payload.attitude == EpistemicAttitudeKind.knows &&
        payload.acquisition?.basis is AuthorEstablishedKnowledge) {
      throw const protocol.PolicyDeniedError(
        message: 'Author-established knowledge requires actual author-origin establishment; inline evidence or ordinary approval cannot manufacture it.',
      );
    }
    if (payload is IssueDecisionRecord &&
        (!authorOrigin ||
            payload.principal.value !=
                approvalAuthor.value.replaceFirst('prf_', 'prn_'))) {
      throw const protocol.PolicyDeniedError(
        message: 'issue decisions must be authored by the installation author',
      );
    }
    final context = switch (payload) {
      AssertionRecord(:final scope) => scope.context,
      PropositionRecord(:final context) => context,
      _ => null,
    };
    if (context != null && context != frame.context) {
      throw const protocol.InvalidArgumentError(
        field: 'operations',
        message: 'asserted changes must use the proposal represented context',
      );
    }
  }
  final findings = assessEventPreconditions(
    candidate: candidate,
    frame: frame,
    checkCancelled: checkCancelled,
  );
  final index = rules.EvaluationIndex(candidate);
  final unsupported = validateActionConsequences(
    records: candidate,
    base: base,
    changed: changedIds,
    frame: frame,
  );
  var admissible = findings.isEmpty;
  final fictionalExceptions = candidate
      .where(
        (r) =>
            r.payload is ExceptionRecord &&
            (r.payload as ExceptionRecord).fictionalDeparture,
      )
      .toList();
  final departureIndex = fictionalExceptions.isEmpty
      ? null
      : rules.RecordIndex(candidate);
  for (final finding in assessRequiredEvidenceReviews(
    sourceFindings: assessRequiredEvidenceSources(
      records: candidate,
      base: base,
      changed: {...changedIds, ...activatedRules},
      categories: evidenceCategories,
      excludedRules: excludedRules,
    ),
    records: candidate,
    review: selectedAssessment,
  )) {
    final departure = departureIndex == null
        ? null
        : fictionalDepartureForClaim(
            finding,
            candidate,
            departureIndex,
            fictionalExceptions,
          );
    if (finding.outcome != protocol.EvidenceOutcome.supported &&
        departure == null) {
      admissible = false;
    }
    if (finding.coverage != protocol.Coverage.complete) {
      unsupported.add('required_evidence:${finding.ruleId.value}');
    }
    findings.add(withFictionalDeparture(finding, [?departure], departureIndex));
  }
  for (final f in findings) {
    if (f.coverage != protocol.Coverage.complete) {
      unsupported.add('event.preconditions:${f.ruleId.value}');
    }
  }
  final declared = <(List<protocol.Finding>, String)>[
    (
      assessKnowledgeBoundaries(candidate, excludedRules: excludedRules),
      'knowledge.boundaries',
    ),
    (
      assessRelationCardinality(candidate, excludedRules: excludedRules),
      'relations.cardinality',
    ),
    (
      assessCommunicationChronology(candidate, excludedRules: excludedRules),
      'communications.chronology',
    ),
    (
      assessKnowledgeAcquisition(
        candidate,
        frame,
        excludedRules: excludedRules,
      ),
      'knowledge.acquisition',
    ),
  ];
  for (final (lane, capability) in declared) {
    for (final f in lane) {
      if (f.outcome != protocol.EvidenceOutcome.supported) admissible = false;
      if (f.coverage != protocol.Coverage.complete) {
        unsupported.add('$capability:${f.ruleId.value}');
      }
      findings.add(f);
    }
  }
  for (final gap in assessResourceAccounting(
    candidate,
    frame,
    excludedRules: excludedRules,
  )) {
    if (gap.acceptance == null) admissible = false;
    findings.add(
      protocol.Finding(
        message: 'The resource count changed without an accounted event or coherent correction. Exact author acceptance preserves the count with its arrival unexplained.',
        records: [
          RecordRef(universe: frame.universe, record: gap.proposition),
          RecordRef(universe: frame.universe, record: gap.assertion),
        ],
        fingerprint: gap.fingerprint,
        ruleId: gap.rule,
        outcome: protocol.EvidenceOutcome.notEstablished,
        evidence: gap.evidence,
        coverage: protocol.Coverage.complete,
      ),
    );
  }
  final allWorlds = [
    for (final r in candidate)
      if (r.payload is WorldRecord) r.identity.recordId,
  ];
  final worlds = footprint.shared
      ? allWorlds
      : footprint.worlds
            .map((w) => RecordId.parse('rec_${w.value.substring(4)}'))
            .toList();
  // New and old versions both participate, including removed evidence.
  final boundaryChanges = [
    for (final c in changes) ...[
      if (c.next != null) RecordVersion.fromWire(c.next!.toCanonical()),
      for (final r in base)
        if (r.identity.recordId == c.recordId) r,
    ],
  ];
  protocol.Finding finding(RecordVersion r, CheckedRule result) =>
      withFictionalDeparture(
        protocol.Finding(
          records: [],
          fingerprint: const FindingFingerprint(''),
          ruleId: r.identity.recordId,
          outcome: _outcome(result.evidence.outcome),
          evidence: result.evidence.allSources,
          coverage: result.complete
              ? protocol.Coverage.complete
              : protocol.Coverage.unsupported,
        ),
        result.fictionalDepartures,
        departureIndex,
      );
  for (final r in candidate) {
    checkCancelled?.call();
    switch (r.payload) {
      case RuleRecord rule:
        if (excludedRules.contains(r.identity.recordId)) {
          continue;
        }
        if (rule.knowledgeBoundary != null ||
            rule.channelChronology != null ||
            rule.knowledgePolicy != null ||
            rule.relationCardinality != null) {
          continue;
        }
        if (!rule.expression.usesOpposingEvidence && !footprint.shared) {
          final scope = rule.applicability;
          if (scope is WorldsApplicability &&
              scope.worldIds.every((w) => !footprint.worlds.contains(w))) {
            continue;
          }
        }
        final result = evaluateCandidateRule(
          index: index,
          record: r,
          records: candidate,
          base: frame,
          footprint: rule.expression.usesOpposingEvidence ? allWorlds : worlds,
        );
        if (!result.complete) {
          unsupported.add('rule:${r.identity.recordId.value}');
        }
        if ((rule.commitPolicy == CommitPolicy.alwaysBlock ||
                rule.commitPolicy == CommitPolicy.blockUnlessException ||
                rule.commitPolicy == CommitPolicy.scopeEnforced) &&
            !result.accepted) {
          admissible = false;
        }
        findings.add(finding(r, result));
      case BoundaryRecord():
        final result = evaluateCandidateBoundary(
          target: r,
          changes: boundaryChanges,
          records: candidate,
          historical: base,
          frame: frame,
          author: authorOrigin,
        );
        if (!result.accepted) admissible = false;
        if (!result.complete) {
          unsupported.add('boundary:${r.identity.recordId.value}');
        }
        findings.add(finding(r, result));
      case ExceptionRecord e:
        if (!validException(e, candidate)) {
          unsupported.add(
            'exception:${r.identity.recordId.value}: stale rule version, unsupported scope or missing acceptance',
          );
          admissible = false;
        }
      default:
        break;
    }
  }
  checkCancelled?.call();
  final (scalar, scalarGaps) = scalarConflicts(candidate);
  final definitionGaps = validateDefinitionApplicability(candidate);
  final (closed, unresolved) = completenessConflicts(candidate);
  final conflicts = [...scalar, ...closed];
  final gaps = [...scalarGaps, ...definitionGaps, ...unresolved];
  if (conflicts.isNotEmpty || gaps.isNotEmpty) admissible = false;
  unsupported.addAll(gaps);
  findings.addAll(
    conflicts.map(
      (c) => protocol.Finding(
        records: [],
        fingerprint: const FindingFingerprint(''),
        ruleId: c.$1,
        outcome: protocol.EvidenceOutcome.conflicting,
        evidence: c.$2,
        coverage: protocol.Coverage.complete,
      ),
    ),
  );
  final bound = finalizeCandidateFindings(
    findings: findings,
    candidate: candidate,
    frame: frame,
    digest: digest,
    evaluator: candidateEvaluatorVersion,
  );
  final opposing = buildOpposingDiagnostics(
    records: candidate,
    frame: frame,
    digest: digest,
    evaluator: candidateEvaluatorVersion,
    unsupported: unsupported,
  );
  return CandidateValidationResult(
    validation: protocol.Validation(
      runId: ValidationRunId.generate(),
      coverage: unsupported.isEmpty
          ? protocol.Coverage.complete
          : protocol.Coverage.partial,
      findings: bound,
      opposingEvidence: opposing,
      unsupportedCapabilities: unsupported,
      inputDigest: digest,
      evaluatorVersion: candidateEvaluatorVersion,
    ),
    admissible: admissible,
  );
}
