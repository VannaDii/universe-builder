import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_service/boundary_checks.dart';
import 'package:ub_service/rule_checks.dart';

import 'operation_compilation_test.dart' as entities;
import 'rule_checks_test.dart' as f;

BoundaryRecord boundary({
  BoundaryArea? area,
  BoundaryMode mode = BoundaryMode.intentionallyUnresolved,
  Scope? scope,
  Validity? validity,
  List<Expr> constraints = const [],
}) => BoundaryRecord(
  key: 'test:question',
  area: area ?? RecordBoundaryArea(f.ref(1)),
  mode: mode,
  constraints: constraints,
  scope: scope ?? f.scope,
  validity: validity ?? f.interval(10, 20),
);
RecordVersion assertion({Scope? scope, Validity? validity}) => f.record(
  4,
  AssertionRecord(
    attributeMode: AttributeMode.instance,
    proposition: f.ref(3),
    polarity: Polarity.support,
    scope: scope ?? f.scope,
    validity: validity ?? f.interval(12, 18),
    persistence: PersistenceSemantics.explicitInterval,
    precision: Precision.exact,
    basis: const AuthorDecisionBasis('Explicit fact'),
  ),
);
List<RecordVersion> fixture() => [
  f.record(1, entities.entity()),
  f.record(
    2,
    PropertyRecord(
      namespace: 'test',
      key: 'answer',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  f.record(
    3,
    PropositionRecord(
      subject: f.ref(1),
      predicate: f.ref(2),
      value: const BooleanValue(true),
      context: f.ref(99),
      quantification: Quantification.particular,
    ),
  ),
  assertion(),
  f.record(5, boundary()),
  f.record(
    6,
    IssueDecisionRecord(
      fingerprints: [],
      mode: IssueDecisionMode.accept,
      scope: f.id(5).value,
      rationale: 'Reviewed exact period',
      principal: PrincipalId.parse('prn_${f.suffix(1)}'),
    ),
  ),
];
RecordVersion exception(
  List<RecordVersion> rows,
  int end, {
  bool stale = false,
}) => f.record(
  7,
  ExceptionRecord(
    rule: f.ref(5),
    ruleVersion: stale ? f.version(99) : rows[4].recordVersionId,
    scope: f.scope,
    validity: f.interval(12, end),
    authorizingDecision: f.ref(6),
    rationale: 'Only the stated period',
  ),
);
CheckedRule check(
  List<RecordVersion> rows, {
  List<RecordVersion>? changes,
  List<RecordVersion> historical = const [],
  bool author = true,
}) => evaluateCandidateBoundary(
  target: rows[4],
  changes: changes ?? [rows[3]],
  records: rows,
  historical: historical,
  frame: f.frame(),
  author: author,
);
void main() {
  test(
    'transitive subject references require a waiver for every exact cell',
    () {
      final rows = fixture();
      expect(check(rows).complete, isTrue);
      expect(check(rows).accepted, isFalse);
      rows.add(exception(rows, 17));
      expect(check(rows).accepted, isFalse);
      rows[6] = exception(rows, 18);
      final waived = check(rows);
      expect(waived.complete, isTrue);
      expect(waived.accepted, isTrue);
      expect(waived.evidence.outcome, EvidenceOutcome.refuted);
      expect(waived.evidence.allSources, [rows[4].recordVersionId]);
      rows[6] = exception(rows, 18, stale: true);
      expect(check(rows).accepted, isFalse);
      rows[3] = assertion(validity: f.interval(20, 25));
      expect(check(rows).accepted, isTrue);
      rows[3] = assertion(validity: f.interval(15, 25));
      expect(check(rows).accepted, isFalse);
    },
  );
  test('deleted evidence and independent clocks cannot escape protection', () {
    final rows = fixture(), next = fixture();
    next[3] = f.record(4, entities.entity());
    expect(check(next, changes: [rows[3]], historical: rows).accepted, isFalse);
    final changed = assertion(
      validity: CalendarIntervalValidity(
        CalendarId.parse('cal_${f.suffix(99)}'),
        const ExactBound('12'),
        const ExactBound('18'),
      ),
    );
    final result = check(rows, changes: [changed]);
    expect(result.complete, isFalse);
    expect(result.accepted, isFalse);
  });
  test('proposition mentions use candidate assertion periods', () {
    final rows = fixture();
    rows[3] = assertion(validity: f.interval(20, 25));
    expect(check(rows, changes: [rows[2]]).accepted, isTrue);
    rows[3] = assertion();
    expect(check(rows, changes: [rows[2]]).accepted, isFalse);
    final withoutAssertion = [...rows]..removeAt(3);
    final result = evaluateCandidateBoundary(
      target: rows[4],
      changes: [rows[2]],
      records: withoutAssertion,
      historical: [],
      frame: f.frame(),
      author: true,
    );
    expect(result.complete, isTrue);
    expect(result.accepted, isFalse);
  });
  test('predicate and exact classification boundaries follow dependencies', () {
    final rows = fixture();
    rows[4] = f.record(
      5,
      boundary(area: PredicateBoundaryArea('test:answer', f.ref(1))),
    );
    expect(check(rows).accepted, isFalse);
    rows[4] = f.record(
      5,
      boundary(area: PredicateBoundaryArea('test:answer', f.ref(88))),
    );
    expect(check(rows).accepted, isTrue);
    rows[4] = f.record(5, boundary(area: CategoryBoundaryArea(f.id(80))));
    expect(check(rows).accepted, isTrue);
    rows[0] = f.record(1, entities.entity(classification: f.id(80)));
    expect(check(rows).accepted, isFalse);
  });
  test('context, realm and world cells retain authored distinctions', () {
    final rows = fixture();
    Scope cell({int context = 99, RecordRef? realm, Applicability? worlds}) =>
        Scope(
          context: f.ref(context),
          realm: realm,
          applicability: worlds ?? const UniverseApplicability(),
        );
    rows[3] = assertion(scope: cell(context: 98));
    expect(check(rows).accepted, isTrue);
    rows[4] = f.record(5, boundary(scope: cell(realm: f.ref(50))));
    rows[3] = assertion();
    expect(check(rows).complete, isFalse);
    rows[3] = assertion(scope: cell(realm: f.ref(51)));
    expect(check(rows).accepted, isTrue);
    rows[3] = assertion(scope: cell(realm: f.ref(50)));
    expect(check(rows).accepted, isFalse);
    final a = WorldId.parse('wld_${f.suffix(1)}'),
        b = WorldId.parse('wld_${f.suffix(2)}');
    rows[4] = f.record(
      5,
      boundary(scope: cell(worlds: WorldsApplicability([a]))),
    );
    rows[3] = assertion(scope: cell(worlds: WorldsApplicability([b])));
    expect(check(rows).accepted, isTrue);
    rows[3] = assertion(scope: cell(worlds: WorldsApplicability([a, b])));
    expect(check(rows).accepted, isFalse);
  });
  test('author reservation and explicit constraints preserve evidence', () {
    final rows = fixture();
    rows[4] = f.record(5, boundary(mode: BoundaryMode.authorReserved));
    expect(check(rows).accepted, isTrue);
    expect(check(rows, author: false).accepted, isFalse);
    rows[4] = f.record(5, boundary(mode: BoundaryMode.proposalRequired));
    expect(check(rows, author: false).accepted, isTrue);
    rows[4] = f.record(
      5,
      boundary(
        mode: BoundaryMode.openWithConstraints,
        constraints: [const LiteralExpr(true)],
      ),
    );
    expect(check(rows).accepted, isTrue);
    rows[4] = f.record(
      5,
      boundary(
        mode: BoundaryMode.openWithConstraints,
        constraints: [const LiteralExpr(false)],
      ),
    );
    expect(check(rows).accepted, isFalse);
  });
  test('event effects supply their own scope and exact validity', () {
    final rows = fixture();
    RecordVersion event(Validity period, Scope scope) => f.record(
      8,
      EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        time: ExactTime(f.calendar, '11'),
        labels: {},
        participants: [],
        effects: [
          EntityEffect(
            slot: 'answer',
            proposition: f.ref(3),
            polarity: Polarity.support,
            validity: period,
            scope: scope,
            order: BigInt.zero,
          ),
        ],
      ),
    );
    expect(
      check(rows, changes: [event(f.interval(20, 25), f.scope)]).accepted,
      isTrue,
    );
    expect(
      check(rows, changes: [event(f.interval(12, 18), f.scope)]).accepted,
      isFalse,
    );
    final unknown = Scope(
      context: f.ref(99),
      applicability: const ConditionalApplicability(),
    );
    final r = check(rows, changes: [event(f.interval(12, 18), unknown)]);
    expect(r.complete, isFalse);
    expect(r.accepted, isFalse);
  });
  test('constraints use candidate evidence in each affected time cell', () {
    final rows = fixture();
    rows[4] = f.record(
      5,
      boundary(
        mode: BoundaryMode.openWithConstraints,
        constraints: [
          ClaimExpr(
            subject: RecordOperand(f.ref(1)),
            predicate: 'test:answer',
            value: const ValueOperand(BooleanValue(true)),
            polarity: Polarity.support,
          ),
        ],
      ),
    );
    expect(check(rows).accepted, isTrue);
    // Entity edits cover cells where no assertion establishes the constraint.
    final r = check(rows, changes: [rows[0]]);
    expect(r.accepted, isFalse);
    expect(r.evidence.outcome, EvidenceOutcome.notEstablished);
    final realmScope = Scope(
      context: f.ref(99),
      realm: f.ref(50),
      applicability: const UniverseApplicability(),
    );
    rows[4] = f.record(
      5,
      boundary(
        scope: realmScope,
        mode: BoundaryMode.openWithConstraints,
        constraints: [const LiteralExpr(true)],
      ),
    );
    rows[3] = assertion(scope: realmScope);
    expect(check(rows).complete, isFalse);
    expect(check(rows).accepted, isFalse);
  });
  test('policy records do not themselves count as protected content edits', () {
    final rows = fixture();
    rows.add(exception(rows, 18));
    expect(check(rows, changes: [rows[4], rows[5], rows[6]]).accepted, isTrue);
  });
  test(
    'work exhaustion is incomplete even when earlier changes do not touch',
    () {
      final rows = fixture();
      final unrelated = f.record(77, entities.entity());
      final result = check(
        rows,
        changes: List<RecordVersion>.filled(100001, unrelated),
      );
      expect(result.complete, isFalse);
      expect(result.accepted, isFalse);
      expect(result.evidence.outcome, EvidenceOutcome.supported);
    },
  );
}
