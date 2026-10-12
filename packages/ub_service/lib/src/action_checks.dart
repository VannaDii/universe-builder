import 'package:ub_contracts/ub_contracts.dart'
    show InvalidArgumentError, EvaluationLimitReachedError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

InvalidArgumentError _invalid(String field, String message) =>
    InvalidArgumentError(field: field, message: message);
String _outcome(EvidenceOutcome e) => switch (e) {
  EvidenceOutcome.supported => 'Supported',
  EvidenceOutcome.refuted => 'Refuted',
  EvidenceOutcome.conflicting => 'Conflicting',
  EvidenceOutcome.notEstablished => 'NotEstablished',
};

/// Mandatory owner-bound action attributes on the exact candidate. Historical
/// actionless events remain readable; changed events must declare their action.
/// This validates factual requirements, not permissions or publication approval.
void validateActionRequirements({
  required List<RecordVersion> records,
  required Set<RecordId> changed,
  required Frame frame,
}) {
  final byId = {for (final r in records) r.identity.recordId: r};
  final index = EvaluationIndex(records);
  var remaining = 1000000;
  void charge(int n) {
    remaining -= n;
    if (remaining < 0) {
      throw const EvaluationLimitReachedError(
        message: 'Action attribute evaluation exceeded its work budget',
      );
    }
  }

  charge(records.length);
  for (final record in records) {
    charge(1);
    final event = record.payload;
    if (event is! EventRecord) {
      continue;
    }
    final reference = event.action;
    if (reference == null) {
      if (changed.contains(record.identity.recordId)) {
        throw _invalid(
          'event.action',
          'new or revised events must name a declared action',
        );
      }
      continue;
    }
    final declaration = byId[reference.record];
    final action = declaration?.payload;
    if (declaration == null ||
        reference.universe != declaration.identity.universeId ||
        action is! ActionDefinitionRecord) {
      throw _invalid(
        'event.action',
        'action must reference a declared action definition',
      );
    }
    final eventFrame = Frame(
      universe: frame.universe,
      continuity: frame.continuity,
      revision: frame.revision,
      context: event.effects.firstOrNull?.scope.context ?? action.scope.context,
      time: AtEventFrameTime(
        RecordRef(universe: frame.universe, record: record.identity.recordId),
        EventTimeSide.before,
      ),
      perspective: frame.perspective,
      readerScene: frame.readerScene,
      personalSequence: frame.personalSequence,
    );
    final applicability = action.scope.applicability;
    if (eventFrame.context != action.scope.context ||
        applicability is! UniverseApplicability &&
            !(applicability is WorldsApplicability &&
                event.worlds.isNotEmpty &&
                event.worlds.every(applicability.worldIds.contains))) {
      throw _invalid(
        'event.action',
        "event must stay within its action's declared context/world scope",
      );
    }
    for (final requirement in action.requirements) {
      final participants = event.participants
          .where((p) => p.role == requirement.role)
          .toList();
      charge(event.participants.length);
      if (participants.length != 1 ||
          byId[participants.first.record.record]?.payload is! EntityRecord) {
        throw _invalid(
          'event.action.requirements',
          'each required role must identify exactly one owning entity',
        );
      }
    }
    if (event.occurrence is! SimpleOccurrence ||
        (event.occurrence as SimpleOccurrence).kind !=
            OccurrenceKind.occurred) {
      continue;
    }
    if (action.validity is! UnspecifiedValidity &&
        eventApplies(action.validity, eventFrame.time, records) != true) {
      throw _invalid(
        'event.action',
        'action is not explicitly active before this event',
      );
    }
    final worlds = event.worlds.isEmpty
        ? <List<RecordId>>[[]]
        : [
            for (final w in event.worlds)
              [
                RecordId.parse(
                  'rec_${w.value.substring(WorldId.prefix.length)}',
                ),
              ],
          ];
    for (final requirement in action.requirements) {
      final owner = event.participants
          .firstWhere((p) => p.role == requirement.role)
          .record;
      final property = byId[requirement.predicate.record]?.payload;
      if (property is! PropertyRecord) {
        throw _invalid(
          'event.action.requirements',
          'required attribute property is unavailable',
        );
      }
      final expression = ClaimExpr(
        subject: RecordOperand(owner),
        predicate: '${property.namespace}:${property.key}',
        roles: [],
        value: ValueOperand(requirement.value),
        polarity: Polarity.support,
      );
      for (final world in worlds) {
        charge(records.length);
        final (evidence, complete) = evaluateExpression(
          expression,
          EvaluationContext(
            frame: eventFrame,
            baseSnapshot: records,
            index: index,
            worldScope: world,
          ),
        );
        if (!complete || evidence.outcome != EvidenceOutcome.supported) {
          throw _invalid(
            'event.action.requirements',
            'required attribute ${property.namespace}:${property.key} for role ${requirement.role} on entity ${owner.record.value} in event ${record.identity.recordId.value} is not established before the event (outcome: ${_outcome(evidence.outcome)}, complete: $complete); evidence may be missing, muted, conflicting, expired or unsupported',
          );
        }
      }
    }
  }
}
