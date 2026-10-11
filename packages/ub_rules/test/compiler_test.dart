import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

void main() {
  RecordId id(int n) => RecordId.parse('rec_${n.toString().padLeft(24, '0')}');
  Operand ref(int n) => RecordOperand(RecordRef(record: id(n)));
  RuleRecord rule(
    Expr expr, {
    RuleKind kind = RuleKind.physicalConstraint,
    bool executable = true,
  }) => RuleRecord(
    namespace: 'author',
    key: 'test',
    labels: {},
    kind: kind,
    commitPolicy: kind.defaultCommitPolicy,
    applicability: const ConditionalApplicability(),
    targetPredicates: [],
    expression: expr,
    capabilities: ['not-yet-implemented'],
    executable: executable,
    validity: const UnknownValidity(),
  );
  test('compiler retains declarations and disables descriptive execution without granting capabilities', () {
    final compiled = compileRule(id(1), rule(const LiteralExpr(false)));
    expect(compiled.nodeCount, 1);
    expect(compiled.applicability, const ConditionalApplicability());
    expect(compiled.expression, const LiteralExpr(false));
    expect(compiled.executable, isTrue);
    expect(
      compileRule(
        id(1),
        rule(const LiteralExpr(true), kind: RuleKind.descriptive),
      ).executable,
      isFalse,
    );
    expect(
      compileRule(
        id(1),
        rule(const LiteralExpr(true), executable: false),
      ).executable,
      isFalse,
    );
    expect(
      () => compileRule(id(1), WorldRecord(selector: 'test')),
      throwsA(isA<NotARule>()),
    );
  });
  test(
    'compiler counts operands and preserves existing special branch metrics',
    () {
      final cases = <(Expr, int)>[
        (NoOpposingEvidenceExpr(ref(1), 'p', ref(2)), 3),
        (
          AttitudeExpr(
            RecordRef(record: id(1)),
            RecordRef(record: id(2)),
            EpistemicAttitudeKind.knows,
          ),
          1,
        ),
        (
          ClaimExpr(
            subject: ref(1),
            predicate: 'p',
            roles: [ExprRole('r', ref(2)), ExprRole('r', ref(2))],
            value: ref(3),
            context: ref(4),
            polarity: Polarity.support,
          ),
          5,
        ),
        (NegatedClaimExpr(subject: ref(1), predicate: 'p'), 2),
        (ExistenceExpr(subject: ref(1), predicate: 'p'), 2),
        (CompareExpr(ref(1), Comparator.eq, ref(2)), 3),
        (TemporalExpr(ref(1), TemporalRelation.before, ref(2)), 3),
        (MembershipExpr(ref(1), ref(2), null), 3),
        (
          CardinalityExpr(ref(1), Comparator.eq, const IntegerValue('1'), null),
          2,
        ),
        (RoleHoldsExpr(ref(1), 'p', 'role', ref(2)), 1),
        (
          QuantifyExpr(
            variable: 'x',
            over: ref(1),
            complete: false,
            quantifier: Quantifier.exists,
            body: const LiteralExpr(true),
          ),
          3,
        ),
      ];
      for (final (expr, nodes) in cases) {
        expect(compileRule(id(1), rule(expr)).nodeCount, nodes);
      }
    },
  );
  test('compiler deduplicates and sorts explicit record operands, excluding claim context as in Rust', () {
    final expr = AllExpr([
      ClaimExpr(
        subject: ref(3),
        predicate: 'p',
        roles: [ExprRole('r', ref(2))],
        value: ref(3),
        context: ref(9),
        polarity: Polarity.support,
      ),
      RoleHoldsExpr(ref(1), 'p', 'r', ref(2)),
      NoOpposingEvidenceExpr(ref(4), 'p', ref(5)),
    ]);
    final compiled = compileRule(id(1), rule(expr));
    expect(compiled.referencedRecords, [id(1), id(2), id(3), id(4), id(5)]);
    expect(() => compiled.referencedRecords.clear(), throwsUnsupportedError);
    // Canonical reference admission still checks context refs separately.
    expect(compiled.referencedRecords, isNot(contains(id(9))));
  });
  test(
    'exact compiler node limit includes operands and fails before depth checks',
    () {
      final bounded = AllExpr(
        List.filled(333, CompareExpr(ref(1), Comparator.eq, ref(2))),
      );
      expect(compileRule(id(1), rule(bounded)).nodeCount, 1000);
      final oversized = AllExpr(
        List.filled(334, CompareExpr(ref(1), Comparator.eq, ref(2))),
      );
      expect(
        () => compileRule(id(1), rule(oversized)),
        throwsA(
          isA<RuleNodeCountExceeded>().having(
            (e) => e.currentCount,
            'count',
            1003,
          ),
        ),
      );
    },
  );
  test(
    'depth metric preserves operand contributions and quantifier increments',
    () {
      Expr expr = CompareExpr(ref(1), Comparator.eq, ref(2));
      for (var n = 0; n < 29; n++) {
        expr = NotExpr(expr);
      }
      compileRule(id(1), rule(expr));
      expect(
        () => compileRule(id(1), rule(NotExpr(expr))),
        throwsA(
          isA<RuleDepthExceeded>().having((e) => e.currentDepth, 'depth', 33),
        ),
      );
      // Compilation is separate from domain quantifier scope analysis.
      compileRule(
        id(1),
        rule(
          ClaimExpr(
            subject: const VariableOperand('external'),
            predicate: 'p',
            polarity: Polarity.support,
          ),
        ),
      );
    },
  );
}
