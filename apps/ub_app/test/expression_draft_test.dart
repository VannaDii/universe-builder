import 'package:test/test.dart';
import 'package:ub_app/expression_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'every expression and operand kind preserves exact authored wire semantics',
    () {
      final reference = RecordRef(
        record: RecordId.generate(),
        universe: UniverseId.generate(),
      );
      final subject = RecordOperand(reference);
      const variable = VariableOperand('person 記憶 😀');
      final values = <Operand>[
        variable,
        subject,
        ValueOperand(IntegerValue('9007199254740993')),
        const FrameTimeOperand(),
        const EventParticipantOperand('witness'),
        const EventRefOperand(),
      ];
      for (final operand in values) {
        final input = OperandInput.fromWire(operandInput(operand).toWire());
        expect(
          buildOperand(input).toWire().toText(),
          operand.toWire().toText(),
        );
      }
      final expressions = <Expr>[
        const LiteralExpr(false),
        const NotExpr(LiteralExpr(true)),
        AllExpr([const LiteralExpr(true), const LiteralExpr(false)]),
        AnyExpr([const LiteralExpr(false)]),
        NoOpposingEvidenceExpr(
          subject,
          'authored:account',
          const FrameTimeOperand(),
        ),
        AttitudeExpr(
          reference,
          RecordRef(record: RecordId.generate()),
          EpistemicAttitudeKind.values.first,
        ),
        ClaimExpr(
          subject: subject,
          predicate: 'authored:relation',
          roles: [ExprRole('speaker', variable), ExprRole('speaker', subject)],
          value: values[2],
          context: const FrameTimeOperand(),
          polarity: Polarity.refutation,
        ),
        NegatedClaimExpr(subject: subject, predicate: 'authored:claim'),
        ExistenceExpr(subject: variable, predicate: 'authored:claim'),
        CompareExpr(
          values[2],
          Comparator.ltEq,
          ValueOperand(IntegerValue('9007199254740994')),
        ),
        TemporalExpr(
          const EventRefOperand(),
          TemporalRelation.before,
          const FrameTimeOperand(),
        ),
        MembershipExpr(subject, variable, null),
        CardinalityExpr(
          variable,
          Comparator.gtEq,
          IntegerValue('9007199254740993'),
          false,
        ),
        QuantifyExpr(
          variable: 'person 記憶 😀',
          over: subject,
          complete: true,
          quantifier: Quantifier.forAll,
          body: ClaimExpr(
            subject: variable,
            predicate: 'authored:claim',
            polarity: Polarity.support,
          ),
        ),
        RoleHoldsExpr(subject, 'authored:relation', 'witness', variable),
      ];
      for (final expression in expressions) {
        final recovered = ExpressionInput.fromWire(
          expressionInput(expression).toWire(),
        );
        final built = buildExpression(recovered);
        expect(built.toWire().toText(), expression.toWire().toText());
        expect(built.usesOpposingEvidence, expression.usesOpposingEvidence);
      }
    },
  );
  test(
    'unfinished condition inputs stay unfinished rather than becoming false',
    () {
      final input = ExpressionInput(kind: 'lit', flags: {'value': null});
      final restored = ExpressionInput.fromWire(input.toWire());
      expect(restored.flags['value'], isNull);
      expect(() => buildExpression(restored), throwsFormatException);
      final incomplete = OperandInput(
        kind: 'record',
        reference: const ExpressionReferenceInput(record: 'unfinished'),
      );
      expect(
        OperandInput.fromWire(incomplete.toWire()).reference.record,
        'unfinished',
      );
      expect(() => buildOperand(incomplete), throwsFormatException);
    },
  );
}
