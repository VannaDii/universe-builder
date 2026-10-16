import 'dart:collection';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show temporalOverlaps;

const relationCardinalityCapability = 'relations.cardinality.v1';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'relationCardinality', message: message);

void validateCardinalityRule(RuleRecord rule, List<RecordVersion> records) {
  final c = rule.relationCardinality;
  if (c == null) {
    if (rule.capabilities.contains(relationCardinalityCapability)) {
      throw _invalid('cardinality capability requires an authored contract');
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
      rule.capabilities.single != relationCardinalityCapability ||
      rule.knowledgeBoundary != null ||
      rule.channelChronology != null ||
      rule.knowledgePolicy != null) {
    throw _invalid(
      'requires an executable physical always_block rule, universe-wide wrapper, unspecified wrapper validity, literal true and only its capability; scope and time belong to the contract',
    );
  }
  RecordPayload? find(RecordRef reference) {
    for (final row in records) {
      if (row.identity.recordId == reference.record) return row.payload;
    }
    return null;
  }

  final d = find(c.relation);
  if (d is! RelationRecord) {
    throw _invalid('relation must resolve to a relation definition');
  }
  if (!d.roles.any((r) => r.name == c.countedRole) ||
      c.grouping is RoleCardinalityKey &&
          !d.roles.any(
            (r) => r.name == (c.grouping as RoleCardinalityKey).role,
          )) {
    throw _invalid(
      'grouping and counted roles must be declared by the relation',
    );
  }
  if (find(c.scope.context) is! RepresentedContextRecord ||
      c.scope.realm != null && find(c.scope.realm!) is! RealmRecord) {
    throw _invalid('scope needs a represented context and optional realm');
  }
  if (c.scope.applicability case WorldsApplicability(:final worldIds)) {
    for (final w in worldIds) {
      final id = RecordId.parse(
        'rec_${w.value.substring(WorldId.prefix.length)}',
      );
      if (!records.any(
        (r) => r.identity.recordId == id && r.payload is WorldRecord,
      )) {
        throw _invalid('contract world must resolve to a world');
      }
    }
  }
}

final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
final _integer = RegExp(r'^[+-]?[0-9]+$');
BigInt? _ticks(String value) {
  if (!_integer.hasMatch(value)) return null;
  final n = BigInt.tryParse(value);
  return n != null && n >= _min && n <= _max ? n : null;
}

/// Closed integer windows preserve exact half-open interval semantics.
(CalendarId, BigInt, BigInt)? _window(Validity v) {
  if (v case InstantValidity(at: ExactTime(:final calendar, :final value))) {
    final n = _ticks(value);
    return n == null ? null : (calendar, n, n);
  }
  if (v is! CalendarIntervalValidity) return null;
  final lo = switch (v.start) {
    ExactBound(:final value) => _ticks(value),
    UnboundedBound() => _min,
    _ => null,
  };
  final end = switch (v.end) {
    ExactBound(:final value) => _ticks(value),
    UnboundedBound() => null,
    _ => null,
  };
  final hi = v.end is UnboundedBound
      ? _max
      : end == null || end == _min
      ? null
      : end - BigInt.one;
  return lo != null && hi != null && lo <= hi ? (v.calendar, lo, hi) : null;
}

bool _empty(Validity v) {
  if (v case CalendarIntervalValidity(
    start: ExactBound(value: final a),
    end: ExactBound(value: final b),
  )) {
    final x = _ticks(a), y = _ticks(b);
    return x != null && y != null && x == y;
  }
  return false;
}

bool? _worlds(Applicability a, WorldId? world) => switch (a) {
  UniverseApplicability() => true,
  WorldsApplicability(:final worldIds) =>
    world != null && worldIds.contains(world),
  _ => null,
};
bool _scopeMatch(Scope a, Scope c) =>
    a.context == c.context &&
    (c.realm == null || a.realm == null || a.realm == c.realm);
bool _sameRelation(PropositionRecord a, PropositionRecord b) {
  final left = a.roles.map((r) => (r.role, r.participant)).toSet();
  final right = b.roles.map((r) => (r.role, r.participant)).toSet();
  return a.predicate == b.predicate &&
      a.subject == b.subject &&
      a.context == b.context &&
      left.length == right.length &&
      left.containsAll(right);
}

int _compareRef(RecordRef? a, RecordRef? b) {
  if (a == null) return b == null ? 0 : -1;
  if (b == null) return 1;
  final au = a.universe, bu = b.universe;
  final ns = au == null
      ? (bu == null ? 0 : -1)
      : bu == null
      ? 1
      : au.value.compareTo(bu.value);
  return ns != 0 ? ns : a.record.value.compareTo(b.record.value);
}

/// Counts distinct participants per grouping key, world, realm and authored
/// clock. Unknown overlap remains unresolved; no minimum count is inferred.
List<Finding> assessRelationCardinality(
  List<RecordVersion> records, {
  Set<RecordId> excludedRules = const {},
}) {
  final map = {for (final r in records) r.identity.recordId: r};
  final worlds = <WorldId?>{null};
  for (final r in records) {
    if (excludedRules.contains(r.identity.recordId)) {
      continue;
    }
    final applicability = switch (r.payload) {
      AssertionRecord(:final scope) => scope.applicability,
      RuleRecord(:final relationCardinality) =>
        relationCardinality?.scope.applicability,
      _ => null,
    };
    if (applicability is WorldsApplicability) {
      worlds.addAll(applicability.worldIds);
    }
  }
  final worldCells = worlds.toList()
    ..sort(
      (a, b) => a == null
          ? b == null
                ? 0
                : -1
          : b == null
          ? 1
          : a.value.compareTo(b.value),
    );
  final assertions =
      <(RecordVersion, AssertionRecord, RecordVersion, PropositionRecord)>[];
  for (final row in records) {
    final a = row.payload;
    if (a is! AssertionRecord) continue;
    final prop = map[a.proposition.record];
    if (prop != null && prop.payload is PropositionRecord) {
      assertions.add((row, a, prop, prop.payload as PropositionRecord));
    }
  }
  final refutations = assertions
      .where((r) => r.$2.polarity == Polarity.refutation)
      .toList();
  final findings = <Finding>[];
  for (final row in records) {
    final rule = row.payload;
    if (rule is! RuleRecord || excludedRules.contains(row.identity.recordId)) {
      continue;
    }
    final c = rule.relationCardinality;
    if (c == null) continue;
    final evidence = <RecordVersionId>{row.recordVersionId};
    if (map[c.relation.record] case final definition?) {
      evidence.add(definition.recordVersionId);
    }
    var unresolved =
        c.scope.applicability is UnspecifiedApplicability ||
        c.scope.applicability is ConditionalApplicability ||
        c.validity is! UnspecifiedValidity &&
            !_empty(c.validity) &&
            _window(c.validity) == null;
    var violation = false, work = 100000;
    final realmCells =
        (c.scope.realm != null
                ? <RecordRef?>{c.scope.realm}
                : <RecordRef?>{
                    null,
                    ...assertions.map((a) => a.$2.scope.realm),
                  })
            .toList()
          ..sort(_compareRef);
    for (final world in worldCells) {
      final ruleWorld = _worlds(c.scope.applicability, world);
      if (ruleWorld == false || _empty(c.validity)) continue;
      for (final realm in realmCells) {
        final groups =
            <(RecordRef, CalendarId), List<(RecordRef, BigInt, BigInt)>>{};
        for (final (aRow, a, pRow, p) in assertions) {
          if (a.polarity != Polarity.support ||
              p.predicate != c.relation ||
              !_scopeMatch(a.scope, c.scope)) {
            continue;
          }
          if (a.scope.realm != null && a.scope.realm != realm) continue;
          if (work == 0) {
            unresolved = true;
            break;
          }
          work--;
          final factWorld = _worlds(a.scope.applicability, world);
          if (factWorld == false || _empty(a.validity)) continue;
          if (temporalOverlaps(a.validity, c.validity) == false) continue;
          evidence.addAll([aRow.recordVersionId, pRow.recordVersionId]);
          final keys = switch (c.grouping) {
            SubjectCardinalityKey() => [p.subject],
            RoleCardinalityKey(:final role) =>
              p.roles
                  .where((r) => r.role == role)
                  .map((r) => r.participant)
                  .toSet()
                  .toList()
                ..sort(_compareRef),
          };
          final participants =
              p.roles
                  .where((r) => r.role == c.countedRole)
                  .map((r) => r.participant)
                  .toSet()
                  .toList()
                ..sort(_compareRef);
          var w = _window(a.validity);
          if (c.validity is! UnspecifiedValidity) {
            final rw = _window(c.validity);
            if (w == null || rw == null || w.$1 != rw.$1) {
              w = null;
            } else {
              final lo = w.$2 > rw.$2 ? w.$2 : rw.$2,
                  hi = w.$3 < rw.$3 ? w.$3 : rw.$3;
              w = lo <= hi ? (w.$1, lo, hi) : null;
            }
          }
          var opposed = false;
          for (final (rRow, r, _, rp) in refutations) {
            if (work == 0) {
              unresolved = true;
              opposed = true;
              break;
            }
            work--;
            if (_sameRelation(p, rp) &&
                r.scope.context == a.scope.context &&
                (r.scope.realm == null || r.scope.realm == realm) &&
                _worlds(r.scope.applicability, world) != false &&
                temporalOverlaps(r.validity, a.validity) != false) {
              evidence.add(rRow.recordVersionId);
              opposed = true;
              break;
            }
          }
          if (keys.isEmpty ||
              participants.isEmpty ||
              p.quantification != Quantification.particular ||
              a.precision != Precision.exact ||
              a.alternatives.isNotEmpty ||
              opposed ||
              ruleWorld == null ||
              factWorld == null ||
              w == null) {
            unresolved = true;
            continue;
          }
          final (clock, lo, hi) = w;
          for (final key in keys) {
            final group = groups.putIfAbsent((key, clock), () => []);
            for (final participant in participants) {
              if (work == 0) {
                unresolved = true;
                break;
              }
              work--;
              group.add((participant, lo, hi));
            }
          }
        }
        final clocks = <RecordRef, Set<CalendarId>>{};
        for (final (key, clock) in groups.keys) {
          clocks.putIfAbsent(key, () => {}).add(clock);
        }
        unresolved |= clocks.values.any((v) => v.length > 1);
        for (final entries in groups.values) {
          final events = SplayTreeMap<BigInt, List<(RecordRef, bool)>>();
          for (final (participant, lo, hi) in entries) {
            events.putIfAbsent(lo, () => []).add((participant, true));
            if (hi < _max) {
              events.putIfAbsent(hi + BigInt.one, () => []).add((
                participant,
                false,
              ));
            }
          }
          final active = <RecordRef, int>{};
          for (final changes in events.values) {
            for (final (participant, starts) in changes) {
              if (starts) {
                active.update(participant, (n) => n + 1, ifAbsent: () => 1);
              } else if (active[participant] case final n?) {
                if (n == 1) {
                  active.remove(participant);
                } else {
                  active[participant] = n - 1;
                }
              }
            }
            violation |= active.length > c.maximum;
          }
        }
      }
    }
    final sorted = evidence.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    findings.add(
      Finding(
        message: violation
            ? 'Distinct participants exceed authored maximum ${c.maximum} at a common overlapping world/context/time for the grouping key. Retrieve this rule and its relation assertions; correct participants, scopes or validity, or explicitly revise the maximum.'
            : unresolved
            ? 'The scoped count is unresolved. Retrieve relation assertions and the authored scope/validity; repair unknown time, scope, precision or opposing evidence. Repeated evidence counts once and local role multiplicity is separate.'
            : 'The authored cross-instance maximum is satisfied; repeated evidence counts once and local role multiplicity remains separate.',
        fingerprint: FindingFingerprint(''),
        ruleId: row.identity.recordId,
        outcome: violation
            ? EvidenceOutcome.refuted
            : unresolved
            ? EvidenceOutcome.notEstablished
            : EvidenceOutcome.supported,
        coverage: unresolved && !violation
            ? Coverage.unsupported
            : Coverage.complete,
        evidence: sorted,
      ),
    );
  }
  return List.unmodifiable(findings);
}
