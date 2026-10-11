import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  RecordRef ref(int n) =>
      RecordRef(record: RecordId.parse('rec_${n.toString().padLeft(24, '0')}'));
  final subject = RecordOperand(ref(1));
  final literal = ValueOperand(const IntegerValue('0002'));
  test(
    'all expression and operand branches decode to immutable typed syntax',
    () {
      final operands = <Operand>[
        const VariableOperand('actor'),
        subject,
        literal,
        const FrameTimeOperand(),
        const EventParticipantOperand('actor'),
        const EventRefOperand(),
      ];
      for (final operand in operands) {
        expect(Operand.fromWire(operand.toWire()), operand);
      }
      final exprs = <Expr>[
        NoOpposingEvidenceExpr(subject, 'author:owns', subject),
        AttitudeExpr(ref(1), ref(2), EpistemicAttitudeKind.suspects),
        const LiteralExpr(false),
        const NotExpr(LiteralExpr(true)),
        AllExpr([]),
        AnyExpr([]),
        ClaimExpr(
          subject: subject,
          predicate: 'author:owns',
          polarity: Polarity.refutation,
          roles: [ExprRole('holder', subject)],
          value: literal,
        ),
        NegatedClaimExpr(subject: subject, predicate: 'author:owns'),
        ExistenceExpr(subject: subject, predicate: 'author:owns'),
        CompareExpr(literal, Comparator.gtEq, literal),
        TemporalExpr(
          const FrameTimeOperand(),
          TemporalRelation.overlaps,
          const FrameTimeOperand(),
        ),
        MembershipExpr(literal, literal, false),
        CardinalityExpr(literal, Comparator.neq, const IntegerValue('2'), null),
        QuantifyExpr(
          variable: 'actor',
          over: literal,
          complete: false,
          quantifier: Quantifier.exists,
          body: const LiteralExpr(true),
        ),
        RoleHoldsExpr(subject, 'author:owns', 'holder', subject),
      ];
      for (final expr in exprs) {
        expect(Expr.fromWire(expr.toWire()), expr);
      }
      final children = [const LiteralExpr(true)];
      final all = AllExpr(children);
      children.clear();
      expect(all.exprs, hasLength(1));
      expect(() => all.exprs.clear(), throwsUnsupportedError);
      expect(
        () => (exprs[6] as ClaimExpr).roles.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('wire roles, comparators and completeness retain their independent comparison encoding', () {
    final claim = ClaimExpr(
      subject: subject,
      predicate: 'owns',
      roles: [ExprRole('holder', subject)],
      polarity: Polarity.support,
    );
    expect(claim.toWire().toText(), contains('"roles":[["holder",'));
    expect(claim.toCanonical().toText(), contains('"roles":[{"operand":'));
    expect(
      CompareExpr(literal, Comparator.ltEq, literal).toWire().toText(),
      contains('"op":"lt_eq"'),
    );
    expect(
      CompareExpr(literal, Comparator.ltEq, literal).toCanonical().toText(),
      contains('"op":"lte"'),
    );
    final quantifier = QuantifyExpr(
      variable: 'x',
      over: literal,
      complete: false,
      quantifier: Quantifier.forAll,
      body: const LiteralExpr(true),
    );
    expect(quantifier.toWire().toText(), contains('"quantifier":"for_all"'));
    expect(
      quantifier.toCanonical().toText(),
      contains('"quantifier":"forall"'),
    );
    final member = MembershipExpr(literal, literal, null);
    expect(member.toWire().toText(), contains('"complete":null'));
    expect(member.toCanonical().toText(), isNot(contains('"complete"')));
    expect(
      MembershipExpr(literal, literal, false).toCanonical().toText(),
      contains('"complete":false'),
    );
  });
  test('analysis enforces exact depth and expression-node bounds', () {
    Expr deep = const LiteralExpr(true);
    for (var i = 0; i < 31; i++) {
      deep = NotExpr(deep);
    }
    expect(deep.analyze().depth, 32);
    expect(deep.analyze().nodes, 0);
    expect(() => NotExpr(deep).analyze(), throwsFormatException);
    final bounded = AllExpr(List.filled(999, const LiteralExpr(true)));
    expect(bounded.analyze().depth, 2);
    expect(
      () => AllExpr(List.filled(1000, const LiteralExpr(true))).analyze(),
      throwsFormatException,
    );
  });
  test('quantifiers bind locally, reject shadowing and cannot use their own variable in the domain', () {
    Expr binding(Expr body, {Operand? over}) => QuantifyExpr(
      variable: 'x',
      over: over ?? literal,
      complete: false,
      quantifier: Quantifier.forAll,
      body: body,
    );
    final use = ClaimExpr(
      subject: const VariableOperand('x'),
      predicate: 'p',
      polarity: Polarity.support,
    );
    expect(binding(use).analyze().variables, ['x']);
    expect(() => use.analyze(), throwsFormatException);
    expect(() => binding(binding(use)).analyze(), throwsFormatException);
    expect(
      () => binding(use, over: const VariableOperand('x')).analyze(),
      throwsFormatException,
    );
    expect(AllExpr([binding(use), binding(use)]).analyze().predicates, [
      'p',
      'p',
    ]);
    expect(() => AllExpr([binding(use), use]).analyze(), throwsFormatException);
  });
  test('analysis retains source traversal order and opposing-evidence use without asserting truth', () {
    final noOpposition = NoOpposingEvidenceExpr(subject, 'p', subject);
    final expr = AllExpr([
      noOpposition,
      AttitudeExpr(ref(1), ref(1), EpistemicAttitudeKind.remembers),
      RoleHoldsExpr(subject, 'p', 'holder', subject),
    ]);
    final analysis = expr.analyze();
    expect(analysis.referencedRecords, [
      ref(1).record,
      ref(1).record,
      ref(1).record,
    ]);
    expect(analysis.predicates, ['p', 'p']);
    expect(expr.usesOpposingEvidence, isTrue);
    expect(const NotExpr(LiteralExpr(false)).usesOpposingEvidence, isFalse);
    expect(() => analysis.predicates.clear(), throwsUnsupportedError);
  });
  test('strict expression decoding rejects unknown branches, malformed pairs and comparison-only spellings', () {
    for (final text in [
      '{"kind":"lit","value":true,"invented":false}',
      '{"kind":"not","expr":null}',
      '{"kind":"all","exprs":null}',
      '{"kind":"claim","subject":${subject.toWire().toText()},"predicate":"p","polarity":"support","roles":[["holder"]]}',
      '{"kind":"claim","subject":${subject.toWire().toText()},"predicate":"p","polarity":"support","roles":[{"role":"holder","operand":${subject.toWire().toText()}}]}',
      '{"kind":"invented"}',
    ]) {
      expect(
        () => Expr.fromWire(CanonicalValue.parseJson(text)),
        throwsFormatException,
      );
    }
    expect(() => Comparator.fromName('lte'), throwsFormatException);
    expect(() => Quantifier.fromName('forall'), throwsFormatException);
  });
  test('plans and commitments keep expressions as declarations without automatic consequences', () {
    final prerequisites = [const LiteralExpr(false)];
    final goal = GoalRecord(
      actor: ref(1),
      prerequisites: prerequisites,
      steps: [ref(2)],
      status: PlanStatus.active,
      validity: const UnknownValidity(),
    );
    prerequisites.clear();
    expect(RecordPayload.fromWire(goal.toWire()), goal);
    expect(goal.desired, isNull);
    expect(goal.prerequisites.single, const LiteralExpr(false));
    expect(() => goal.steps.clear(), throwsUnsupportedError);
    for (final status in CommitmentStatus.values) {
      final commitment = CommitmentRecord(
        parties: [
          CommitmentParty(ref(1), 'promisor'),
          CommitmentParty(ref(2), 'recipient'),
        ],
        obligated: ref(3),
        conditions: [const LiteralExpr(true)],
        status: status,
      );
      expect(RecordPayload.fromWire(commitment.toWire()), commitment);
      expect(commitment.deadline, isNull);
      expect(commitment.toWire().toText(), contains('"deadline":null'));
      expect(() => commitment.conditions.clear(), throwsUnsupportedError);
    }
  });
}
