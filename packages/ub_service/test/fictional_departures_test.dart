import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as p;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/fictional_departures.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

import 'candidate_validation_test.dart' as candidate;
import 'required_evidence_sources_test.dart' as sources;
import 'rule_checks_test.dart' as f;

ExceptionRecord departure({
  int policy = 10,
  int decision = 20,
  bool marked = true,
  Scope? scope,
  Validity? validity,
  RecordVersionId? pin,
}) => ExceptionRecord(
  fictionalDeparture: marked,
  rule: f.ref(policy),
  ruleVersion: pin ?? f.version(policy),
  authorizingDecision: f.ref(decision),
  scope: scope ?? f.scope,
  validity: validity ?? f.interval(12, 18),
  rationale: 'Invented for this story',
);
List<RecordVersion> fixture() {
  final rows = sources.fixture();
  sources.replace(
    rows,
    4,
    sources.assertion(basis: const AuthorDecisionBasis('Invented claim')),
  );
  rows.addAll([
    f.record(
      20,
      IssueDecisionRecord(
        fingerprints: [],
        mode: IssueDecisionMode.accept,
        scope: f.id(10).value,
        rationale: 'Explicit scoped fiction',
        principal: PrincipalId.parse('prn_${f.suffix(1)}'),
      ),
    ),
    f.record(21, departure()),
  ]);
  return rows;
}

List<Assignment> changes(
  List<RecordVersion> rows,
  List<RecordVersion> base,
  List<int> ids,
) => [
  for (final n in ids)
    Assignment(
      recordId: f.id(n),
      expected: base
          .where((r) => r.identity.recordId == f.id(n))
          .firstOrNull
          ?.recordVersionId,
      next: rows
          .where((r) => r.identity.recordId == f.id(n))
          .map(
            (r) => StoredVersion(
              versionId: r.recordVersionId,
              identity: r.identity,
              payload: r.payload.toWire(),
              digest: r.payloadDigest,
            ),
          )
          .firstOrNull,
    ),
];
p.Finding sourceFinding(List<RecordVersion> rows) =>
    sources.assess(rows).single;
RecordVersion? matchDeparture(p.Finding finding, List<RecordVersion> rows) =>
    fictionalDepartureForClaim(
      finding,
      rows,
      rules.RecordIndex(rows),
      rows.where((r) => r.payload is ExceptionRecord),
    );
