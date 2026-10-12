import 'package:ub_domain/ub_domain.dart';

import 'comparison.dart';
import 'compiler.dart';
import 'definitions.dart';
import 'evidence.dart';
import 'events.dart';
import 'index.dart';
import 'opposing.dart';
import 'powers.dart';
import 'time.dart';

/// A caller-selected frame and factual candidate, with no permission authority.
final class EvaluationContext {
  EvaluationContext({
    this.index,
    this.frame,
    Iterable<RecordVersion> baseSnapshot = const [],
    Iterable<(RecordId, RecordVersion?)> candidateChanges = const [],
    Iterable<RecordId>? worldScope,
  }) : baseSnapshot = List.unmodifiable(baseSnapshot),
       candidateChanges = List.unmodifiable(candidateChanges),
       worldScope = worldScope == null ? null : List.unmodifiable(worldScope);
  final EvaluationIndex? index;
  final Frame? frame;
  final List<RecordVersion> baseSnapshot;
  final List<(RecordId, RecordVersion?)> candidateChanges;
  final List<RecordId>? worldScope;
}

enum EvaluationCoverage { complete, partial, failed, unsupported }

final class EvaluationResult {
  const EvaluationResult({
    required this.ruleId,
    required this.evidence,
    required this.coverage,
  });
  final RecordId ruleId;
  final Evidence evidence;
  final EvaluationCoverage coverage;
  EvidenceOutcome get outcome => evidence.outcome;
}

EvaluationResult evaluateRule(CompiledRule rule, EvaluationContext context) {
  final applies = switch (rule.applicability) {
    UniverseApplicability() => true,
    WorldsApplicability(:final worldIds) =>
      context.worldScope?.any(
            (r) => worldIds.any(
              (w) => r.value.substring(4) == w.value.substring(4),
            ),
          ) ??
          false,
    _ => false,
  };
  final (evidence, supported) = rule.executable && applies
      ? evaluateExpression(rule.expression, context)
      : (Evidence.notEstablished(), false);
  return EvaluationResult(
    ruleId: rule.id,
    evidence: evidence,
    coverage: supported
        ? EvaluationCoverage.complete
        : EvaluationCoverage.unsupported,
  );
}

/// Bounded execution over the caller-selected factual candidate and frame.
(Evidence, bool) evaluateExpression(Expr expr, EvaluationContext context) =>
    _Evaluation(context).eval(expr, const {});

Evidence _truth(bool value) =>
    value ? Evidence.supported([]) : Evidence.refuted([]);
(Evidence, bool) _unsupported() => (Evidence.notEstablished(), false);

DomainValue? _operand(Operand op, Map<String, DomainValue> variables) =>
    switch (op) {
      ValueOperand(:final value) => value,
      VariableOperand(:final name) => variables[name],
      RecordOperand(:final reference) => ReferenceValue(
        ValueReferenceKind.record,
        reference,
      ),
      _ => null,
    };

List<DomainValue>? _items(DomainValue? value) {
  switch (value) {
    case SetValue(:final items):
      final seen = <String>{};
      // Set identity follows canonical serde/wire bytes, not numeric equivalence.
      return items.where((v) => seen.add(v.toWire().toText())).toList();
    case SequenceValue(:final items):
      return items;
    default:
      return null;
  }
}

final class _Evaluation {
  _Evaluation(this.context);
  final EvaluationContext context;
  int budget = 10000;

