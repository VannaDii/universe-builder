import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

const resourceAccountingCapability = 'resources.accounting.v1';

final class ResourceGap {
  ResourceGap({
    required this.rule,
    required this.assertion,
    required this.proposition,
    required this.fingerprint,
    required Iterable<RecordVersionId> evidence,
    this.acceptance,
  }) : evidence = List.unmodifiable(evidence);
  final RecordId rule, assertion, proposition;
  final FindingFingerprint fingerprint;
  final List<RecordVersionId> evidence;
  final RecordId? acceptance;
}

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'resource.accounting', message: message);
final _integer = RegExp(r'^[+-]?[0-9]+$');
final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
(CalendarId, BigInt) _coordinate(AssertionRecord a) {
  if (a.validity case CalendarIntervalValidity(
    :final calendar,
    start: ExactBound(:final value),
  )) {
    final n = _integer.hasMatch(value) ? BigInt.tryParse(value) : null;
    if (n == null || n < _min || n > _max) {
      throw _invalid('invalid stock coordinate');
    }
    return (calendar, n);
  }
  throw _invalid('accounted stock needs an exact named-calendar interval');
}

bool _objective(AssertionRecord a) =>
    a.attributeMode == AttributeMode.instance && a.polarity == Polarity.support;
bool _worldApplies(Applicability scope, WorldId? world) => switch (scope) {
  UniverseApplicability() => true,
  WorldsApplicability(:final worldIds) =>
    world != null && worldIds.contains(world),
  _ => throw _invalid('resource accounting world applicability is unresolved'),
};
bool _accounted(
  AssertionRecord a,
  PropositionRecord p,
  Map<RecordId, RecordVersion> byId,
) {
  final link = a.establishedBy;
  if (link == null) return false;
  final event = byId[link.event.record]?.payload;
  if (event is! EventRecord) return false;
  final action = byId[event.action?.record]?.payload;
  if (action is! ActionDefinitionRecord) return false;
  return action.consequenceContract?.slots.any(
        (s) =>
            s.slot == link.slot &&
            s.target.predicate == p.predicate &&
            s.change is DeltaEffect,
      ) ??
      false;
}

CanonicalObject _bare(RecordPayload p) =>
    CanonicalObject(p.toWire().fields.where((e) => e.key != 'record_kind'));
