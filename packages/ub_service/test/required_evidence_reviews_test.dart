import 'package:ub_service/src/universe_evidence_policy.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as p;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/required_evidence_checks.dart';
import 'package:ub_service/src/required_evidence_reviews.dart';
import 'package:ub_service/candidate_validation.dart';
import 'package:ub_service/proposal_authorization.dart';
import 'package:ub_store/ub_store.dart';

import 'assessment_validation_test.dart' as assessments;
import 'required_evidence_sources_test.dart' as sources;
import 'rule_checks_test.dart' as f;

p.AssessmentVersionRef ref(int n, {int? version}) => p.AssessmentVersionRef(
  universe: f.universe,
  record: f.id(n),
  version: f.version(version ?? n),
);
p.ClaimMapping mapping({
  String key = 'mapping',
  int assertionVersion = 4,
  int subject = 1,
  int context = 99,
  int? world,
  int? realm,
  int start = 12,
  int end = 18,
  bool value = true,
  p.MappingJudgment judgment = p.MappingJudgment.supported,
  p.Modality modality = p.Modality.asserted,
  p.CandidateLinkKind kind = p.CandidateLinkKind.unchangedRecord,
}) => p.ClaimMapping(
  mappingId: key,
  itemIds: [key],
  referents: [],
  context: ref(context),
  world: world == null ? null : ref(world),
  realm: realm == null ? null : ref(realm),
  storyTime: IntervalTime(f.calendar, ExactBound('$start'), ExactBound('$end')),
  narrationPosition: const p.NotApplicablePosition(),
  readerPosition: const p.NotApplicablePosition(),
  occurrence: p.Occurrence.occurred,
  modality: modality,
  semantic: p.ClaimSemanticMapping(
    predicate: ref(2),
    subject: ref(subject),
    value: BooleanValue(value),
    roles: [],
    polarity: Polarity.support,
  ),
  candidateLinks: [
    p.CandidateLink(
      kind: kind,
      version: ref(4, version: assertionVersion),
    ),
  ],
  judgment: judgment,
  rationale: 'Reviewed the cited claim',
);
p.AssessmentReview review({
  List<p.ClaimMapping>? mappings,
  p.Method method = p.Method.humanReview,
  p.AssessmentState? state,
}) {
  final original = assessments.body();
  final claims = mappings ?? [mapping()];
  final pending = claims
      .where((m) => m.judgment == p.MappingJudgment.unresolved)
      .toList();
  final source = original.sources.single;
  final dependencies = <String, p.AssessmentVersionRef>{};
  for (final m in claims) {
    final semantic = m.semantic as p.ClaimSemanticMapping;
    for (final r in [
      m.context,
      m.world,
      m.realm,
      semantic.subject,
      semantic.predicate,
      ...m.candidateLinks.map((l) => l.version),
    ]) {
      if (r != null) dependencies[r.toWire().toText()] = r;
    }
  }
  final body = p.SourceAssessmentV1(
    kind: original.kind,
    proposal: original.proposal,
    baseFrame: original.baseFrame,
    assessor: p.Assessor(
      principal: original.assessor.principal,
      method: method,
      tool: method == p.Method.humanReview
          ? null
          : p.ToolIdentity(
              name: 'External writer',
              version: '1',
              modelRevision: '1',
              procedureDigest: p.Sha256Hex('a' * 64),
            ),
      assessedAt: original.assessor.assessedAt,
    ),
    sources: [
      p.SourceBinding(
        key: source.key,
        sourceVersion: ref(12),
        blobDigest: source.blobDigest,
        byteSize: source.byteSize,
        representation: source.representation,
        ranges: source.ranges,
        workEdition: null,
        passageId: null,
      ),
    ],
    dependencies: dependencies.values,
    declaredInventory: [
      for (final m in claims)
        p.MaterialItem(
          itemId: m.mappingId,
          sourceKey: source.key,
          range: source.ranges.single,
          materialKind: p.MaterialKind.fact,
          statement: 'A sourced claim',
          mappingIds: [m.mappingId],
          unresolvedIds: m.judgment == p.MappingJudgment.unresolved
              ? ['pending-${m.mappingId}']
              : [],
        ),
    ],
    inventoryDeclaration: p.InventoryDeclaration(
      kind: p.InventoryKind.materialInventoryDeclared,
      rationale: 'Claim review',
      exclusions: [],
    ),
    claimMappings: claims,
    unresolved: [
      for (final m in pending)
        p.UnresolvedDisposition(
          unresolvedId: 'pending-${m.mappingId}',
          itemIds: [m.mappingId],
          reason: p.UnresolvedReason.interpretationDisagreement,
          detail: 'Needs resolution',
        ),
    ],
    conclusion: pending.isNotEmpty
        ? p.DeclaredConclusion.unresolved
        : claims.any((m) => m.judgment == p.MappingJudgment.contradicted)
        ? p.DeclaredConclusion.inconsistent
        : p.DeclaredConclusion.consistentWithDeclaredInventory,
  );
  body.validate();
  final envelope = p.AssessmentEnvelope(
    assessmentId: p.AssessmentId('asm_${f.suffix(1)}'),
    digest: body.digest(),
    body: body,
  );
  final selected = p.AssessmentRef(
    assessmentId: envelope.assessmentId,
    digest: envelope.digest,
  );
  return p.AssessmentReview(
    selection: p.AssessmentSelection(
      proposal: body.proposal,
      generation: BigInt.one,
      selected: selected,
    ),
    state:
        state ??
        p.BoundAssessment(
          assessmentReference: selected,
          selectionGeneration: BigInt.one,
          byteVerification: p.ByteVerification.verified,
          declaredConclusion: body.conclusion,
          inventoryCount: BigInt.from(body.declaredInventory.length),
          mappingCount: BigInt.from(claims.length),
          unresolvedCount: BigInt.from(pending.length),
          inventoryDigest: body.inventoryDigest(),
        ),
    envelope: envelope,
  );
}