  (Evidence, bool) eval(Expr expr, Map<String, DomainValue> variables) {
    if (budget == 0) return _unsupported();
    budget--;
    DomainValue? value(Operand op) => _operand(op, variables);
    switch (expr) {
      case LiteralExpr(:final value):
        return (_truth(value), true);
      case NotExpr(:final expr):
        final (e, supported) = eval(expr, variables);
        return (e.negate(), supported);
      case AllExpr(:final exprs) || AnyExpr(:final exprs):
        final all = expr is AllExpr;
        var acc = _truth(all), supported = true;
        for (final child in exprs) {
          final (e, complete) = eval(child, variables);
          acc = all ? acc.all(e) : acc.any(e);
          supported = supported && complete;
        }
        return (acc, supported);
      case CompareExpr(:final left, :final op, :final right):
        final a = value(left), b = value(right);
        if (a == null || b == null) return _unsupported();
        final answer = compareValues(a, op, b);
        return answer == null ? _unsupported() : (_truth(answer), true);
      case TemporalExpr(:final left, :final relation, :final right):
        final a = value(left), b = value(right);
        if (a is! TemporalValue || b is! TemporalValue) return _unsupported();
        final answer = temporalRelation(a.temporal, relation, b.temporal);
        return answer == null ? _unsupported() : (_truth(answer), true);
      case MembershipExpr(:final element, :final collection, :final complete):
        final wanted = value(element), items = _items(value(collection));
        if (wanted == null || items == null || items.length > budget) {
          return _unsupported();
        }
        budget -= items.length;
        final found = items.any(
          (v) => v == wanted || compareValues(v, Comparator.eq, wanted) == true,
        );
        return (
          found
              ? _truth(true)
              : complete == true
              ? _truth(false)
              : Evidence.notEstablished(),
          true,
        );
      case CardinalityExpr(
        :final collection,
        :final op,
        :final count,
        :final complete,
      ):
        final items = _items(value(collection));
        if (items == null || items.length > budget) return _unsupported();
        budget -= items.length;
        final answer = compareValues(
          IntegerValue('${items.length}'),
          op,
          count,
        );
        if (answer == null) return _unsupported();
        final monotone =
            (op == Comparator.gt || op == Comparator.gtEq) && answer ||
            (op == Comparator.lt || op == Comparator.ltEq) && !answer;
        return (
          complete == true || monotone
              ? _truth(answer)
              : Evidence.notEstablished(),
          true,
        );
      case QuantifyExpr(
        :final variable,
        :final over,
        :final complete,
        :final quantifier,
        :final body,
      ):
        final items = _items(value(over));
        if (items == null || items.length > budget) return _unsupported();
        final all = quantifier == Quantifier.forAll;
        var acc = _truth(all), supported = true;
        for (final item in items) {
          final (e, c) = eval(body, {...variables, variable: item});
          acc = all ? acc.all(e) : acc.any(e);
          supported = supported && c;
        }
        if (!complete) {
          acc = Evidence(
            support: all ? EvidenceBit.absent() : acc.support,
            refutation: all ? acc.refutation : EvidenceBit.absent(),
          );
        }
        return (acc, supported);
      case AttitudeExpr(:final holder, :final proposition, :final attitude):
        var evidence = Evidence.notEstablished(), complete = true;
        final snapshot = context.baseSnapshot, frame = context.frame;
        if (snapshot.length > budget) return (evidence, false);
        budget -= snapshot.length;
        if (!snapshot.any(
          (r) =>
              r.identity.recordId == proposition.record &&
              r.payload is PropositionRecord &&
              frame != null &&
              (r.payload as PropositionRecord).context == frame.context,
        )) {
          return (evidence, false);
        }
        for (final r in snapshot) {
          final a = r.payload;
          if (a is! EpistemicAttitudeRecord ||
              a.holder != holder ||
              a.proposition != proposition ||
              a.attitude != attitude) {
            continue;
          }
          if (frame?.time is TimelessFrameTime &&
              a.validity is! UnspecifiedValidity) {
            complete = false;
            continue;
          }
          final applies = frame == null
              ? null
              : eventApplies(a.validity, frame.time, snapshot);
          if (applies == true) {
            evidence = evidence.any(Evidence.supported([r.recordVersionId]));
          } else if (applies == null) {
            complete = false;
          }
        }
        return (evidence, complete);
      case ClaimExpr(
        :final subject,
        :final predicate,
        :final roles,
        :final value,
        :final polarity,
        context: final cell,
      ):
        final (e, c) = claim(
          subject,
          predicate,
          roles,
          value,
          cell,
          variables,
          true,
        );
        return (polarity == Polarity.refutation ? e.negate() : e, c);
      case NegatedClaimExpr(
        :final subject,
        :final predicate,
        :final roles,
        :final value,
        context: final cell,
      ):
        final (e, c) = claim(
          subject,
          predicate,
          roles,
          value,
          cell,
          variables,
          true,
        );
        return (e.negate(), c);
      case ExistenceExpr(
        :final subject,
        :final predicate,
        :final roles,
        :final value,
        context: final cell,
      ):
        final (e, c) = claim(
          subject,
          predicate,
          roles,
          value,
          cell,
          variables,
          true,
        );
        return (
          Evidence(support: e.support, refutation: EvidenceBit.absent()),
          c,
        );
      case RoleHoldsExpr(
        :final subject,
        :final predicate,
        :final role,
        :final participant,
      ):
        final (e, c) = claim(
          subject,
          predicate,
          [ExprRole(role, participant)],
          null,
          null,
          variables,
          false,
        );
        return (
          Evidence(support: e.support, refutation: EvidenceBit.absent()),
          c,
        );
      case NoOpposingEvidenceExpr(
        :final subject,
        :final predicate,
        context: final cell,
      ):
        return noOpposing(subject, predicate, cell, variables);
    }
  }

