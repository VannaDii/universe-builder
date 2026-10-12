import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

RecordId id(int n) =>
    RecordId.parse('rec_${n.toRadixString(16).padLeft(24, '0')}');
WorldId world(int n) =>
    WorldId.parse('wld_${n.toRadixString(16).padLeft(24, '0')}');
const one = ValueOperand(IntegerValue('1'));
ValueOperand sequence(List<DomainValue> values) =>
    ValueOperand(SequenceValue(values));
CompiledRule rule(
  Expr expression, {
  Applicability scope = const UniverseApplicability(),
  bool executable = true,
}) => compileRule(
  id(1),
  RuleRecord(
    namespace: 'author',
    key: 'check',
    labels: {},
    kind: RuleKind.physicalConstraint,
    commitPolicy: RuleKind.physicalConstraint.defaultCommitPolicy,
    applicability: scope,
    targetPredicates: [],
    expression: expression,
    capabilities: [],
    executable: executable,
    validity: const UnspecifiedValidity(),
  ),
);
EvaluationResult run(Expr e) => evaluateRule(rule(e), EvaluationContext());
void outcome(Expr e, EvidenceOutcome expected) {
  final result = run(e);
  expect(result.outcome, expected);
  expect(result.coverage, EvaluationCoverage.complete);
}