void main() {
  test('a departure covers only the policy intersection and never excuses unsupported checks', () {
    final rows = fixture();
    final a = WorldId.parse('wld_${f.suffix(30)}'),
        b = WorldId.parse('wld_${f.suffix(31)}');
    sources.replace(
      rows,
      10,
      sources.policy(
        applicability: WorldsApplicability([a]),
        validity: f.interval(14, 16),
      ),
    );
    sources.replace(
      rows,
      4,
      sources.assertion(
        basis: const AuthorDecisionBasis('Invented'),
        applicability: WorldsApplicability([a, b]),
      ),
    );
    sources.replace(
      rows,
      21,
      departure(
        scope: Scope(
          context: f.ref(99),
          applicability: WorldsApplicability([a]),
        ),
        validity: f.interval(14, 16),
      ),
    );
    final finding = sourceFinding(rows);
    expect(matchDeparture(finding, rows)?.identity.recordId, f.id(21));
    final unsupported = p.Finding.fromWire(
      CanonicalObject([
        ...finding.toWire().fields.where((f) => f.key != 'coverage'),
        MapEntry('coverage', CanonicalString('unsupported')),
      ]),
    );
    expect(matchDeparture(unsupported, rows), isNull);
  });
  test('physical rule departures preserve the refuted outcome and exact declaration', () {
    final rows = f.fixture();
    f.replace(
      rows,
      f.record(
        4,
        f.rule(expr: const LiteralExpr(false), validity: f.interval(12, 18)),
      ),
    );
    rows.addAll([
      f.decision(),
      f.record(
        6,
        ExceptionRecord.fromWire(
          CanonicalObject([
            ...f.exception().toWire().fields,
            const MapEntry('fictionalDeparture', CanonicalBool(true)),
          ]),
        ),
      ),
    ]);
    final result = candidate.check(rows);
    expect(result.admissible, isTrue);
    final finding = result.validation.findings.single;
    expect(finding.outcome, p.EvidenceOutcome.refuted);
    expect(finding.message, startsWith('Fictional departure:'));
    expect(finding.evidence, containsAll([f.version(5), f.version(6)]));
  });
  test('explicit departures permit scoped fiction without claiming factual support', () {
    final rows = fixture();
    final result = candidate.check(rows, changes: changes(rows, rows, [4]));
    expect(result.admissible, isTrue);
    final finding = result.validation.findings.singleWhere(
      (f) => f.records.isNotEmpty,
    );
    expect(finding.outcome, p.EvidenceOutcome.notEstablished);
    expect(finding.coverage, p.Coverage.complete);
    expect(
      finding.message,
      startsWith('Fictional departure: Invented for this story'),
    );
    expect(finding.evidence, containsAll([f.version(20), f.version(21)]));
    sources.replace(rows, 21, departure(marked: false));
    final ordinary = candidate.check(rows, changes: changes(rows, rows, [4]));
    expect(ordinary.admissible, isFalse);
    expect(
      ordinary.validation.findings
          .singleWhere((f) => f.records.isNotEmpty)
          .message,
      isNot(startsWith('Fictional departure:')),
    );
  });
  test(
    'departures cannot cross world context realm time or exact policy pins',
    () {
      final a = WorldId.parse('wld_${f.suffix(30)}'),
          b = WorldId.parse('wld_${f.suffix(31)}');
      final rows = fixture();
      for (final invalid in [
        departure(pin: f.version(200)),
        departure(
          scope: Scope(
            context: f.ref(98),
            applicability: const UniverseApplicability(),
          ),
        ),
        departure(
          scope: Scope(
            context: f.ref(99),
            realm: f.ref(98),
            applicability: const UniverseApplicability(),
          ),
        ),
        departure(validity: f.interval(12, 15)),
        departure(
          scope: Scope(
            context: f.ref(99),
            applicability: WorldsApplicability([a]),
          ),
        ),
      ]) {
        sources.replace(rows, 21, invalid);
        expect(matchDeparture(sourceFinding(rows), rows), isNull);
      }
      sources.replace(
        rows,
        4,
        sources.assertion(
          basis: const AuthorDecisionBasis('Invented'),
          applicability: WorldsApplicability([a]),
        ),
      );
      expect(
        matchDeparture(sourceFinding(rows), rows)?.identity.recordId,
        f.id(21),
      );
      sources.replace(
        rows,
        4,
        sources.assertion(
          basis: const AuthorDecisionBasis('Invented'),
          applicability: WorldsApplicability([b]),
        ),
      );
      expect(matchDeparture(sourceFinding(rows), rows), isNull);
      sources.replace(
        rows,
        4,
        sources.assertion(
          basis: const AuthorDecisionBasis('Invented'),
          applicability: WorldsApplicability([a, b]),
        ),
      );
      expect(matchDeparture(sourceFinding(rows), rows), isNull);
      rows.removeWhere((r) => r.identity.recordId == f.id(20));
      expect(matchDeparture(sourceFinding(rows), rows), isNull);
    },
  );
  test(
    'changing or removing a departure rechecks its existing affected claims',
    () {
      final rows = fixture();
      expect(sources.assess(rows, changed: [21]), hasLength(1));
      expect(sources.assess(rows, changed: [20]), hasLength(1));
      final removed = [...rows]
        ..removeWhere((r) => r.identity.recordId == f.id(21));
      final result = candidate.check(
        removed,
        base: rows,
        changes: changes(removed, rows, [21]),
      );
      expect(result.admissible, isFalse);
      expect(
        result.validation.findings
            .singleWhere((f) => f.records.isNotEmpty)
            .outcome,
        p.EvidenceOutcome.notEstablished,
      );
    },
  );
  test(
    'required review remains unresolved evidence when fiction is declared',
    () {
      final rows = fixture();
      sources.replace(
        rows,
        10,
        sources.policy(
          reviewMethods: [EvidenceReviewMethod.externalModelReview],
        ),
      );
      sources.replace(rows, 4, sources.assertion());
      final result = candidate.check(rows, changes: changes(rows, rows, [4]));
      expect(result.admissible, isTrue);
      final finding = result.validation.findings.singleWhere(
        (f) => f.records.isNotEmpty,
      );
      expect(finding.outcome, p.EvidenceOutcome.notEstablished);
      expect(
        finding.message,
        contains('requires a selected, current assessment'),
      );
      expect(finding.message, startsWith('Fictional departure:'));
    },
  );
}