  (Evidence, bool) noOpposing(
    Operand subjectOperand,
    String predicate,
    Operand contextOperand,
    Map<String, DomainValue> variables,
  ) {
    RecordRef? reference(DomainValue? v) =>
        v is ReferenceValue &&
            (v.kind == ValueReferenceKind.record ||
                v.kind == ValueReferenceKind.entity)
        ? v.record
        : null;
    final subject = reference(_operand(subjectOperand, variables)),
        cell = reference(_operand(contextOperand, variables)),
        frame = context.frame;
    if (subject == null || cell == null || frame == null) return _unsupported();
    try {
      subject.resolveNamespace(frame.universe);
      cell.resolveNamespace(frame.universe);
    } on FormatException {
      return _unsupported();
    }
    final snapshot = <RecordId, RecordVersion>{
      for (final r in context.baseSnapshot) r.identity.recordId: r,
    };
    for (final (id, next) in context.candidateChanges) {
      if (next == null) {
        snapshot.remove(id);
      } else {
        snapshot[id] = next;
      }
    }
    final definitions = snapshot.values
        .where(
          (r) => switch (r.payload) {
            PropertyRecord(:final namespace, :final key) ||
            RelationRecord(
              :final namespace,
              :final key,
            ) => '$namespace:$key' == predicate,
            _ => false,
          },
        )
        .map((r) => r.identity.recordId)
        .toList();
    if (definitions.length != 1 ||
        !snapshot.containsKey(subject.record) ||
        snapshot[cell.record]?.payload is! RepresentedContextRecord) {
      return _unsupported();
    }
    RecordRef? normalized(RecordRef ref) {
      try {
        return ref.resolveNamespace(frame.universe);
      } on FormatException {
        return null;
      }
    }

    final props = snapshot.values
        .where((r) {
          final p = r.payload;
          return p is PropositionRecord &&
              normalized(p.subject) == normalized(subject) &&
              normalized(p.context) == normalized(cell) &&
              p.predicate.record == definitions.single;
        })
        .map((r) => r.identity.recordId)
        .toSet();
    final ids = snapshot.keys.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final records = ids.map((id) => snapshot[id]!).toList();
    final exactCell = <RecordId>{};
    snapshot.removeWhere((id, r) {
      final a = r.payload;
      if (a is! AssertionRecord) return false;
      if (!props.contains(a.proposition.record)) return true;
      final world = switch (a.scope.applicability) {
        UniverseApplicability() => true,
        WorldsApplicability(:final worldIds) when worldIds.isEmpty => false,
        WorldsApplicability(:final worldIds) => context.worldScope?.any(
          (r) =>
              worldIds.any((w) => r.value.substring(4) == w.value.substring(4)),
        ),
        _ => null,
      };
      final time = a.validity is UnspecifiedValidity
          ? true
          : eventApplies(a.validity, frame.time, records);
      if (world == false || time == false) return true;
      if (world == true && time == true && a.scope.realm == null) {
        exactCell.add(id);
      }
      return false;
    });
    if (snapshot.length > budget) return _unsupported();
    budget -= snapshot.length;
    final remaining = ids
        .where(snapshot.containsKey)
        .map((id) => snapshot[id]!)
        .toList();
    OpposingScan scan;
    try {
      scan = detectOpposing(
        universe: frame.universe,
        records: remaining,
        indexed: context.index != null,
        budget: budget,
      );
    } on OpposingError {
      return _unsupported();
    }
    budget -= scan.comparisons;
    final complete =
        scan.complete &&
        scan.pairs.every(
          (p) =>
              exactCell.contains(p.support.assertion.identity.recordId) &&
              exactCell.contains(p.refutation.assertion.identity.recordId),
        );
    final sources = scan.pairs
        .expand((p) => [p.support, p.refutation])
        .expand(
          (c) => [
            c.assertion.recordVersionId,
            c.proposition.recordVersionId,
            ...c.dependencies.map((r) => r.recordVersionId),
          ],
        )
        .toList();
    if (scan.pairs.any(
      (p) =>
          p.definite &&
          exactCell.contains(p.support.assertion.identity.recordId) &&
          exactCell.contains(p.refutation.assertion.identity.recordId),
    )) {
      return (Evidence.refuted(sources), complete);
    }
    return complete ? (Evidence.supported(sources), true) : _unsupported();
  }

