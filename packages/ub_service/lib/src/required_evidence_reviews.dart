import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

/// Completes source findings using the selected assessment already admitted by
/// resolveAssessment. This function never selects, imports or approves a review.
List<protocol.Finding> assessRequiredEvidenceReviews({
  required List<protocol.Finding> sourceFindings,
  required List<RecordVersion> records,
  required protocol.AssessmentReview? review,
}) {
  final index = rules.RecordIndex(records);
  final bound = review?.state;
  final envelope = review?.envelope;
  final selected = review?.selection.selected;
  final body =
      bound is protocol.BoundAssessment &&
          bound.byteVerification == protocol.ByteVerification.verified &&
          selected != null &&
          envelope != null &&
          selected.assessmentId == envelope.assessmentId &&
          selected.digest == envelope.digest &&
          bound.assessmentReference.toWire().toText() ==
              selected.toWire().toText() &&
          bound.selectionGeneration == review!.selection.generation &&
          envelope.body.proposal == review.selection.proposal
      ? envelope.body
      : null;
  return [for (final source in sourceFindings) _review(source, index, body)];
}

protocol.Finding _review(
  protocol.Finding source,
  rules.RecordIndex index,
  protocol.SourceAssessmentV1? body,
) {
  final policy = index.get(source.ruleId)?.payload;
  if (policy is! RuleRecord ||
      policy.requiredEvidence == null ||
      policy.requiredEvidence!.reviewMethods.isEmpty ||
      source.outcome != protocol.EvidenceOutcome.supported) {
    return source;
  }
  protocol.Finding finding(
    String message, {
    bool supported = false,
    bool unsupported = false,
  }) => protocol.Finding(
    ruleId: source.ruleId,
    records: source.records,
    fingerprint: source.fingerprint,
    outcome: supported
        ? protocol.EvidenceOutcome.supported
        : protocol.EvidenceOutcome.notEstablished,
    evidence: source.evidence,
    coverage: unsupported ? protocol.Coverage.unsupported : source.coverage,
    message: message,
  );
  if (body == null ||
      !policy.requiredEvidence!.reviewMethods.any(
        (method) => method.wireName == body.assessor.method.wireName,
      )) {
    return finding(
      'This policy requires a selected, current assessment using an accepted review method.',
    );
  }
  final row = index.get(source.records.single.record)!;
  final assertion = row.payload as AssertionRecord;
  final proposition =
      index.get(assertion.proposition.record)!.payload as PropositionRecord;
  final anchorRef = (assertion.basis as SourceAnchorBasis).anchor;
  final anchor = index.get(anchorRef.record)!.payload as AnchorRecord;
  final locator = anchor.locator;
  if (locator is! ByteRangeLocator) {
    return finding(
      'This review requires a retained source passage with exact byte boundaries.',
      unsupported: true,
    );
  }
  bool exact(protocol.AssessmentVersionRef ref, RecordId id) {
    final record = index.get(id);
    return record != null &&
        ref.universe == record.identity.universeId &&
        ref.record == id &&
        ref.version == record.recordVersionId;
  }

  bool matches(protocol.ClaimMapping mapping) {
    final semantic = mapping.semantic;
    if (semantic is! protocol.ClaimSemanticMapping ||
        !mapping.candidateLinks.any(
          (link) =>
              link.kind != protocol.CandidateLinkKind.historicalEvidence &&
              exact(link.version, row.identity.recordId),
        ) ||
        !exact(mapping.context, assertion.scope.context.record) ||
        !exact(semantic.subject, proposition.subject.record) ||
        !exact(semantic.predicate, proposition.predicate.record) ||
        semantic.polarity != assertion.polarity ||
        proposition.value != null && semantic.value != proposition.value ||
        semantic.roles.length != proposition.roles.length) {
      return false;
    }
    for (var i = 0; i < semantic.roles.length; i++) {
      if (semantic.roles[i].role != proposition.roles[i].role ||
          !exact(
            semantic.roles[i].participant,
            proposition.roles[i].participant.record,
          )) {
        return false;
      }
    }
    final realm = assertion.scope.realm;
    if (realm == null
        ? mapping.realm != null
        : mapping.realm == null || !exact(mapping.realm!, realm.record)) {
      return false;
    }
    return body.declaredInventory.any(
      (item) =>
          mapping.itemIds.contains(item.itemId) &&
          item.range.start <= locator.start &&
          locator.end <= item.range.end &&
          body.sources.any(
            (binding) =>
                binding.key == item.sourceKey &&
                binding.sourceVersion.record == anchor.sourceVersion.record &&
                binding.sourceVersion.version == anchor.sourceVersion.version &&
                (anchor.sourceVersion.universe == null ||
                    binding.sourceVersion.universe ==
                        anchor.sourceVersion.universe),
          ),
    );
  }

  final mappings = body.claimMappings.where(matches).toList();
  final worlds = switch ((
    policy.applicability,
    assertion.scope.applicability,
  )) {
    (
      WorldsApplicability(worldIds: final a),
      WorldsApplicability(worldIds: final b),
    ) =>
      a.where(b.contains).toList(),
    (WorldsApplicability(:final worldIds), _) ||
    (_, WorldsApplicability(:final worldIds)) => worldIds,
    _ => <WorldId?>[null],
  };
  for (final world in worlds) {
    final scoped = mappings
        .where(
          (m) =>
              m.world == null ||
              world != null &&
                  exact(
                    m.world!,
                    RecordId.parse('rec_${world.value.substring(4)}'),
                  ),
        )
        .toList();
    final unresolved = scoped.where(
      (m) =>
          m.judgment != protocol.MappingJudgment.supported ||
          body.unresolved.any((u) => u.itemIds.any(m.itemIds.contains)),
    );
    if (unresolved.any(
      (m) =>
          _overlapsRequiredTime(
            assertion.validity,
            policy.validity,
            m.storyTime,
          ) !=
          false,
    )) {
      return finding(
        'The selected review contains unresolved or opposing interpretation for this required claim.',
      );
    }
    final covered = _coversRequiredTime(
      assertion.validity,
      policy.validity,
      scoped
          // Attributed/hypothetical material does not establish an objective
          // proposition. A recollection may assert the memory/report itself.
          .where(
            (m) =>
                m.judgment == protocol.MappingJudgment.supported &&
                (m.modality == protocol.Modality.asserted ||
                    m.modality == protocol.Modality.negated),
          )
          .map((m) => m.storyTime),
    );
    if (covered != true) {
      return finding(
        'Review the exact claim and cited passage over the world and time required by this policy.',
        unsupported: covered == null,
      );
    }
  }
  return finding(
    'The qualifying source and scoped interpretation review satisfy this claim’s evidence policy.',
    supported: true,
  );
}

