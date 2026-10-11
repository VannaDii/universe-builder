part of 'records.dart';

enum Comparator {
  eq('eq', 'eq'),
  neq('neq', 'neq'),
  lt('lt', 'lt'),
  ltEq('lt_eq', 'lte'),
  gt('gt', 'gt'),
  gtEq('gt_eq', 'gte');

  const Comparator(this.wireName, this.canonicalName);
  final String wireName, canonicalName;
  static Comparator fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown comparator'),
  );
}

enum Quantifier {
  forAll('for_all', 'forall'),
  exists('exists', 'exists');

  const Quantifier(this.wireName, this.canonicalName);
  final String wireName, canonicalName;
  static Quantifier fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown quantifier'),
  );
}

sealed class Operand {
  const Operand();
  CanonicalObject encode({required bool canonical});
  CanonicalObject toWire() => encode(canonical: false);
  CanonicalObject toCanonical() => encode(canonical: true);
  @override
  bool operator ==(Object other) =>
      other is Operand && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
  static Operand fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'variable':
        f.allow({'kind', 'name'});
        return VariableOperand(f.string('name'));
      case 'record':
        f.allow({'kind', 'ref'});
        return RecordOperand(RecordRef.fromCanonical(f.require('ref')));
      case 'value':
        f.allow({'kind', 'value'});
        return ValueOperand(DomainValue.fromWire(f.require('value')));
      case 'frame_time':
        f.allow({'kind'});
        return const FrameTimeOperand();
      case 'event_participant':
        f.allow({'kind', 'role'});
        return EventParticipantOperand(f.string('role'));
      case 'event_ref':
        f.allow({'kind'});
        return const EventRefOperand();
      default:
        throw const FormatException('Unknown operand');
    }
  }
}

final class VariableOperand extends Operand {
  const VariableOperand(this.name);
  final String name;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('variable', [MapEntry('name', CanonicalString(name))]);
}

final class RecordOperand extends Operand {
  const RecordOperand(this.reference);
  final RecordRef reference;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('record', [MapEntry('ref', reference.toCanonical())]);
}

final class ValueOperand extends Operand {
  const ValueOperand(this.value);
  final DomainValue value;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('value', [
    MapEntry('value', canonical ? value.toCanonical() : value.toWire()),
  ]);
}

final class FrameTimeOperand extends Operand {
  const FrameTimeOperand();
  @override
  CanonicalObject encode({required bool canonical}) => tagged('frame_time', []);
}

final class EventParticipantOperand extends Operand {
  const EventParticipantOperand(this.role);
  final String role;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('event_participant', [MapEntry('role', CanonicalString(role))]);
}

final class EventRefOperand extends Operand {
  const EventRefOperand();
  @override
  CanonicalObject encode({required bool canonical}) => tagged('event_ref', []);
}