  (Evidence, bool) claim(
    Operand subjectOperand,
    String predicate,
    List<ExprRole> roleOperands,
    Operand? valueOperand,
    Operand? contextOperand,
    Map<String, DomainValue> variables,
    bool exactRoles,
  ) {
    RecordRef? reference(DomainValue? v) =>
        v is ReferenceValue &&
            (v.kind == ValueReferenceKind.record ||
                v.kind == ValueReferenceKind.entity)
        ? v.record
        : null;
    final frame = context.frame;
    final subject = reference(_operand(subjectOperand, variables));
    final cell = contextOperand == null
        ? frame?.context
        : reference(_operand(contextOperand, variables));
    if (frame == null || subject == null || cell == null) return _unsupported();
    try {
      // Validate namespace without changing authored reference identity.
      subject.resolveNamespace(frame.universe);
      cell.resolveNamespace(frame.universe);
    } on FormatException {
      return _unsupported();
    }
    final expected = valueOperand == null
        ? null
        : _operand(valueOperand, variables);
    if (valueOperand != null && expected == null) return _unsupported();
    final roles = <(String, RecordRef)>[];
    for (final r in roleOperands) {
      final participant = reference(_operand(r.operand, variables));
      if (participant == null) return _unsupported();
      roles.add((r.role, participant));
    }
    final all = <RecordId, RecordVersion>{
      for (final r in context.baseSnapshot) r.identity.recordId: r,
    };
    for (final (id, next) in context.candidateChanges) {
      if (next == null) {
        all.remove(id);
      } else {
        all[id] = next;
      }
    }
    List<RecordVersion> ordered(Map<RecordId, RecordVersion> records) =>
        (records.keys.toList()..sort((a, b) => a.value.compareTo(b.value)))
            .map((id) => records[id]!)
            .toList();
    final allRecords = ordered(all);
    final inherits = all[subject.record]?.payload is EntityRecord;
    final chain = definitionAncestry(subject.record, allRecords);
    final selected =
        context.index != null && context.candidateChanges.isEmpty && !inherits
        ? context.index!.claim(subject, predicate, cell)
        : allRecords;
    final snapshot = <RecordId, RecordVersion>{
      for (final r in selected) r.identity.recordId: r,
    };
    final rows = ordered(snapshot);
    if (snapshot.length > budget) return _unsupported();
    budget -= snapshot.length;
    final definitions = rows
        .where(
          (r) => switch (r.payload) {
            PropertyRecord(:final namespace, :final key) ||
            RelationRecord(
              :final namespace,
              :final key,
            ) => '$namespace:$key' == predicate,
            _ => false,
          },
        )
        .map((r) => r.identity.recordId)
        .toList();
    if (definitions.length != 1) return _unsupported();
    final propositions = rows
        .where((r) {
          final p = r.payload;
          return p is PropositionRecord &&
              (p.subject == subject ||
                  inherits && chain.types.contains(p.subject.record)) &&
              p.context == cell &&
              p.predicate.record == definitions.single &&
              (!exactRoles || p.roles.length == roles.length) &&
              roles.every(
                (role) => p.roles.any(
                  (r) => r.role == role.$1 && r.participant == role.$2,
                ),
              );
        })
        .map((r) => r.identity.recordId)
        .toSet();
    var support = EvidenceBit.absent(), refutation = EvidenceBit.absent();
    var complete = true;
    final definition = snapshot[definitions.single]!.payload;
    final property = definition is PropertyRecord ? definition : null;
    final worlds = context.worldScope ?? const <RecordId>[];
    if (property != null && property.subjectTypes.isNotEmpty) {
      final matches = definitionMatches(
        subject.record,
        property.subjectTypes,
        allRecords,
        worlds,
      );
      if (matches == false) return (Evidence.notEstablished(), true);
      if (matches == null) complete = false;
    }
    if (inherits &&
        !chain.complete &&
        allRecords.any((r) {
          final a = r.payload;
          if (a is! AssertionRecord ||
              a.attributeMode != AttributeMode.shared ||
              a.scope.context != cell ||
              worldApplies(a.scope.applicability, worlds) == false ||
              eventApplies(a.validity, frame.time, allRecords) == false) {
            return false;
          }
          final p = all[a.proposition.record]?.payload;
          return p is PropositionRecord &&
              p.context == cell &&
              p.predicate.record == definitions.single &&
              all[p.subject.record]?.payload is EntityTypeRecord;
        })) {
      complete = false;
    }
    final hasShared = rows.any((r) {
      final a = r.payload;
      if (a is! AssertionRecord) return false;
      final p = snapshot[a.proposition.record]?.payload;
      return p is PropositionRecord &&
          a.attributeMode == AttributeMode.shared &&
          p.subject != subject &&
          propositions.contains(a.proposition.record) &&
          a.scope.context == cell &&
          a.scope.realm == null &&
          worldApplies(a.scope.applicability, worlds) == true &&
          eventApplies(a.validity, frame.time, allRecords) == true &&
          definitionMatches(
                subject.record,
                [p.subject.record],
                allRecords,
                worlds,
              ) ==
              true;
    });
    for (final r in rows) {
      final a = r.payload;
      if (a is! AssertionRecord ||
          !propositions.contains(a.proposition.record) ||
          a.scope.context != cell) {
        continue;
      }
      final prop = snapshot[a.proposition.record]!;
      final p = prop.payload as PropositionRecord;
      final inherited = p.subject != subject;
      if (inherited && a.attributeMode != AttributeMode.shared) continue;
      final matches =
          expected == null ||
          p.value != null &&
              (expected == p.value ||
                  compareValues(expected, Comparator.eq, p.value!) == true);
      if (!matches &&
          !((inherited || inherits && hasShared) &&
              property?.multiplicity == Multiplicity.single)) {
        continue;
      }
      final world = worldApplies(a.scope.applicability, worlds);
      final validity = eventApplies(a.validity, frame.time, allRecords);
      // Proven disjointness makes uncertainty in another dimension irrelevant.
      if (world == false || validity == false) continue;
      if (inherited || all[p.subject.record]?.payload is EntityTypeRecord) {
        final matches = definitionMatches(
          inherited ? subject.record : p.subject.record,
          [p.subject.record],
          allRecords,
          worlds,
        );
        if (matches == false) continue;
        if (matches == null) {
          complete = false;
          continue;
        }
      }
      if (world == null || a.scope.realm != null) {
        complete = false;
        continue;
      }
      if (a.precision != Precision.exact ||
          a.alternatives.isNotEmpty ||
          validity == null ||
          frame.time is TimelessFrameTime &&
              a.validity is! UnspecifiedValidity) {
        complete = false;
        continue;
      }
      final sources = <RecordVersionId>[r.recordVersionId];
      if (inherited) {
        sources.add(prop.recordVersionId);
        final owner = all[subject.record];
        if (owner != null) sources.add(owner.recordVersionId);
        sources.addAll(
          chain.types
              .map((id) => all[id]?.recordVersionId)
              .whereType<RecordVersionId>(),
        );
      }
      final bit = EvidenceBit.withSources(sources);
      if (a.polarity == Polarity.support && matches) {
        support = support.or(bit);
      } else if (a.polarity == Polarity.refutation && matches ||
          a.polarity == Polarity.support && !matches) {
        refutation = refutation.or(bit);
      }
    }
    final hasPowers = context.index != null && context.candidateChanges.isEmpty
        ? context.index!.hasPowers
        : context.baseSnapshot.any((r) => r.payload is ItemPowerRecord) ||
              context.candidateChanges.any(
                (r) => r.$2?.payload is ItemPowerRecord,
              );
    if (roles.isEmpty && hasPowers) {
      if (context.baseSnapshot.length > budget) return _unsupported();
      budget -= context.baseSnapshot.length;
      final queries = worlds.isEmpty
          ? <WorldId?>[null]
          : worlds
                .map((r) => WorldId.parse('wld_${r.value.substring(4)}'))
                .toList();
      for (final world in queries) {
        List<PowerFact> derived;
        try {
          derived = derivePowers(
            records: allRecords,
            subjects: [subject.record],
            predicates: definitions,
            context: cell,
            time: frame.time,
            world: world,
          );
        } on PowerEvaluationError {
          return _unsupported();
        }
        for (final fact in derived) {
          if (fact.subject != subject) continue;
          final matches = expected == null || expected == fact.value;
          final bit = EvidenceBit.withSources(fact.evidence);
          if (matches) {
            support = support.or(bit);
          } else if (hasShared &&
              property?.multiplicity == Multiplicity.single) {
            refutation = refutation.or(bit);
          }
        }
      }
    }
    for (final r in rows) {
      final c = r.payload;
      if (c is! CompletenessRecord ||
          c.subject != subject ||
          c.predicate != predicate ||
          c.scope.context != cell ||
          c.completeness is! ObjectiveCompleteness ||
          roles.isNotEmpty ||
          c.scope.realm != null) {
        continue;
      }
      final applies = switch (c.scope.applicability) {
        UniverseApplicability() => true,
        WorldsApplicability(:final worldIds) =>
          context.worldScope != null &&
              worlds.length == 1 &&
              worldIds.any(
                (w) => worlds.single.value.substring(4) == w.value.substring(4),
              ),
        _ => false,
      };
      if (!applies ||
          frame.time is TimelessFrameTime &&
              c.validity is! UnspecifiedValidity ||
          eventApplies(c.validity, frame.time, context.baseSnapshot) != true) {
        continue;
      }
      final absent = expected == null
          ? c.members.isEmpty
          : expected is ReferenceValue &&
                (expected.kind == ValueReferenceKind.record ||
                    expected.kind == ValueReferenceKind.entity) &&
                !c.members.contains(expected.record);
      if (absent) {
        refutation = refutation.or(EvidenceBit.withSource(r.recordVersionId));
      }
    }
    return (Evidence(support: support, refutation: refutation), complete);
  }
}
