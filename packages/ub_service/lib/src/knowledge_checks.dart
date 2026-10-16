import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

import 'communication_checks.dart';

const knowledgeAcquisitionCapability = 'knowledge.acquisition.v1';

void validateKnowledgeRule(RuleRecord rule) {
  InvalidArgumentError invalid(String message) =>
      InvalidArgumentError(field: 'knowledgePolicy', message: message);
  if (rule.knowledgePolicy == null) {
    if (rule.capabilities.contains(knowledgeAcquisitionCapability)) {
      throw invalid('knowledge capability requires an explicit context policy');
    }
    return;
  }
  if (!rule.executable ||
      rule.kind != RuleKind.physicalConstraint ||
      rule.commitPolicy != CommitPolicy.alwaysBlock ||
      rule.applicability is! UniverseApplicability ||
      rule.validity is! UnspecifiedValidity ||
      rule.subjectTypes.isNotEmpty ||
      rule.targetPredicates.isNotEmpty ||
      rule.expression is! LiteralExpr ||
      !(rule.expression as LiteralExpr).value ||
      rule.capabilities.length != 1 ||
      rule.capabilities.single != knowledgeAcquisitionCapability ||
      rule.knowledgeBoundary != null ||
      rule.channelChronology != null) {
    throw invalid(
      'knowledge needs an executable universe-wide physical constraint with always_block, unspecified validity, literal true and only its capability',
    );
  }
}

BigInt? _coordinate(String value) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) return null;
  final n = BigInt.tryParse(value);
  return n != null && n >= -(BigInt.one << 127) && n < (BigInt.one << 127)
      ? n
      : null;
}

bool? _beforeOrAt(TemporalExpression a, TemporalExpression b) {
  if (a is! ExactTime || b is! ExactTime || a.calendar != b.calendar) {
    return null;
  }
  final x = _coordinate(a.value), y = _coordinate(b.value);
  return x == null || y == null ? null : x <= y;
}

TemporalExpression? _beginning(Validity validity) => switch (validity) {
  InstantValidity(:final at) => at,
  CalendarIntervalValidity(:final calendar, start: ExactBound(:final value)) =>
    ExactTime(calendar, value),
  _ => null,
};

(bool?, String) _check(
  List<RecordVersion> records,
  EpistemicAttitudeRecord a,
  KnowledgePolicy policy,
  Frame frame,
  List<RecordVersionId> evidence,
  Set<RecordId> excludedRules,
) {
  RecordVersion? find(RecordRef reference) {
    try {
      reference.resolveNamespace(frame.universe);
    } on FormatException {
      return null;
    }
    for (final row in records) {
      if (row.identity.recordId == reference.record) return row;
    }
    return null;
  }

  var reason =
      'Knowledge requires explicit acquisition time, truth context and acquisition basis.';
  final acquisition = a.acquisition;
  if (acquisition == null) return (null, reason);
  reason =
      'Retrieve the claimed proposition and its represented truth context.';
  final prop = find(a.proposition);
  if (prop == null) return (null, reason);
  evidence.add(prop.recordVersionId);
  final p = prop.payload;
  if (p is! PropositionRecord) return (null, reason);
  reason = 'The acquisition truth context must match both the proposition and the authored knowledge policy.';
  if (acquisition.truthContext != p.context ||
      acquisition.truthContext != policy.context) {
    return (false, reason);
  }
  final context = find(acquisition.truthContext);
  if (context == null) return (null, reason);
  evidence.add(context.recordVersionId);
  if (context.payload is! RepresentedContextRecord) return (null, reason);
  reason = 'Acquisition must be at or before knowledge onset on the same exact authored clock; repair acquisition time or knowledge validity.';
  final onset = _beginning(a.validity);
  final ordered = onset == null ? null : _beforeOrAt(acquisition.time, onset);
  if (ordered != true) return (ordered, reason);
  reason = 'The acquisition basis must match the authored author-established or justified policy.';
  final basis = acquisition.basis;
  if (policy.mode == KnowledgeMode.authorEstablished) {
    if (basis is! AuthorEstablishedKnowledge) return (false, reason);
    return (a.basis is AuthorDecisionBasis ? true : null, reason);
  }
  if (basis is AuthorEstablishedKnowledge) return (false, reason);
  final receipt = basis as CommunicationKnowledge;
  final message = find(receipt.communication);
  if (message == null) return (null, reason);
  evidence.add(message.recordVersionId);
  final c = message.payload;
  if (c is! CommunicationRecord) return (null, reason);
  reason = 'The communication needs an actual recipient and an authored receipt time.';
  if (c.actualRecipients.isEmpty) return (null, reason);
  reason =
      'The knowledge holder must be an actual recipient of the communication.';
  if (!c.actualRecipients.contains(a.holder)) return (false, reason);
  reason = 'Supply an explicit interpretation referencing the claimed proposition contained in the communication.';
  final interpreted = receipt.interpretation;
  if (interpreted == null) return (null, reason);
  if (interpreted != a.proposition || !c.content.contains(interpreted)) {
    return (false, reason);
  }
  reason = 'Distorted communication does not establish interpreted knowledge in this bounded receipt lane.';
  if (c.distorted) return (null, reason);
  reason = 'Receipt must be at or before acquisition on the same exact authored clock; repair receipt or acquisition time.';
  final received = c.receivedAt;
  final receiptOrder = received == null
      ? null
      : _beforeOrAt(received, acquisition.time);
  if (receiptOrder != true) return (receiptOrder, reason);
  reason = 'Retrieve the matching channel chronology contract and repair its missing or violated transmission timing.';
  final chronologyRecords = <RecordVersion>[
    for (final r in records)
      if (!excludedRules.contains(r.identity.recordId) &&
          r.payload is RuleRecord &&
          (r.payload as RuleRecord).channelChronology != null)
        r,
  ];
  if (chronologyRecords.isEmpty) return (null, reason);
  final chronology = assessCommunicationChronology([
    ...chronologyRecords,
    message,
  ]);
  for (final f in chronology) {
    evidence.addAll(f.evidence);
  }
  if (chronology.any((f) => f.coverage != Coverage.complete)) {
    return (null, reason);
  }
  if (chronology.any((f) => f.outcome != EvidenceOutcome.supported)) {
    return (false, reason);
  }
  reason = 'Justified acquisition requires a particular proposition with a supported definition.';
  if (p.quantification != Quantification.particular) return (null, reason);
  final definition = find(p.predicate);
  if (definition == null) return (null, reason);
  evidence.add(definition.recordVersionId);
  final predicate = switch (definition.payload) {
    PropertyRecord(:final namespace, :final key) => '$namespace:$key',
    RelationRecord(:final namespace, :final key) => '$namespace:$key',
    _ => null,
  };
  if (predicate == null) return (null, reason);
  final truthFrame = Frame(
    universe: frame.universe,
    continuity: frame.continuity,
    revision: frame.revision,
    context: acquisition.truthContext,
    time: AtFrameTime(acquisition.time),
    perspective: frame.perspective,
    readerScene: frame.readerScene,
    personalSequence: frame.personalSequence,
  );
  final worldScope = <RecordId>[];
  if (acquisition.world case final reference?) {
    final world = find(reference);
    if (world == null) return (null, reason);
    evidence.add(world.recordVersionId);
    if (world.payload is! WorldRecord) return (null, reason);
    worldScope.add(world.identity.recordId);
  }
  final expr = ClaimExpr(
    subject: RecordOperand(p.subject),
    predicate: predicate,
    roles: p.roles.map((r) => ExprRole(r.role, RecordOperand(r.participant))),
    value: p.value == null ? null : ValueOperand(p.value!),
    polarity: Polarity.support,
  );
  reason = 'The claimed proposition needs unopposed supporting truth in its acquisition context, world and time. Retrieve its assertions; repair acquisition time or the missing/conflicting truth evidence.';
  final (truth, complete) = rules.evaluateExpression(
    expr,
    rules.EvaluationContext(
      frame: truthFrame,
      baseSnapshot: records,
      worldScope: worldScope,
    ),
  );
  evidence.addAll(truth.allSources);
  if (!complete) return (null, reason);
  return (
    switch (truth.outcome) {
      rules.EvidenceOutcome.supported => true,
      rules.EvidenceOutcome.refuted ||
      rules.EvidenceOutcome.conflicting => false,
      rules.EvidenceOutcome.notEstablished => null,
    },
    reason,
  );
}

