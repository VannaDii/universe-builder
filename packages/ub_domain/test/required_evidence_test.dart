import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

final category = VersionRef(
  universe: UniverseId.parse('unv_${'1'.padLeft(24, '0')}'),
  record: RecordId.parse('rec_${'2'.padLeft(24, '0')}'),
  version: RecordVersionId.parse('ver_${'3'.padLeft(24, '0')}'),
);
RuleRecord rule({RequiredEvidence? evidence}) => RuleRecord(
  requiredEvidence: evidence,
  namespace: 'real_world',
  key: 'historical_facts',
  labels: {'en': 'Historical facts'},
  kind: RuleKind.authorialRestriction,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability: const UniverseApplicability(),
  targetPredicates: ['history:birth_date'],
  expression: const LiteralExpr(true),
  capabilities: [],
  executable: true,
  validity: const UnspecifiedValidity(),
);
void main() {
  test('review is optional and source categories retain exact published identities', () {
    for (final methods in [
      <EvidenceReviewMethod>[],
      EvidenceReviewMethod.values,
    ]) {
      final sourceCategories = [category], choices = methods.toList();
      final policy = RequiredEvidence(
        sourceCategories: sourceCategories,
        reviewMethods: choices,
      );
      sourceCategories.clear();
      choices.clear();
      final original = rule(evidence: policy),
          decoded = RuleRecord.fromWire(original.toWire());
      expect(decoded.toWire().toText(), original.toWire().toText());
      expect(decoded.digest, original.digest);
      expect(
        decoded.requiredEvidence!.sourceCategories.single
            .toCanonical()
            .toText(),
        category.toCanonical().toText(),
      );
      expect(decoded.requiredEvidence!.reviewMethods, methods);
      expect(() => policy.reviewMethods.clear(), throwsUnsupportedError);
      expect(() => policy.sourceCategories.clear(), throwsUnsupportedError);
    }
  });
  test('ordinary rules retain absence and closed policy fields reject unknown claims', () {
    final ordinary = rule();
    expect(
      ordinary.toWire().fields.map((f) => f.key),
      isNot(contains('requiredEvidence')),
    );
    expect(RuleRecord.fromWire(ordinary.toWire()).digest, ordinary.digest);
    expect(
      () => RequiredEvidence.fromWire(
        CanonicalValue.parseWireJson(
          '{"sourceCategories":[],"reviewMethods":["automatically_true"]}',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => RequiredEvidence.fromWire(
        CanonicalValue.parseWireJson(
          '{"sourceCategories":[],"realityVerified":true}',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => RequiredEvidence.fromWire(
        CanonicalValue.parseWireJson('{"reviewMethods":[]}'),
      ),
      throwsFormatException,
    );
  });
}
