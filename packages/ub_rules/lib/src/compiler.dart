import 'package:ub_domain/ub_domain.dart';

/// Compilation checks structure and preserves declarations; it does not grant
/// publication rights, establish truth, or implement declared capabilities.
final class CompiledRule {
  CompiledRule({
    required this.id,
    required this.applicability,
    required this.executable,
    required this.expression,
    required Iterable<RecordId> referencedRecords,
    required this.nodeCount,
  }) : referencedRecords = List.unmodifiable(referencedRecords);
  final RecordId id;
  final Applicability applicability;
  final bool executable;
  final Expr expression;
  final List<RecordId> referencedRecords;
  final int nodeCount;
}

sealed class RuleCompileError implements Exception {
  const RuleCompileError();
}

final class NotARule extends RuleCompileError {
  const NotARule();
  @override
  String toString() => 'Expected a rule record';
}

final class RuleDepthExceeded extends RuleCompileError {
  const RuleDepthExceeded(this.currentDepth);
  final int currentDepth;
  @override
  String toString() => 'Depth $currentDepth exceeds 32';
}

final class RuleNodeCountExceeded extends RuleCompileError {
  const RuleNodeCountExceeded(this.currentCount);
  final int currentCount;
  @override
  String toString() => 'Nodes $currentCount exceeds 1000';
}

CompiledRule compileRule(RecordId id, RecordPayload payload) {
  if (payload is! RuleRecord) throw const NotARule();
  final (nodes, depth) = _metrics(payload.expression);
  if (nodes > 1000) throw RuleNodeCountExceeded(nodes);
  if (depth > 32) throw RuleDepthExceeded(depth);
  final references = <RecordId>{};
  void operand(Operand value) {
    if (value is RecordOperand) references.add(value.reference.record);
  }

  void visit(Expr expr) {
    switch (expr) {
      case NoOpposingEvidenceExpr():
        operand(expr.subject);
        operand(expr.context);
      case AttitudeExpr():
        references.add(expr.holder.record);
        references.add(expr.proposition.record);
      case LiteralExpr():
        break;
      case NotExpr():
        visit(expr.expr);
      case AllExpr():
        for (final child in expr.exprs) {
          visit(child);
        }
      case AnyExpr():
        for (final child in expr.exprs) {
          visit(child);
        }
      case ClaimExpr(:final subject, :final roles, :final value) ||
          NegatedClaimExpr(:final subject, :final roles, :final value) ||
          ExistenceExpr(:final subject, :final roles, :final value):
        operand(subject);
        for (final role in roles) {
          operand(role.operand);
        }
        if (value != null) operand(value);
      case CompareExpr():
        operand(expr.left);
        operand(expr.right);
      case TemporalExpr():
        operand(expr.left);
        operand(expr.right);
      case MembershipExpr():
        operand(expr.element);
        operand(expr.collection);
      case CardinalityExpr():
        operand(expr.collection);
      case QuantifyExpr():
        operand(expr.over);
        visit(expr.body);
      case RoleHoldsExpr():
        operand(expr.subject);
        operand(expr.participant);
    }
  }

  visit(payload.expression);
  final sorted = references.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return CompiledRule(
    id: id,
    applicability: payload.applicability,
    executable: payload.executable && payload.kind != RuleKind.descriptive,
    expression: payload.expression,
    referencedRecords: sorted,
    nodeCount: nodes,
  );
}

// Preserve the current compiler's metrics independently from Expr.analyze:
// each operand contributes one; claim context is excluded, role_holds is a
// single node, and claim role/value contributions also add to depth.
(int, int) _metrics(Expr expr) {
  switch (expr) {
    case NoOpposingEvidenceExpr():
      return (3, 3);
    case AttitudeExpr() || LiteralExpr() || RoleHoldsExpr():
      return (1, 1);
    case NotExpr():
      final (nodes, depth) = _metrics(expr.expr);
      return (1 + nodes, 1 + depth);
    case AllExpr(:final exprs) || AnyExpr(:final exprs):
      var nodes = 1;
      var depth = 0;
      for (final child in exprs) {
        final (n, d) = _metrics(child);
        nodes += n;
        if (d > depth) depth = d;
      }
      return (nodes, 1 + depth);
    case ClaimExpr(:final roles, :final value) ||
        NegatedClaimExpr(:final roles, :final value) ||
        ExistenceExpr(:final roles, :final value):
      return (
        2 + roles.length + (value == null ? 0 : 1),
        2 + (roles.isEmpty ? 0 : 1) + (value == null ? 0 : 1),
      );
    case CompareExpr() || TemporalExpr() || MembershipExpr():
      return (3, 3);
    case CardinalityExpr():
      return (2, 2);
    case QuantifyExpr():
      final (nodes, depth) = _metrics(expr.body);
      return (2 + nodes, 2 + depth);
  }
}
