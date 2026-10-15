import 'package:test/test.dart';
import 'package:ub_app/world_evidence_policies.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final a = WorldId.generate(), b = WorldId.generate();
  RuleRecord rule(Applicability applicability, {bool evidence = true}) =>
      RuleRecord(
        namespace: 'authored',
        key: 'historical_basis',
        labels: {},
        kind: RuleKind.authorialRestriction,
        commitPolicy: CommitPolicy.alwaysBlock,
        applicability: applicability,
        targetPredicates: [],
        expression: const LiteralExpr(true),
        capabilities: [],
        executable: true,
        validity: const UnspecifiedValidity(),
        requiredEvidence: evidence
            ? RequiredEvidence(
                sourceCategories: [
                  VersionRef(
                    record: RecordId.generate(),
                    version: RecordVersionId.generate(),
                  ),
                ],
              )
            : null,
      );
  test('world policy display distinguishes inheritance, selection and unresolved scope', () {
    expect(
      worldEvidencePolicyOrigin(rule(const UniverseApplicability()), a),
      WorldPolicyOrigin.universe,
    );
    expect(
      worldEvidencePolicyOrigin(rule(WorldsApplicability([a, b])), a),
      WorldPolicyOrigin.selectedWorld,
    );
    expect(
      worldEvidencePolicyOrigin(rule(WorldsApplicability([b])), a),
      isNull,
    );
    expect(worldEvidencePolicyOrigin(rule(WorldsApplicability([])), a), isNull);
    expect(
      worldEvidencePolicyOrigin(rule(const ConditionalApplicability()), a),
      WorldPolicyOrigin.unresolved,
    );
    expect(
      worldEvidencePolicyOrigin(rule(const UnspecifiedApplicability()), a),
      WorldPolicyOrigin.unresolved,
    );
    expect(
      worldEvidencePolicyOrigin(
        rule(const UniverseApplicability(), evidence: false),
        a,
      ),
      isNull,
    );
  });
}