List<RecordVersion> fixture({
  List<EvidenceReviewMethod> methods = const [EvidenceReviewMethod.humanReview],
}) {
  final rows = sources.fixture();
  sources.replace(rows, 10, sources.policy(reviewMethods: methods));
  return rows;
}

p.Finding assess(List<RecordVersion> rows, p.AssessmentReview? selected) =>
    assessRequiredEvidenceReviews(
      sourceFindings: assessRequiredEvidenceSources(
        records: rows,
        base: rows,
        changed: {f.id(4)},
      ),
      records: rows,
      review: selected,
    ).single;
void main() {
  test(
    'the shared candidate evaluator enforces scoped source and review duties',
    () {
      final rows = [
        ...fixture(),
        ...initialUniversePolicyRecords(f.universe, false),
      ];
      final assertion = rows.singleWhere((r) => r.identity.recordId == f.id(4));
      CandidateValidationResult check(p.AssessmentReview? selected) =>
          evaluateCandidate(
            candidate: rows,
            base: rows,
            changes: [
              Assignment(
                recordId: f.id(4),
                next: StoredVersion(
                  versionId: assertion.recordVersionId,
                  identity: assertion.identity,
                  payload: assertion.payload.toWire(),
                  digest: assertion.payloadDigest,
                ),
              ),
            ],
            frame: f.frame(),
            digest: 'exact-candidate',
            footprint: WriteFootprint(shared: true),
            authorOrigin: true,
            approvalAuthor: ProfileId.parse('prf_${f.suffix(1)}'),
            selectedAssessment: selected,
          );
      expect(check(null).admissible, isFalse);
      expect(check(review()).admissible, isTrue);
      sources.replace(rows, 10, sources.policy());
      expect(check(null).admissible, isTrue);
      sources.replace(
        rows,
        4,
        sources.assertion(basis: const AuthorDecisionBasis('Approved')),
      );
      expect(check(review()).admissible, isFalse);
    },
  );
  test('no review duty needs no assessment; a scoped duty requires an accepted method', () {
    expect(
      assess(fixture(methods: []), null).outcome,
      p.EvidenceOutcome.supported,
    );
    expect(assess(fixture(), null).outcome, p.EvidenceOutcome.notEstablished);
    expect(assess(fixture(), review()).outcome, p.EvidenceOutcome.supported);
    expect(
      assess(fixture(), review(method: p.Method.externalModelReview)).outcome,
      p.EvidenceOutcome.notEstablished,
    );
    expect(
      assess(
        fixture(methods: [EvidenceReviewMethod.externalModelReview]),
        review(method: p.Method.externalModelReview),
      ).outcome,
      p.EvidenceOutcome.supported,
    );
  });
  test(
    'review links must identify the exact objective candidate and meaning',
    () {
      for (final m in [
        mapping(assertionVersion: 88),
        mapping(subject: 20),
        mapping(context: 98),
        mapping(value: false),
        mapping(kind: p.CandidateLinkKind.historicalEvidence),
        mapping(modality: p.Modality.attributed),
        mapping(modality: p.Modality.counterfactual),
        mapping(realm: 20),
      ]) {
        expect(
          assess(fixture(), review(mappings: [m])).outcome,
          p.EvidenceOutcome.notEstablished,
        );
      }
    },
  );
  test('stale or unavailable selected material never discharges review', () {
    expect(
      assess(
        fixture(),
        review(
          state: const p.UnavailableAssessment(
            reason: p.UnavailableReason.missingRetainedMaterial,
          ),
        ),
      ).outcome,
      p.EvidenceOutcome.notEstablished,
    );
  });
  test('review coverage can be composed over the required time and leaves gaps unresolved', () {
    expect(
      assess(
        fixture(),
        review(
          mappings: [
            mapping(end: 15),
            mapping(key: 'later', start: 15),
          ],
        ),
      ).outcome,
      p.EvidenceOutcome.supported,
    );
    expect(
      assess(
        fixture(),
        review(
          mappings: [
            mapping(end: 14),
            mapping(key: 'later', start: 15),
          ],
        ),
      ).outcome,
      p.EvidenceOutcome.notEstablished,
    );
    final rows = fixture();
    sources.replace(
      rows,
      10,
      sources.policy(
        reviewMethods: [EvidenceReviewMethod.humanReview],
        validity: f.interval(14, 16),
      ),
    );
    expect(
      assess(rows, review(mappings: [mapping(start: 14, end: 16)])).outcome,
      p.EvidenceOutcome.supported,
    );
  });
  test('review must cover every policy world; a world-specific mapping cannot satisfy a universe-wide duty', () {
    final rows = fixture();
    rows.addAll([
      f.record(20, WorldRecord(selector: 'A')),
      f.record(21, WorldRecord(selector: 'B')),
    ]);
    sources.replace(
      rows,
      4,
      sources.assertion(
        applicability: WorldsApplicability([
          WorldId.parse('wld_${f.suffix(20)}'),
          WorldId.parse('wld_${f.suffix(21)}'),
        ]),
      ),
    );
    expect(
      assess(rows, review(mappings: [mapping(world: 20)])).outcome,
      p.EvidenceOutcome.notEstablished,
    );
    expect(
      assess(
        rows,
        review(
          mappings: [
            mapping(world: 20),
            mapping(key: 'world-b', world: 21),
          ],
        ),
      ).outcome,
      p.EvidenceOutcome.supported,
    );
    expect(
      assess(fixture(), review(mappings: [mapping(world: 20)])).outcome,
      p.EvidenceOutcome.notEstablished,
    );
  });
  test('opposing and unresolved interpretation blocks only overlapping required scope', () {
    expect(
      assess(
        fixture(),
        review(
          mappings: [
            mapping(),
            mapping(
              key: 'ambiguous-modality',
              judgment: p.MappingJudgment.unresolved,
              modality: p.Modality.unknown,
            ),
          ],
        ),
      ).outcome,
      p.EvidenceOutcome.notEstablished,
    );
    for (final judgment in [
      p.MappingJudgment.contradicted,
      p.MappingJudgment.unresolved,
    ]) {
      expect(
        assess(
          fixture(),
          review(
            mappings: [
              mapping(),
              mapping(key: 'pending', judgment: judgment),
            ],
          ),
        ).outcome,
        p.EvidenceOutcome.notEstablished,
      );
      expect(
        assess(
          fixture(),
          review(
            mappings: [
              mapping(),
              mapping(key: 'elsewhere', start: 20, end: 25, judgment: judgment),
            ],
          ),
        ).outcome,
        p.EvidenceOutcome.supported,
      );
    }
  });
}
