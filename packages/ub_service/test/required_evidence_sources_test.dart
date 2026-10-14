import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/required_evidence_checks.dart';

import 'candidate_validation_test.dart' as candidate;
import 'operation_compilation_test.dart' as definitions;
import 'rule_checks_test.dart' as f;
import 'source_verification_test.dart' as sources;

RuleRecord policy({
  Applicability applicability = const UniverseApplicability(),
  Validity validity = const UnspecifiedValidity(),
  List<String> predicates = const ['test:answer'],
  List<RecordId> subjectTypes = const [],
  List<EvidenceReviewMethod> reviewMethods = const [],
  int categoryVersion = 11,
}) => RuleRecord(
  namespace: 'real_world',
  key: 'required_sources',
  labels: {},
  kind: RuleKind.authorialRestriction,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability: applicability,
  targetPredicates: predicates,
  subjectTypes: subjectTypes,
  expression: const LiteralExpr(true),
  capabilities: [],
  executable: true,
  validity: validity,
  requiredEvidence: RequiredEvidence(
    sourceCategories: [
      VersionRef(
        universe: f.universe,
        record: f.id(11),
        version: f.version(categoryVersion),
      ),
    ],
    reviewMethods: reviewMethods,
  ),
);
DomainPackRecord category({bool includesSource = true}) => DomainPackRecord(
  key: 'private_memories',
  version: '1',
  dependencies: {},
  capabilities: [],
  records: includesSource ? [f.id(12)] : [],
);
AssertionRecord assertion({
  EvidenceBasis? basis,
  Applicability applicability = const UniverseApplicability(),
  Validity? validity,
}) => AssertionRecord(
  attributeMode: AttributeMode.instance,
  proposition: f.ref(3),
  polarity: Polarity.support,
  scope: Scope(context: f.ref(99), applicability: applicability),
  validity: validity ?? f.interval(12, 18),
  persistence: PersistenceSemantics.explicitInterval,
  precision: Precision.exact,
  basis: basis ?? SourceAnchorBasis(f.ref(13), false),
);
List<RecordVersion> fixture() => [
  ...candidate.fixture().where((r) => r.identity.recordId != f.id(4)),
  f.record(4, assertion()),
  f.record(10, policy()),
  f.record(11, category()),
  f.record(
    12,
    sources.source(
      origin: const OriginMetadata(
        externallyAssertedAuthor: 'Memoir author',
        originNote: 'Private recollection',
      ),
    ),
  ),
  f.record(
    13,
    sources.anchor(
      version: VersionRef(
        universe: f.universe,
        record: f.id(12),
        version: f.version(12),
      ),
    ),
  ),
];
void replace(List<RecordVersion> rows, int n, RecordPayload payload) {
  rows.removeWhere((r) => r.identity.recordId == f.id(n));
  rows.add(f.record(n, payload));
}