/// Declarative syntax only. Evaluation belongs to the shared rules service.
sealed class Expr {
  const Expr();
  CanonicalObject encode({required bool canonical});
  CanonicalObject toWire() => encode(canonical: false);
  CanonicalObject toCanonical() => encode(canonical: true);
  ExprAnalysis analyze() => _analyze(this);
  bool get usesOpposingEvidence => switch (this) {
    NoOpposingEvidenceExpr() => true,
    NotExpr(:final expr) => expr.usesOpposingEvidence,
    AllExpr(:final exprs) => exprs.any((e) => e.usesOpposingEvidence),
    AnyExpr(:final exprs) => exprs.any((e) => e.usesOpposingEvidence),
    QuantifyExpr(:final body) => body.usesOpposingEvidence,
    _ => false,
  };
  @override
  bool operator ==(Object other) =>
      other is Expr && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
  static Expr fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) {
      throw const FormatException('Expression decoding nesting limit');
    }
    final f = Fields(value);
    Operand op(String key) => Operand.fromWire(f.require(key));
    Expr child(String key) => fromWire(f.require(key), depth: depth + 1);
    Iterable<Expr> children() =>
        f.array('exprs').map((v) => fromWire(v, depth: depth + 1));
    switch (f.string('kind')) {
      case 'no_opposing_evidence':
        f.allow({'kind', 'subject', 'predicate', 'context'});
        return NoOpposingEvidenceExpr(
          op('subject'),
          f.string('predicate'),
          op('context'),
        );
      case 'attitude':
        f.allow({'kind', 'holder', 'proposition', 'attitude'});
        return AttitudeExpr(
          RecordRef.fromCanonical(f.require('holder')),
          RecordRef.fromCanonical(f.require('proposition')),
          EpistemicAttitudeKind.fromName(f.string('attitude')),
        );
      case 'lit':
        f.allow({'kind', 'value'});
        return LiteralExpr(f.boolean('value'));
      case 'not':
        f.allow({'kind', 'expr'});
        return NotExpr(child('expr'));
      case 'all':
        f.allow({'kind', 'exprs'});
        return AllExpr(children());
      case 'any':
        f.allow({'kind', 'exprs'});
        return AnyExpr(children());
      case 'claim':
        f.allow({
          'kind',
          'subject',
          'predicate',
          'roles',
          'value',
          'polarity',
          'context',
        });
        return ClaimExpr(
          subject: op('subject'),
          predicate: f.string('predicate'),
          roles: _exprRoles(f),
          value: _optionalOperand(f, 'value'),
          context: _optionalOperand(f, 'context'),
          polarity: Polarity.fromWire(f.require('polarity')),
        );
      case 'negated_claim':
        f.allow({'kind', 'subject', 'predicate', 'roles', 'value', 'context'});
        return NegatedClaimExpr(
          subject: op('subject'),
          predicate: f.string('predicate'),
          roles: _exprRoles(f),
          value: _optionalOperand(f, 'value'),
          context: _optionalOperand(f, 'context'),
        );
      case 'existence':
        f.allow({'kind', 'subject', 'predicate', 'roles', 'value', 'context'});
        return ExistenceExpr(
          subject: op('subject'),
          predicate: f.string('predicate'),
          roles: _exprRoles(f),
          value: _optionalOperand(f, 'value'),
          context: _optionalOperand(f, 'context'),
        );
      case 'compare':
        f.allow({'kind', 'left', 'op', 'right'});
        return CompareExpr(
          op('left'),
          Comparator.fromName(f.string('op')),
          op('right'),
        );
      case 'temporal':
        f.allow({'kind', 'left', 'relation', 'right'});
        final relation = TemporalRelation.values.firstWhere(
          (r) => r.name == f.string('relation'),
          orElse: () =>
              throw const FormatException('Unknown temporal relation'),
        );
        return TemporalExpr(op('left'), relation, op('right'));
      case 'membership':
        f.allow({'kind', 'element', 'collection', 'complete'});
        return MembershipExpr(
          op('element'),
          op('collection'),
          _optionalBool(f, 'complete'),
        );
      case 'cardinality':
        f.allow({'kind', 'collection', 'op', 'count', 'complete'});
        return CardinalityExpr(
          op('collection'),
          Comparator.fromName(f.string('op')),
          DomainValue.fromWire(f.require('count')),
          _optionalBool(f, 'complete'),
        );
      case 'quantify':
        f.allow({'kind', 'variable', 'over', 'complete', 'quantifier', 'body'});
        return QuantifyExpr(
          variable: f.string('variable'),
          over: op('over'),
          complete: f.boolean('complete'),
          quantifier: Quantifier.fromName(f.string('quantifier')),
          body: child('body'),
        );
      case 'role_holds':
        f.allow({'kind', 'subject', 'predicate', 'role', 'participant'});
        return RoleHoldsExpr(
          op('subject'),
          f.string('predicate'),
          f.string('role'),
          op('participant'),
        );
      default:
        throw const FormatException('Unknown expression');
    }
  }
}

final class NoOpposingEvidenceExpr extends Expr {
  const NoOpposingEvidenceExpr(this.subject, this.predicate, this.context);
  final Operand subject, context;
  final String predicate;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('no_opposing_evidence', [
        MapEntry('subject', subject.toWire()),
        MapEntry('predicate', CanonicalString(predicate)),
        MapEntry('context', context.toWire()),
      ]);
}

final class AttitudeExpr extends Expr {
  const AttitudeExpr(this.holder, this.proposition, this.attitude);
  final RecordRef holder, proposition;
  final EpistemicAttitudeKind attitude;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('attitude', [
    MapEntry('holder', holder.toCanonical()),
    MapEntry('proposition', proposition.toCanonical()),
    MapEntry('attitude', CanonicalString(attitude.name)),
  ]);
}

final class LiteralExpr extends Expr {
  const LiteralExpr(this.value);
  final bool value;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('lit', [MapEntry('value', CanonicalBool(value))]);
}

final class NotExpr extends Expr {
  const NotExpr(this.expr);
  final Expr expr;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('not', [MapEntry('expr', expr.encode(canonical: canonical))]);
}

final class AllExpr extends Expr {
  AllExpr(Iterable<Expr> exprs) : exprs = List.unmodifiable(exprs);
  final List<Expr> exprs;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('all', [
    MapEntry(
      'exprs',
      CanonicalArray(exprs.map((e) => e.encode(canonical: canonical))),
    ),
  ]);
}

