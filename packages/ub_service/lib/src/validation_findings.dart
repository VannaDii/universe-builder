import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

/// Rechecks every occurred event's prerequisites in the exact pre-event frame.
/// Candidate expansion, authorization and publication remain caller-owned.
List<protocol.Finding> assessEventPreconditions({
  required List<RecordVersion> candidate,
  required Frame frame,
  void Function()? checkCancelled,
}) {
  final findings = <protocol.Finding>[];
  for (final record in candidate) {
    checkCancelled?.call();
    final event = record.payload;
    if (event is! EventRecord ||
        event.occurrence is! SimpleOccurrence ||
        (event.occurrence as SimpleOccurrence).kind !=
            OccurrenceKind.occurred) {
      continue;
    }
    RecordVersion? action;
    if (event.action case final ref?) {
      for (final r in candidate) {
        if (r.identity.recordId == ref.record) {
          action = r;
          break;
        }
      }
    }
    var context = frame.context;
    if (event.effects.isNotEmpty) {
      context = event.effects.first.scope.context;
    } else if (action?.payload case ActionDefinitionRecord definition) {
      context = definition.scope.context;
    }
    final eventFrame = Frame(
      universe: frame.universe,
      continuity: frame.continuity,
      revision: frame.revision,
      context: context,
      time: AtEventFrameTime(
        RecordRef(universe: frame.universe, record: record.identity.recordId),
        EventTimeSide.before,
      ),
      perspective: frame.perspective,
      readerScene: frame.readerScene,
      personalSequence: frame.personalSequence,
    );
    for (var position = 0; position < event.preconditions.length; position++) {
      final (evidence, complete) = rules.evaluateExpression(
        event.preconditions[position],
        rules.EvaluationContext(
          frame: eventFrame,
          baseSnapshot: candidate,
          worldScope: event.worlds.map(
            (w) => RecordId.parse(
              'rec_${w.value.substring(WorldId.prefix.length)}',
            ),
          ),
        ),
      );
      if (!complete || evidence.outcome != rules.EvidenceOutcome.supported) {
        findings.add(
          protocol.Finding(
            message:
                'Action prerequisite ${position + 1} must be supported before this event. Retrieve the event and its precondition references; repair missing/conflicting evidence or the authored event time.',
            fingerprint: const FindingFingerprint(''),
            ruleId: record.identity.recordId,
            outcome: protocol.EvidenceOutcome.fromName(evidence.outcome.label),
            evidence: [
              ...evidence.allSources,
              record.recordVersionId,
              if (action != null) action.recordVersionId,
            ],
            coverage: complete
                ? protocol.Coverage.complete
                : protocol.Coverage.unsupported,
          ),
        );
      }
    }
  }
  return findings;
}

/// Binds findings after all candidate checks, preserving authored fingerprints.
List<protocol.Finding> finalizeCandidateFindings({
  required List<protocol.Finding> findings,
  required List<RecordVersion> candidate,
  required Frame frame,
  required String digest,
  required String evaluator,
}) => findings
    .map(
      (finding) => protocol.Finding(
        message: finding.message,
        records: finding.records.isNotEmpty
            ? finding.records
            : candidate
                  .where((r) => finding.evidence.contains(r.recordVersionId))
                  .map(
                    (r) => RecordRef(
                      universe: r.identity.universeId,
                      record: r.identity.recordId,
                    ),
                  ),
        fingerprint: finding.fingerprint.value.isNotEmpty
            ? finding.fingerprint
            : FindingFingerprint(
                canonicalDigest(
                  CanonicalArray([
                    frame.toWire(),
                    CanonicalString(digest),
                    CanonicalString(evaluator),
                    CanonicalString(finding.ruleId.value),
                    CanonicalString(finding.outcome.wireName),
                    CanonicalArray(
                      finding.evidence.map((v) => CanonicalString(v.value)),
                    ),
                  ]),
                ),
              ),
        ruleId: finding.ruleId,
        outcome: finding.outcome,
        evidence: finding.evidence,
        coverage: finding.coverage,
      ),
    )
    .toList();