void main() {
  test('literal, negation and connective execution keep evidence separate from coverage', () {
    outcome(const LiteralExpr(true), EvidenceOutcome.supported);
    outcome(const NotExpr(LiteralExpr(true)), EvidenceOutcome.refuted);
    outcome(AllExpr([]), EvidenceOutcome.supported);
    outcome(AnyExpr([]), EvidenceOutcome.refuted);
    outcome(
      AllExpr([const LiteralExpr(true), const LiteralExpr(false)]),
      EvidenceOutcome.refuted,
    );
    outcome(
      AnyExpr([const LiteralExpr(false), const LiteralExpr(true)]),
      EvidenceOutcome.supported,
    );
    final result = run(
      AnyExpr([
        const LiteralExpr(true),
        const CompareExpr(VariableOperand('missing'), Comparator.eq, one),
      ]),
    );
    expect(result.outcome, EvidenceOutcome.supported);
    expect(result.coverage, EvaluationCoverage.unsupported);
  });

  test('rule execution retains executable and applicability gates', () {
    final e = const LiteralExpr(true);
    for (final scope in [
      const ConditionalApplicability(),
      const UnspecifiedApplicability(),
      WorldsApplicability([world(1)]),
    ]) {
      expect(
        evaluateRule(rule(e, scope: scope), EvaluationContext()).coverage,
        EvaluationCoverage.unsupported,
      );
    }
    expect(
      evaluateRule(rule(e, executable: false), EvaluationContext()).outcome,
      EvidenceOutcome.notEstablished,
    );
    final scoped = rule(e, scope: WorldsApplicability([world(1)]));
    expect(
      evaluateRule(
        scoped,
        EvaluationContext(worldScope: [id(1), id(2)]),
      ).coverage,
      EvaluationCoverage.complete,
    );
    expect(
      evaluateRule(scoped, EvaluationContext(worldScope: [id(2)])).coverage,
      EvaluationCoverage.unsupported,
    );
    expect(
      evaluateRule(scoped, EvaluationContext(worldScope: [])).coverage,
      EvaluationCoverage.unsupported,
    );
  });

  test('exact comparisons and authored temporal relations execute without guessed operands', () {
    outcome(
      const CompareExpr(
        ValueOperand(DecimalValue('0.5')),
        Comparator.eq,
        ValueOperand(RationalValue('1', '2')),
      ),
      EvidenceOutcome.supported,
    );
    final clock = CalendarId.parse('cal_000000000000000000000001');
    outcome(
      TemporalExpr(
        ValueOperand(TemporalValue(ExactTime(clock, '10'))),
        TemporalRelation.before,
        ValueOperand(TemporalValue(ExactTime(clock, '11'))),
      ),
      EvidenceOutcome.supported,
    );
    expect(
      run(const CompareExpr(FrameTimeOperand(), Comparator.eq, one)).coverage,
      EvaluationCoverage.unsupported,
    );
    expect(
      run(const TemporalExpr(one, TemporalRelation.before, one)).coverage,
      EvaluationCoverage.unsupported,
    );
  });

  test('membership needs completeness only to refute an absent member', () {
    final values = sequence([const DecimalValue('1.0')]);
    outcome(MembershipExpr(one, values, false), EvidenceOutcome.supported);
    outcome(
      MembershipExpr(const ValueOperand(IntegerValue('2')), values, null),
      EvidenceOutcome.notEstablished,
    );
    outcome(
      MembershipExpr(const ValueOperand(IntegerValue('2')), values, true),
      EvidenceOutcome.refuted,
    );
    final reference = RecordRef(record: id(9));
    outcome(
      MembershipExpr(
        RecordOperand(reference),
        sequence([ReferenceValue(ValueReferenceKind.record, reference)]),
        null,
      ),
      EvidenceOutcome.supported,
    );
  });

  test(
    'sets deduplicate wire-identical values while sequences retain repetitions',
    () {
      const values = [
        IntegerValue('1'),
        IntegerValue('1'),
        IntegerValue('01'),
        DecimalValue('1.0'),
      ];
      outcome(
        CardinalityExpr(
          ValueOperand(SetValue(values)),
          Comparator.eq,
          const IntegerValue('3'),
          true,
        ),
        EvidenceOutcome.supported,
      );
      outcome(
        CardinalityExpr(
          sequence(values),
          Comparator.eq,
          const IntegerValue('4'),
          true,
        ),
        EvidenceOutcome.supported,
      );
    },
  );

  test('incomplete cardinality retains only monotone conclusions', () {
    final values = sequence([const IntegerValue('1'), const IntegerValue('2')]);
    outcome(
      CardinalityExpr(values, Comparator.gtEq, const IntegerValue('2'), false),
      EvidenceOutcome.supported,
    );
    outcome(
      CardinalityExpr(values, Comparator.lt, const IntegerValue('2'), false),
      EvidenceOutcome.refuted,
    );
    outcome(
      CardinalityExpr(values, Comparator.eq, const IntegerValue('2'), false),
      EvidenceOutcome.notEstablished,
    );
    outcome(
      CardinalityExpr(values, Comparator.gt, const IntegerValue('2'), false),
      EvidenceOutcome.notEstablished,
    );
  });

  test(
    'quantification respects completeness, witnesses and counterexamples',
    () {
      final values = sequence([
        const IntegerValue('1'),
        const IntegerValue('2'),
      ]);
      const body = CompareExpr(VariableOperand('x'), Comparator.eq, one);
      Expr quantified(Quantifier q, bool complete, Operand over) =>
          QuantifyExpr(
            variable: 'x',
            over: over,
            complete: complete,
            quantifier: q,
            body: body,
          );
      outcome(
        quantified(Quantifier.forAll, false, values),
        EvidenceOutcome.refuted,
      );
      outcome(
        quantified(Quantifier.exists, false, values),
        EvidenceOutcome.supported,
      );
      outcome(
        quantified(
          Quantifier.forAll,
          false,
          sequence([const IntegerValue('1')]),
        ),
        EvidenceOutcome.notEstablished,
      );
      outcome(
        quantified(
          Quantifier.exists,
          false,
          sequence([const IntegerValue('2')]),
        ),
        EvidenceOutcome.notEstablished,
      );
      outcome(
        quantified(Quantifier.forAll, true, sequence([])),
        EvidenceOutcome.supported,
      );
      outcome(
        quantified(Quantifier.exists, true, sequence([])),
        EvidenceOutcome.refuted,
      );
    },
  );

  test('nested variable shadowing restores outer bindings', () {
    outcome(
      QuantifyExpr(
        variable: 'x',
        over: sequence([const IntegerValue('1'), const IntegerValue('2')]),
        complete: true,
        quantifier: Quantifier.forAll,
        body: AllExpr([
          QuantifyExpr(
            variable: 'x',
            over: sequence([const IntegerValue('9')]),
            complete: true,
            quantifier: Quantifier.forAll,
            body: const CompareExpr(
              VariableOperand('x'),
              Comparator.eq,
              ValueOperand(IntegerValue('9')),
            ),
          ),
          const CompareExpr(
            VariableOperand('x'),
            Comparator.lt,
            ValueOperand(IntegerValue('3')),
          ),
        ]),
      ),
      EvidenceOutcome.supported,
    );
  });

  test(
    'work budget applies across collection traversal and nested quantifiers',
    () {
      final values = List<DomainValue>.filled(9999, const IntegerValue('1'));
      final (_, allowed) = evaluateExpression(
        MembershipExpr(one, sequence(values), true),
        EvaluationContext(),
      );
      expect(allowed, isTrue);
      final (_, exhausted) = evaluateExpression(
        MembershipExpr(
          one,
          sequence([...values, const IntegerValue('1')]),
          true,
        ),
        EvaluationContext(),
      );
      expect(exhausted, isFalse);
      final hundred = sequence(
        List<DomainValue>.filled(100, const IntegerValue('1')),
      );
      final nested = QuantifyExpr(
        variable: 'a',
        over: hundred,
        complete: true,
        quantifier: Quantifier.forAll,
        body: QuantifyExpr(
          variable: 'b',
          over: hundred,
          complete: true,
          quantifier: Quantifier.forAll,
          body: const LiteralExpr(true),
        ),
      );
      expect(run(nested).coverage, EvaluationCoverage.unsupported);
    },
  );

  test(
    'factual claims without a selected frame cannot claim a completed check',
    () {
      final result = run(
        ClaimExpr(
          subject: RecordOperand(RecordRef(record: id(9))),
          predicate: 'author:age',
          polarity: Polarity.support,
        ),
      );
      expect(result.outcome, EvidenceOutcome.notEstablished);
      expect(result.coverage, EvaluationCoverage.unsupported);
    },
  );
}