typedef _Window = ({CalendarId calendar, BigInt start, BigInt end, bool point});
final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
BigInt? _number(String text) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(text)) return null;
  final n = BigInt.tryParse(text);
  return n == null || n < _min || n > _max ? null : n;
}

_Window? _window(TemporalExpression? expression) {
  if (expression is ExactTime) {
    final n = _number(expression.value);
    return n == null
        ? null
        : (calendar: expression.calendar, start: n, end: n, point: true);
  }
  if (expression is! IntervalTime) return null;
  BigInt? bound(TemporalBound b, bool start) => switch (b) {
    ExactBound(:final value) => _number(value),
    UnboundedBound() => start ? _min : _max,
    _ => null,
  };
  final start = bound(expression.start, true),
      end = bound(expression.end, false);
  return start == null || end == null || start >= end
      ? null
      : (calendar: expression.calendar, start: start, end: end, point: false);
}

_Window? _requiredTime(Validity claim, Validity policy) {
  final a = _window(rules.validityExpression(claim));
  if (a == null || policy is UnspecifiedValidity) return a;
  final b = _window(rules.validityExpression(policy));
  if (b == null || a.calendar != b.calendar) return null;
  final start = a.start > b.start ? a.start : b.start;
  final end = a.end < b.end ? a.end : b.end;
  return (
    calendar: a.calendar,
    start: start,
    end: end,
    point: a.point || b.point,
  );
}

bool? _overlapsRequiredTime(
  Validity claim,
  Validity policy,
  TemporalExpression time,
) {
  final required = _requiredTime(claim, policy), other = _window(time);
  if (required == null || other == null) return null;
  if (required.calendar != other.calendar) return false;
  if (required.point) {
    return other.point
        ? required.start == other.start
        : other.start <= required.start && required.start < other.end;
  }
  if (other.point) {
    return required.start <= other.start && other.start < required.end;
  }
  return required.start < other.end && other.start < required.end;
}

bool? _coversRequiredTime(
  Validity claim,
  Validity policy,
  Iterable<TemporalExpression> evidence,
) {
  final required = _requiredTime(claim, policy);
  if (required == null) return null;
  final windows =
      evidence
          .map(_window)
          .whereType<_Window>()
          .where((w) => w.calendar == required.calendar)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  if (required.point) {
    return windows.any(
      (w) => w.point
          ? w.start == required.start
          : w.start <= required.start && required.start < w.end,
    );
  }
  var covered = required.start;
  for (final w in windows.where((w) => !w.point)) {
    if (w.start > covered) break;
    if (w.end > covered) covered = w.end;
    if (covered >= required.end) return true;
  }
  return false;
}