/// Reassess every declared knowledge fact against the candidate, including
/// unchanged attitudes whose receipt, truth or policy has been corrected.
List<Finding> assessKnowledgeAcquisition(
  List<RecordVersion> records,
  Frame frame, {
  Set<RecordId> excludedRules = const {},
}) {
  final policies = <(RecordVersion, KnowledgePolicy)>[
    for (final r in records)
      if (!excludedRules.contains(r.identity.recordId) &&
          r.payload is RuleRecord &&
          (r.payload as RuleRecord).knowledgePolicy != null)
        (r, (r.payload as RuleRecord).knowledgePolicy!),
  ];
  final findings = <Finding>[];
  for (final row in records) {
    final a = row.payload;
    if (a is! EpistemicAttitudeRecord ||
        a.attitude != EpistemicAttitudeKind.knows) {
      continue;
    }
    if (policies.isEmpty && a.acquisition == null) continue;
    RecordRef? context;
    for (final r in records) {
      if (r.identity.recordId == a.proposition.record &&
          r.payload is PropositionRecord) {
        context = (r.payload as PropositionRecord).context;
        break;
      }
    }
    final matching = policies.where((p) => p.$2.context == context).toList();
    if (matching.isEmpty && a.acquisition == null) continue;
    if (matching.isEmpty) {
      findings.add(
        Finding(
          message: 'No matching knowledge policy covers this explicit acquisition. Retrieve or author the policy for the proposition truth context.',
          fingerprint: FindingFingerprint(''),
          ruleId: row.identity.recordId,
          outcome: EvidenceOutcome.notEstablished,
          evidence: [row.recordVersionId],
          coverage: Coverage.unsupported,
        ),
      );
    }
    for (final (rule, policy) in matching) {
      final evidence = [rule.recordVersionId, row.recordVersionId];
      final (pass, reason) = _check(
        records,
        a,
        policy,
        frame,
        evidence,
        excludedRules,
      );
      final unique = evidence.toSet().toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      findings.add(
        Finding(
          message: pass == true
              ? 'Declared knowledge acquisition is supported.'
              : reason,
          fingerprint: FindingFingerprint(''),
          ruleId: rule.identity.recordId,
          outcome: pass == null
              ? EvidenceOutcome.notEstablished
              : pass
              ? EvidenceOutcome.supported
              : EvidenceOutcome.refuted,
          evidence: unique,
          coverage: pass == null ? Coverage.unsupported : Coverage.complete,
        ),
      );
    }
  }
  return List.unmodifiable(findings);
}
