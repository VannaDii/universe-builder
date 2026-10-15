import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/structural_checks.dart';

import 'operation_compilation_test.dart' as f;

void main() {
  test('an ordinary true expression never stands in for required evidence admission', () {
    final ordinary = RuleRecord(
      namespace: 'real_world',
      key: 'history',
      labels: {},
      kind: RuleKind.authorialRestriction,
      commitPolicy: CommitPolicy.alwaysBlock,
      applicability: const UniverseApplicability(),
      targetPredicates: [],
      expression: const LiteralExpr(true),
      capabilities: [],
      executable: true,
      validity: const UnspecifiedValidity(),
    );
    validateStructuralCandidate([f.row(1, ordinary)]);
    for (final methods in [
      <EvidenceReviewMethod>[],
      EvidenceReviewMethod.values,
    ]) {
      final guarded = RuleRecord.fromWire(
        CanonicalObject([
          ...ordinary.toWire().fields,
          MapEntry(
            'requiredEvidence',
            RequiredEvidence(
              sourceCategories: [
                VersionRef(universe: f.u, record: f.id(2), version: f.ver(2)),
              ],
              reviewMethods: methods,
            ).toWire(),
          ),
        ]),
      );
      expect(
        () => validateStructuralCandidate([f.row(1, guarded)]),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
  });
}
