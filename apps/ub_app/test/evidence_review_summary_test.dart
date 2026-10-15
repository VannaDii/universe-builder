import 'package:test/test.dart';
import 'package:ub_app/evidence_review_summary.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final universe = UniverseId.generate();
  RecordVersion row(RecordPayload payload, {RecordId? id}) =>
      RecordVersion.build(
        recordVersionId: RecordVersionId.generate(),
        identity: RecordIdentity(
          universeId: universe,
          recordId: id ?? RecordId.generate(),
          recordKind: payload.recordKind,
        ),
        payload: payload,
      );
  final category = row(
    DomainPackRecord(
      key: 'private recollections',
      version: '1',
      dependencies: {},
      capabilities: [],
      records: [],
    ),
  );
  RuleRecord policy({
    List<EvidenceReviewMethod> methods = const [],
    Applicability applicability = const UniverseApplicability(),
  }) => RuleRecord(
    namespace: 'authored',
    key: 'sources',
    labels: {'en': 'Memoir sources'},
    kind: RuleKind.authorialRestriction,
    commitPolicy: CommitPolicy.alwaysBlock,
    applicability: applicability,
    targetPredicates: [],
    expression: const LiteralExpr(true),
    capabilities: [],
    executable: true,
    validity: const UnspecifiedValidity(),
    requiredEvidence: RequiredEvidence(
      sourceCategories: [
        VersionRef(
          universe: universe,
          record: category.identity.recordId,
          version: category.recordVersionId,
        ),
      ],
      reviewMethods: methods,
    ),
  );
  test(
    'policy summary keeps review optional and exact source selections distinct',
    () {
      final summary = EvidencePolicySummary(policy(), {
        category.identity.recordId: category,
      });
      expect(
        summary.review,
        'No interpretation review required by this policy.',
      );
      expect(summary.categories, ['private recollections (1)']);
      expect(summary.scope, contains('across the universe'));
      final changed = row(
        DomainPackRecord(
          key: 'private recollections',
          version: '2',
          dependencies: {},
          capabilities: [],
          records: [],
        ),
        id: category.identity.recordId,
      );
      final earlier = EvidencePolicySummary(policy(), {
        changed.identity.recordId: changed,
      });
      expect(earlier.categories, [
        'private recollections (earlier published selection retained)',
      ]);
      expect(earlier.categories.single, isNot(contains('(2)')));
      final reviewed = EvidencePolicySummary(
        policy(
          methods: EvidenceReviewMethod.values,
          applicability: WorldsApplicability([WorldId.generate()]),
        ),
        {},
      );
      expect(
        reviewed.review,
        contains('Human review or External writer review'),
      );
      expect(reviewed.scope, contains('1 selected world'));
      expect(reviewed.categories, [
        'Published source selection (name unavailable)',
      ]);
    },
  );
  test('findings show affected fact and policy names without replacing the verdict', () {
    final subject = row(
      EntityRecord(
        names: [],
        classificationResolution: ClassificationResolution.unclassified,
        worldAssociations: [],
        labels: {'en': 'Alice 記憶'},
        metadata: {},
      ),
    );
    final property = row(
      PropertyRecord(
        namespace: 'authored',
        key: 'birthplace',
        labels: {'en': 'Birthplace'},
        value: const SimpleValueShape(SimpleShapeKind.text),
        multiplicity: Multiplicity.single,
        persistence: PersistenceSemantics.unspecified,
        exclusive: false,
        symmetric: false,
        transitive: false,
      ),
    );
    final context = RecordRef(record: RecordId.generate());
    final proposition = row(
      PropositionRecord(
        predicate: RecordRef(record: property.identity.recordId),
        subject: RecordRef(record: subject.identity.recordId),
        quantification: Quantification.particular,
        context: context,
      ),
    );
    final assertion = row(
      AssertionRecord(
        attributeMode: AttributeMode.instance,
        proposition: RecordRef(record: proposition.identity.recordId),
        polarity: Polarity.support,
        scope: Scope(
          context: context,
          applicability: const UniverseApplicability(),
        ),
        validity: const UnspecifiedValidity(),
        persistence: PersistenceSemantics.unspecified,
        precision: Precision.exact,
        basis: const AuthorDecisionBasis('Authored'),
      ),
    );
    final rule = row(policy());
    final finding = Finding(
      ruleId: rule.identity.recordId,
      records: [RecordRef(record: assertion.identity.recordId)],
      fingerprint: const FindingFingerprint('source duty'),
      outcome: EvidenceOutcome.notEstablished,
      evidence: [rule.recordVersionId, assertion.recordVersionId],
      coverage: Coverage.complete,
      message: 'A qualifying source is missing.',
    );
    final original = finding.toWire().toText();
    final summary = FindingReviewSummary(
      finding: finding,
      universe: universe,
      records: {
        for (final r in [
          subject,
          property,
          proposition,
          assertion,
          rule,
          category,
        ])
          r.identity.recordId: r,
      },
    );
    expect(summary.title, 'Rule check · Memoir sources');
    expect(summary.claims, ['Alice 記憶 · Birthplace']);
    expect(summary.requirement!.review, contains('No interpretation review'));
    expect(finding.toWire().toText(), original);
    final ruleOnly = Finding.fromWire(
      CanonicalObject([
        ...finding.toWire().fields.where(
          (f) => f.key != 'records' && f.key != 'outcome',
        ),
        MapEntry('outcome', CanonicalString('supported')),
      ]),
    );
    expect(
      FindingReviewSummary(
        finding: ruleOnly,
        universe: universe,
        records: {rule.identity.recordId: rule},
      ).claims,
      ['No individual claim is identified by this finding.'],
    );
    final missing = FindingReviewSummary(
      finding: finding,
      universe: universe,
      records: {},
    );
    expect(missing.title, 'Rule check · Policy name unavailable');
    expect(missing.claims, ['Affected record (name unavailable)']);
    expect(missing.requirement, isNull);
    final foreign = FindingReviewSummary(
      finding: finding,
      universe: UniverseId.generate(),
      records: {
        rule.identity.recordId: rule,
        assertion.identity.recordId: assertion,
      },
    );
    expect(foreign.requirement, isNull);
    expect(foreign.title, 'Rule check · Policy name unavailable');
  });
}