final class AnyExpr extends Expr {
  AnyExpr(Iterable<Expr> exprs) : exprs = List.unmodifiable(exprs);
  final List<Expr> exprs;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('any', [
    MapEntry(
      'exprs',
      CanonicalArray(exprs.map((e) => e.encode(canonical: canonical))),
    ),
  ]);
}

final class ExprRole {
  const ExprRole(this.role, this.operand);
  final String role;
  final Operand operand;
  CanonicalValue encode({required bool canonical}) => canonical
      ? CanonicalObject([
          MapEntry('role', CanonicalString(role)),
          MapEntry('operand', operand.toCanonical()),
        ])
      : CanonicalArray([CanonicalString(role), operand.toWire()]);
}

sealed class _ClaimExpr extends Expr {
  _ClaimExpr({
    required this.subject,
    required this.predicate,
    required Iterable<ExprRole> roles,
    this.value,
    this.context,
  }) : roles = List.unmodifiable(roles);
  final Operand subject;
  final String predicate;
  final List<ExprRole> roles;
  final Operand? value, context;
  String get kind;
  Polarity? get polarity => null;
  @override
  CanonicalObject encode({required bool canonical}) => tagged(kind, [
    MapEntry('subject', subject.encode(canonical: canonical)),
    MapEntry('predicate', CanonicalString(predicate)),
    if (polarity != null) MapEntry('polarity', polarity!.toWire()),
    if (roles.isNotEmpty)
      MapEntry(
        'roles',
        CanonicalArray(roles.map((r) => r.encode(canonical: canonical))),
      ),
    if (value != null) MapEntry('value', value!.encode(canonical: canonical)),
    if (context != null)
      MapEntry('context', context!.encode(canonical: canonical)),
  ]);
}

final class ClaimExpr extends _ClaimExpr {
  ClaimExpr({
    required super.subject,
    required super.predicate,
    super.roles = const [],
    super.value,
    super.context,
    required this.polarity,
  });
  @override
  final Polarity polarity;
  @override
  String get kind => 'claim';
}

final class NegatedClaimExpr extends _ClaimExpr {
  NegatedClaimExpr({
    required super.subject,
    required super.predicate,
    super.roles = const [],
    super.value,
    super.context,
  });
  @override
  String get kind => 'negated_claim';
}

final class ExistenceExpr extends _ClaimExpr {
  ExistenceExpr({
    required super.subject,
    required super.predicate,
    super.roles = const [],
    super.value,
    super.context,
  });
  @override
  String get kind => 'existence';
}

final class CompareExpr extends Expr {
  const CompareExpr(this.left, this.op, this.right);
  final Operand left, right;
  final Comparator op;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('compare', [
    MapEntry('left', left.encode(canonical: canonical)),
    MapEntry('op', CanonicalString(canonical ? op.canonicalName : op.wireName)),
    MapEntry('right', right.encode(canonical: canonical)),
  ]);
}

final class TemporalExpr extends Expr {
  const TemporalExpr(this.left, this.relation, this.right);
  final Operand left, right;
  final TemporalRelation relation;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('temporal', [
    MapEntry('left', left.encode(canonical: canonical)),
    MapEntry('relation', CanonicalString(relation.name)),
    MapEntry('right', right.encode(canonical: canonical)),
  ]);
}

final class MembershipExpr extends Expr {
  const MembershipExpr(this.element, this.collection, this.complete);
  final Operand element, collection;
  final bool? complete;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('membership', [
    MapEntry('element', element.encode(canonical: canonical)),
    MapEntry('collection', collection.encode(canonical: canonical)),
    if (!canonical || complete != null)
      MapEntry(
        'complete',
        complete == null ? const CanonicalNull() : CanonicalBool(complete!),
      ),
  ]);
}

final class CardinalityExpr extends Expr {
  const CardinalityExpr(this.collection, this.op, this.count, this.complete);
  final Operand collection;
  final Comparator op;
  final DomainValue count;
  final bool? complete;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('cardinality', [
    MapEntry('collection', collection.encode(canonical: canonical)),
    MapEntry('op', CanonicalString(canonical ? op.canonicalName : op.wireName)),
    MapEntry('count', canonical ? count.toCanonical() : count.toWire()),
    if (!canonical || complete != null)
      MapEntry(
        'complete',
        complete == null ? const CanonicalNull() : CanonicalBool(complete!),
      ),
  ]);
}

final class QuantifyExpr extends Expr {
  const QuantifyExpr({
    required this.variable,
    required this.over,
    required this.complete,
    required this.quantifier,
    required this.body,
  });
  final String variable;
  final Operand over;
  final bool complete;
  final Quantifier quantifier;
  final Expr body;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('quantify', [
    MapEntry('variable', CanonicalString(variable)),
    MapEntry('over', over.encode(canonical: canonical)),
    MapEntry('complete', CanonicalBool(complete)),
    MapEntry(
      'quantifier',
      CanonicalString(
        canonical ? quantifier.canonicalName : quantifier.wireName,
      ),
    ),
    MapEntry('body', body.encode(canonical: canonical)),
  ]);
}

