import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show compareValues, temporalOverlaps;

const knowledgeBoundaryCapability = 'knowledge.boundaries.v1';
InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'knowledgeBoundary', message: message);
final _integer = RegExp(r'^[+-]?[0-9]+$');
final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
BigInt? _ticks(String value) {
  if (!_integer.hasMatch(value)) return null;
  final n = BigInt.tryParse(value);
  return n != null && n >= _min && n <= _max ? n : null;
}

RecordPayload? _find(List<RecordVersion> rows, RecordId id) {
  for (final r in rows) {
    if (r.identity.recordId == id) return r.payload;
  }
  return null;
}

void validateKnowledgeBoundaryRule(RuleRecord rule, List<RecordVersion> rows) {
  final b = rule.knowledgeBoundary;
  if (b == null) {
    if (rule.capabilities.contains(knowledgeBoundaryCapability)) {
      throw _invalid('boundary capability requires an explicit boundary');
    }
    return;
  }
  if (!rule.executable ||
      rule.kind != RuleKind.physicalConstraint ||
      rule.commitPolicy != CommitPolicy.alwaysBlock ||
      rule.expression is! LiteralExpr ||
      !(rule.expression as LiteralExpr).value ||
      rule.capabilities.length != 1 ||
      rule.capabilities.single != knowledgeBoundaryCapability ||
      rule.targetPredicates.isNotEmpty ||
      rule.subjectTypes.isNotEmpty ||
      rule.knowledgePolicy != null ||
      rule.channelChronology != null ||
      rule.relationCardinality != null ||
      rule.applicability is! UniverseApplicability &&
          rule.applicability is! WorldsApplicability ||
      rule.validity is! CalendarIntervalValidity) {
    throw _invalid(
      'requires a separate executable always_block physical rule, explicit world applicability and calendar interval, literal true and only its boundary capability',
    );
  }
  final v = rule.validity as CalendarIntervalValidity;
  final start = v.start is ExactBound
      ? _ticks((v.start as ExactBound).value)
      : null;
  final end = v.end is ExactBound ? _ticks((v.end as ExactBound).value) : null;
  if (start == null ||
      end == null ||
      start > end ||
      rule.applicability is WorldsApplicability &&
          (rule.applicability as WorldsApplicability).worldIds.isEmpty) {
    throw _invalid(
      'explicit finite exact start/end and nonempty authored world scope required',
    );
  }
  if (rows.isNotEmpty) {
    for (final reference in [b.holder, b.proposition, b.context]) {
      reference.resolveNamespace(rows.first.identity.universeId);
    }
  }
  if (rule.applicability case WorldsApplicability(:final worldIds)) {
    for (final w in worldIds) {
      if (_find(
        rows,
        RecordId.parse('rec_${w.value.substring(WorldId.prefix.length)}'),
      ) is! WorldRecord) {
        throw _invalid('boundary worlds must resolve to authored worlds');
      }
    }
  }
  final prop = _find(rows, b.proposition.record);
  if (_find(rows, b.holder.record) is! EntityRecord ||
      _find(rows, b.context.record) is! RepresentedContextRecord ||
      prop is! PropositionRecord ||
      prop.context != b.context) {
    throw _invalid(
      'holder, matching proposition and represented context must resolve',
    );
  }
}

bool _claimEqual(
  PropositionRecord a,
  PropositionRecord b,
  List<RecordVersion> rows,
) {
  (String, String)? predicate(PropositionRecord p) =>
      switch (_find(rows, p.predicate.record)) {
        PropertyRecord(:final namespace, :final key) ||
        RelationRecord(:final namespace, :final key) => (namespace, key),
        _ => null,
      };
  final value =
      a.value == null && b.value == null ||
      a.value != null &&
          b.value != null &&
          (a.value == b.value ||
              compareValues(a.value!, Comparator.eq, b.value!) == true);
  return a.context == b.context &&
      a.subject == b.subject &&
      a.roles.length == b.roles.length &&
      a.roles.every(
        (r) => b.roles.any(
          (s) => r.role == s.role && r.participant == s.participant,
        ),
      ) &&
      value &&
      a.quantification == b.quantification &&
      (a.predicate == b.predicate ||
          predicate(a) != null && predicate(a) == predicate(b));
}

/// Absence of a knowing attitude stays unknown. Authored prohibitions report
/// only overlapping knowledge facts; ordinary approval cannot waive them.
List<Finding> assessKnowledgeBoundaries(List<RecordVersion> rows) {
  final out = <Finding>[];
  for (final ruleRow in rows) {
    final rule = ruleRow.payload;
    if (rule is! RuleRecord || rule.knowledgeBoundary == null) continue;
    final b = rule.knowledgeBoundary!, prop = _find(rows, b.proposition.record);
    if (rule.validity case CalendarIntervalValidity(
      start: ExactBound(value: final a),
      end: ExactBound(value: final z),
    )) {
      if (_ticks(a) == _ticks(z)) continue;
    }
    for (final row in rows) {
      final a = row.payload;
      if (a is! EpistemicAttitudeRecord ||
          a.attitude != EpistemicAttitudeKind.knows ||
          a.holder != b.holder) {
        continue;
      }
      final other = _find(rows, a.proposition.record);
      if (prop is! PropositionRecord ||
          other is! PropositionRecord ||
          !_claimEqual(prop, other, rows)) {
        continue;
      }
      if (a.acquisition != null && a.acquisition!.truthContext != b.context) {
        continue;
      }
      final acquisition = a.acquisition;
      final bool? world;
      switch (rule.applicability) {
        case UniverseApplicability():
          world = true;
        case WorldsApplicability(:final worldIds):
          if (acquisition == null) {
            world = null;
          } else if (acquisition.world == null) {
            world = true;
          } else {
            world = worldIds.contains(
              WorldId.parse(
                'wld_${acquisition.world!.record.value.substring(RecordId.prefix.length)}',
              ),
            );
          }
        default:
          world = null;
      }
      final overlap = temporalOverlaps(a.validity, rule.validity);
      if (world == false || overlap == false) continue;
      final definite = world == true && overlap == true;
      out.add(
        Finding(
          message: definite
              ? 'An explicit author knowledge boundary prohibits this holder knowing this claim during an overlapping period. Correct the knowledge claim or explicitly revise/end the boundary; approval cannot waive it.'
              : 'Knowledge boundary applicability or temporal overlap is unresolved; clarify the authored world and interval.',
          records: [b.holder, b.proposition],
          fingerprint: FindingFingerprint(''),
          ruleId: ruleRow.identity.recordId,
          outcome: definite
              ? EvidenceOutcome.refuted
              : EvidenceOutcome.notEstablished,
          evidence: [ruleRow.recordVersionId, row.recordVersionId],
          coverage: definite ? Coverage.complete : Coverage.unsupported,
        ),
      );
    }
  }
  return List.unmodifiable(out);
}