List<protocol.Finding> assess(
  List<RecordVersion> rows, {
  List<RecordVersion>? base,
  List<int> changed = const [4],
}) => assessRequiredEvidenceSources(
  records: rows,
  base: base ?? rows,
  changed: changed.map(f.id).toSet(),
);
void main() {
  test('private attributed recollection qualifies without a public URL or writer verification flag', () {
    final finding = assess(fixture()).single;
    expect(finding.outcome, protocol.EvidenceOutcome.supported);
    expect(finding.coverage, protocol.Coverage.complete);
    expect(finding.records, [f.ref(4)]);
    expect(
      finding.evidence,
      containsAll([f.version(10), f.version(11), f.version(12), f.version(13)]),
    );
  });
  test(
    'ordinary author choice cannot replace a required qualifying source',
    () {
      final rows = fixture();
      replace(rows, 4, assertion(basis: const AuthorDecisionBasis('Approved')));
      expect(
        assess(rows).single.outcome,
        protocol.EvidenceOutcome.notEstablished,
      );
    },
  );
  test('categories must contain the cited source at the exact pinned active version', () {
    final rows = fixture();
    replace(rows, 11, category(includesSource: false));
    expect(
      assess(rows).single.outcome,
      protocol.EvidenceOutcome.notEstablished,
    );
    replace(rows, 11, category());
    replace(rows, 10, policy(categoryVersion: 55));
    expect(
      assess(rows).single.outcome,
      protocol.EvidenceOutcome.notEstablished,
    );
    expect(assess(rows).single.message, contains('exact current'));
  });
  test('an anchor cannot silently follow a source revision', () {
    final rows = fixture();
    replace(
      rows,
      13,
      sources.anchor(
        version: VersionRef(
          universe: f.universe,
          record: f.id(12),
          version: f.version(88),
        ),
      ),
    );
    expect(
      assess(rows).single.outcome,
      protocol.EvidenceOutcome.notEstablished,
    );
  });
  test('unrelated changes leave unchanged claims alone', () {
    expect(assess(fixture(), changed: [77]), isEmpty);
    expect(assess(fixture(), changed: []), isEmpty);
  });
  test('source, anchor, proposition, subject, context, category and policy changes revisit dependent claims', () {
    for (final changed in [1, 2, 3, 4, 10, 11, 12, 13, 99]) {
      expect(
        assess(fixture(), changed: [changed]),
        hasLength(1),
        reason: '$changed',
      );
    }
  });
  test('deleted source dependencies still revisit their existing claims', () {
    final base = fixture(), rows = [...base];
    rows.removeWhere((r) => r.identity.recordId == f.id(12));
    expect(
      assess(rows, base: base, changed: [12]).single.outcome,
      protocol.EvidenceOutcome.notEstablished,
    );
  });
  test('disjoint predicate and time policies do not impose a source duty', () {
    final rows = fixture();
    replace(rows, 10, policy(predicates: ['other:predicate']));
    expect(assess(rows), isEmpty);
    replace(rows, 10, policy(validity: f.interval(20, 25)));
    expect(assess(rows), isEmpty);
    replace(rows, 10, policy(validity: f.interval(10, 15)));
    expect(assess(rows), hasLength(1));
  });
  test('world overlap determines which claims need sources', () {
    final a = WorldId.parse('wld_${f.suffix(20)}');
    final b = WorldId.parse('wld_${f.suffix(21)}');
    final rows = fixture();
    replace(rows, 10, policy(applicability: WorldsApplicability([a])));
    replace(rows, 4, assertion(applicability: WorldsApplicability([b])));
    expect(assess(rows), isEmpty);
    replace(rows, 4, assertion(applicability: WorldsApplicability([a, b])));
    expect(assess(rows).single.outcome, protocol.EvidenceOutcome.supported);
  });
  test('unresolved relevant scope and time do not count as established eligibility', () {
    final rows = fixture();
    replace(
      rows,
      4,
      assertion(applicability: const UnspecifiedApplicability()),
    );
    expect(assess(rows).single.coverage, protocol.Coverage.unsupported);
    replace(rows, 4, assertion(validity: const UnspecifiedValidity()));
    replace(rows, 10, policy(validity: f.interval(10, 20)));
    expect(assess(rows).single.coverage, protocol.Coverage.unsupported);
  });
  test('character beliefs are not promoted to objective claims', () {
    final rows = fixture();
    replace(
      rows,
      99,
      RepresentedContextRecord(
        universe: f.universe,
        kind: CharacterContext(f.ref(1)),
        labels: {},
      ),
    );
    expect(assess(rows), isEmpty);
  });
  test('subject restrictions follow inheritance and preserve unresolved classification', () {
    final rows = fixture();
    rows.addAll([
      f.record(30, definitions.type(30)),
      f.record(31, definitions.type(31, parent: 30)),
      f.record(32, definitions.type(32)),
    ]);
    replace(rows, 10, policy(subjectTypes: [f.id(30)]));
    replace(rows, 1, definitions.entity(classification: f.id(31)));
    expect(assess(rows).single.outcome, protocol.EvidenceOutcome.supported);
    replace(rows, 1, definitions.entity(classification: f.id(32)));
    expect(assess(rows), isEmpty);
    replace(rows, 1, definitions.entity());
    expect(assess(rows).single.coverage, protocol.Coverage.unsupported);
  });
  test(
    'source eligibility never reports interpretation review as discharged',
    () {
      final rows = fixture();
      replace(rows, 10, policy(reviewMethods: EvidenceReviewMethod.values));
      expect(
        assess(rows).single.message,
        contains('review is evaluated separately'),
      );
    },
  );
}