final class RoleHoldsExpr extends Expr {
  const RoleHoldsExpr(
    this.subject,
    this.predicate,
    this.role,
    this.participant,
  );
  final Operand subject, participant;
  final String predicate, role;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('role_holds', [
    MapEntry('subject', subject.encode(canonical: canonical)),
    MapEntry('predicate', CanonicalString(predicate)),
    MapEntry('role', CanonicalString(role)),
    MapEntry('participant', participant.encode(canonical: canonical)),
  ]);
}

Operand? _optionalOperand(Fields f, String key) =>
    f.values[key] == null || f.values[key] is CanonicalNull
    ? null
    : Operand.fromWire(f.require(key));
bool? _optionalBool(Fields f, String key) =>
    f.values[key] == null || f.values[key] is CanonicalNull
    ? null
    : f.boolean(key);
Iterable<ExprRole> _exprRoles(Fields f) => _array(f, 'roles').map((v) {
  if (v is! CanonicalArray || v.items.length != 2) {
    throw const FormatException('Expected role/operand pair');
  }
  return ExprRole(_string(v.items[0]), Operand.fromWire(v.items[1]));
});

final class ExprAnalysis {
  ExprAnalysis({
    required this.depth,
    required this.nodes,
    required Iterable<String> variables,
    required Iterable<String> predicates,
    required Iterable<RecordId> referencedRecords,
  }) : variables = List.unmodifiable(variables),
       predicates = List.unmodifiable(predicates),
       referencedRecords = List.unmodifiable(referencedRecords);
  final int depth, nodes;
  final List<String> variables, predicates;
  final List<RecordId> referencedRecords;
}

ExprAnalysis _analyze(Expr root) {
  var depth = 0;
  var nodes = 0;
  final scope = <String>{};
  final variables = <String>[];
  final predicates = <String>[];
  final records = <RecordId>[];
  void op(Operand operand) {
    if (operand is VariableOperand) {
      if (!scope.contains(operand.name)) {
        throw FormatException('Unbound variable: ${operand.name}');
      }
      if (!variables.contains(operand.name)) variables.add(operand.name);
    } else if (operand is RecordOperand) {
      if (!records.contains(operand.reference.record)) {
        records.add(operand.reference.record);
      }
    }
  }

  void walk(Expr e, int level) {
    if (level > 32) throw const FormatException('Expression depth exceeds 32');
    if (++nodes > 1000) {
      throw const FormatException('Expression node count exceeds 1000');
    }
    if (level > depth) depth = level;
    switch (e) {
      case NoOpposingEvidenceExpr():
        op(e.subject);
        op(e.context);
        predicates.add(e.predicate);
      case AttitudeExpr():
        records.add(e.holder.record);
        records.add(e.proposition.record);
      case LiteralExpr():
        break;
      case NotExpr():
        walk(e.expr, level + 1);
      case AllExpr():
        for (final child in e.exprs) {
          walk(child, level + 1);
        }
      case AnyExpr():
        for (final child in e.exprs) {
          walk(child, level + 1);
        }
      case _ClaimExpr():
        op(e.subject);
        predicates.add(e.predicate);
        for (final role in e.roles) {
          op(role.operand);
        }
        if (e.value != null) op(e.value!);
        if (e.context != null) op(e.context!);
      case CompareExpr():
        op(e.left);
        op(e.right);
      case TemporalExpr():
        op(e.left);
        op(e.right);
      case MembershipExpr():
        op(e.element);
        op(e.collection);
      case CardinalityExpr():
        op(e.collection);
      case QuantifyExpr():
        op(e.over);
        if (!scope.add(e.variable)) {
          throw FormatException('Duplicate quantifier binding: ${e.variable}');
        }
        if (!variables.contains(e.variable)) variables.add(e.variable);
        walk(e.body, level + 1);
        scope.remove(e.variable);
      case RoleHoldsExpr():
        op(e.subject);
        predicates.add(e.predicate);
        op(e.participant);
    }
  }

  walk(root, 1);
  return ExprAnalysis(
    depth: depth,
    // Preserve the existing domain summary. Rust enforces the local counter
    // above but leaves ExprAnalysis.nodes at zero. The rules compiler uses
    // its own operand-inclusive budget and must not use this summary field.
    nodes: 0,
    variables: variables,
    predicates: predicates,
    referencedRecords: records,
  );
}