final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// Assess the whole factual timeline. Acceptance preserves an unexplained
/// arrival; it neither invents an event nor replaces ordinary approval.
List<ResourceGap> assessResourceAccounting(
  List<RecordVersion> records,
  Frame base, {
  Set<RecordId> excludedRules = const {},
}) {
  final byId = {for (final r in records) r.identity.recordId: r};
  var remaining = 1000000;
  final gaps = <ResourceGap>[];
  final allWorlds = [
    for (final r in records)
      if (r.payload is WorldRecord)
        WorldId.parse(
          'wld_${r.identity.recordId.value.substring(RecordId.prefix.length)}',
        ),
  ];
  for (final ruleRow in records) {
    final rule = ruleRow.payload;
    if (excludedRules.contains(ruleRow.identity.recordId) ||
        rule is! RuleRecord ||
        !rule.capabilities.contains(resourceAccountingCapability)) {
      continue;
    }
    if (!rule.executable ||
        rule.commitPolicy != CommitPolicy.blockUnlessException ||
        rule.targetPredicates.isEmpty) {
      throw _invalid(
        'accounting rules must be executable, target resource properties and require explicit exception resolution',
      );
    }
    for (final name in rule.targetPredicates) {
      final properties = records
          .where(
            (r) =>
                r.payload is PropertyRecord &&
                '${(r.payload as PropertyRecord).namespace}:${(r.payload as PropertyRecord).key}' ==
                    name,
          )
          .toList();
      if (properties.length != 1) {
        throw _invalid('accounting target must identify one property');
      }
      final propertyRow = properties.single,
          property = propertyRow.payload as PropertyRecord;
      final numeric = switch (property.value) {
        SimpleValueShape(
          kind: SimpleShapeKind.integer || SimpleShapeKind.decimal,
        ) ||
        QuantityShape() => true,
        _ => false,
      };
      if (property.multiplicity != Multiplicity.single || !numeric) {
        throw _invalid(
          'accounting requires a single integer/decimal or exact-unit quantity property',
        );
      }
      for (final row in records) {
        final a = row.payload;
        if (a is! AssertionRecord || !_objective(a)) continue;
        final p = byId[a.proposition.record]?.payload;
        if (p is! PropositionRecord ||
            p.predicate.record != propertyRow.identity.recordId) {
          continue;
        }
        if (rule.applicability is WorldsApplicability &&
            a.scope.applicability is WorldsApplicability) {
          final policyWorlds =
              (rule.applicability as WorldsApplicability).worldIds;
          final claimWorlds =
              (a.scope.applicability as WorldsApplicability).worldIds;
          if (policyWorlds.every((w) => !claimWorlds.contains(w))) continue;
        }
        if (a.precision != Precision.exact ||
            a.alternatives.isNotEmpty ||
            a.scope.realm != null ||
            p.roles.isNotEmpty) {
          throw _invalid(
            'accounted stock must be exact objective evidence without alternate values or roles',
          );
        }
        final (calendar, tick) = _coordinate(a);
        final worlds = switch (a.scope.applicability) {
          UniverseApplicability() =>
            allWorlds.isEmpty ? <WorldId?>[null] : allWorlds,
          WorldsApplicability(:final worldIds) => worldIds,
          _ => throw _invalid('resource accounting scope is unresolved'),
        };
        for (final world in worlds) {
          if (!_worldApplies(rule.applicability, world)) continue;
          final frame = Frame(
            universe: base.universe,
            continuity: base.continuity,
            revision: base.revision,
            context: p.context,
            time: AtFrameTime(ExactTime(calendar, tick.toString())),
            perspective: base.perspective,
            readerScene: base.readerScene,
            personalSequence: base.personalSequence,
          );
          if (rule.validity is! UnspecifiedValidity) {
            final applies = eventApplies(rule.validity, frame.time, records);
            if (applies == false) continue;
            if (applies == null) {
              throw _invalid('accounting rule validity unresolved');
            }
          }
          final worldRecords = <RecordId>[
            if (world != null)
              RecordId.parse(
                'rec_${world.value.substring(WorldId.prefix.length)}',
              ),
          ];
          final applies = definitionMatches(
            p.subject.record,
            rule.subjectTypes,
            records,
            worldRecords,
          );
          if (applies == false) continue;
          if (applies == null) {
            throw _invalid('accounting rule subject applicability unresolved');
          }
          if (_accounted(a, p, byId)) continue;
          final prior = <(RecordVersion, AssertionRecord, PropositionRecord)>[];
          BigInt? latest;
          for (final prev in records) {
            if (remaining == 0) {
              throw _invalid('resource accounting work budget exceeded');
            }
            remaining--;
            final pa = prev.payload;
            if (pa is! AssertionRecord ||
                !_objective(pa) ||
                pa.scope.context != a.scope.context ||
                pa.scope.realm != a.scope.realm) {
              continue;
            }
            final pp = byId[pa.proposition.record]?.payload;
            if (pp is! PropositionRecord ||
                pp.subject != p.subject ||
                pp.predicate != p.predicate ||
                pp.context != p.context) {
              continue;
            }
            if (!_worldApplies(pa.scope.applicability, world)) continue;
            final (pc, pt) = _coordinate(pa);
            if (pc != calendar || pt >= tick) continue;
            if (latest == null || pt > latest) {
              prior.clear();
              latest = pt;
            }
            if (latest == pt) prior.add((prev, pa, pp));
          }
          if (prior.isEmpty ||
              prior.every(
                (r) =>
                    r.$3.value == p.value ||
                    r.$3.value != null &&
                        p.value != null &&
                        compareValues(r.$3.value!, Comparator.eq, p.value!) ==
                            true,
              )) {
            continue;
          }
          prior.sort(
            (a, b) => a.$1.identity.recordId.value.compareTo(
              b.$1.identity.recordId.value,
            ),
          );
          final fingerprint = FindingFingerprint(
            canonicalDigest(
              CanonicalArray([
                CanonicalString(resourceAccountingCapability),
                CanonicalString(ruleRow.identity.recordId.value),
                ruleRow.payload.toWire(),
                CanonicalString(propertyRow.identity.recordId.value),
                propertyRow.payload.toWire(),
                CanonicalString(a.proposition.record.value),
                _bare(a),
                _bare(p),
                world == null
                    ? const CanonicalNull()
                    : CanonicalString(world.value),
                CanonicalArray(
                  prior.map((r) => CanonicalArray([_bare(r.$2), _bare(r.$3)])),
                ),
              ]),
            ),
          );
          if (gaps.any((g) => g.fingerprint == fingerprint)) continue;
          final decisionScope = 'resource:${a.proposition.record.value}';
          RecordVersion? acceptance;
          for (final r in records) {
            final d = r.payload;
            if (d is IssueDecisionRecord &&
                d.mode == IssueDecisionMode.accept &&
                d.scope == decisionScope &&
                d.fingerprints.length == 1 &&
                d.fingerprints.single == fingerprint &&
                _nonWhitespace.hasMatch(d.rationale)) {
              acceptance = r;
              break;
            }
          }
          final evidence = <RecordVersionId>{
            ruleRow.recordVersionId,
            propertyRow.recordVersionId,
            row.recordVersionId,
            ...prior.map((r) => r.$1.recordVersionId),
            if (acceptance != null) acceptance.recordVersionId,
          }.toList()..sort((a, b) => a.value.compareTo(b.value));
          gaps.add(
            ResourceGap(
              rule: ruleRow.identity.recordId,
              assertion: row.identity.recordId,
              proposition: a.proposition.record,
              fingerprint: fingerprint,
              evidence: evidence,
              acceptance: acceptance?.identity.recordId,
            ),
          );
        }
      }
    }
  }
  return List.unmodifiable(gaps);
}
