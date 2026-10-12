import 'package:ub_domain/ub_domain.dart';

import 'comparison.dart';
import 'compiler.dart';
import 'evidence.dart';
import 'events.dart';
import 'index.dart';
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

/// Bounded execution. Factual claim and opposing-evidence branches are still
/// being ported; they remain unsupported until their handlers arrive.
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
      case NoOpposingEvidenceExpr() ||
          ClaimExpr() ||
          NegatedClaimExpr() ||
          ExistenceExpr() ||
          RoleHoldsExpr():
        return _unsupported();
    }
  }
}
