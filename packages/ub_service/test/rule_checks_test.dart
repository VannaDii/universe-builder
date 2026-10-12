import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_service/rule_checks.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(10)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
RecordVersion record(int n, RecordPayload payload) => RecordVersion.build(
  recordVersionId: version(n),
  identity: RecordIdentity(
    universeId: universe,
    recordId: id(n),
    recordKind: payload.recordKind,
  ),
  payload: payload,
);
Validity interval(int a, int b) =>
    CalendarIntervalValidity(calendar, ExactBound('$a'), ExactBound('$b'));
final scope = Scope(
  context: ref(99),
  applicability: const UniverseApplicability(),
);
Frame frame({FrameTime? time}) => Frame(
  universe: universe,
  continuity: ContinuityId.parse('cont_${suffix(1)}'),
  revision: RevisionId.parse('rev_${suffix(1)}'),
  context: ref(99),
  time: time ?? const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
  readerScene: id(60),
  personalSequence: 'later narration',
);
final claim = ClaimExpr(
  subject: RecordOperand(ref(80)),
  predicate: 'test:open',
  value: const ValueOperand(BooleanValue(true)),
  polarity: Polarity.support,
);
RuleRecord rule({
  Expr? expr,
  Validity? validity,
  Applicability applicability = const UniverseApplicability(),
  CommitPolicy policy = CommitPolicy.blockUnlessException,
  List<String> capabilities = const ['basic.v1'],
  List<RecordId> types = const [],
}) => RuleRecord(
  namespace: 'test',
  key: 'period',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: policy,
  applicability: applicability,
  subjectTypes: types,
  targetPredicates: ['test:open'],
  expression: expr ?? claim,
  capabilities: capabilities,
  executable: true,
  validity: validity ?? interval(10, 20),
);
RecordVersion assertion({
  Validity? validity,
  Scope? cell,
  Precision precision = Precision.exact,
}) => record(
  3,
  AssertionRecord(
    attributeMode: AttributeMode.instance,
    proposition: ref(2),
    polarity: Polarity.support,
    scope: cell ?? scope,
    validity: validity ?? interval(10, 20),
    persistence: PersistenceSemantics.explicitInterval,
    precision: precision,
    basis: const AuthorDecisionBasis('explicit period'),
  ),
);
List<RecordVersion> fixture() => [
  record(
    1,
    PropertyRecord(
      namespace: 'test',
      key: 'open',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  record(
    2,
    PropositionRecord(
      subject: ref(80),
      predicate: ref(1),
      context: ref(99),
      value: const BooleanValue(true),
      quantification: Quantification.particular,
    ),
  ),
  assertion(),
  record(4, rule()),
  record(
    80,
    EntityRecord(
      names: [],
      classificationResolution: ClassificationResolution.unclassified,
      worldAssociations: [],
      labels: {},
      metadata: {},
    ),
  ),
  record(
    99,
    RepresentedContextRecord(
      universe: universe,
      kind: const ObjectiveContext(),
      labels: {},
    ),
  ),
];
void replace(List<RecordVersion> records, RecordVersion next) =>
    records[records.indexWhere(
          (r) => r.identity.recordId == next.identity.recordId,
        )] =
        next;
CheckedRule check(
  List<RecordVersion> records, {
  bool indexed = false,
  List<RecordId> footprint = const [],
  Frame? base,
}) => evaluateCandidateRule(
  record: records.firstWhere((r) => r.identity.recordId == id(4)),
  records: records,
  base: base ?? frame(),
  footprint: footprint,
  index: indexed ? EvaluationIndex(records) : null,
);
RecordVersion decision({
  IssueDecisionMode mode = IssueDecisionMode.accept,
  String? target,
  String rationale = 'Reviewed exception',
}) => record(
  5,
  IssueDecisionRecord(
    fingerprints: [],
    mode: mode,
    scope: target ?? id(4).value,
    rationale: rationale,
    principal: PrincipalId.parse('prn_${suffix(1)}'),
  ),
);
ExceptionRecord exception({
  Validity? validity,
  Scope? cell,
  RecordVersionId? pin,
  String rationale = 'Only in this period',
}) => ExceptionRecord(
  rule: ref(4),
  ruleVersion: pin ?? version(4),
  scope: cell ?? scope,
  validity: validity ?? interval(12, 18),
  authorizingDecision: ref(5),
  rationale: rationale,
);
void main() {
  test(
    'rules check every exact interval and never leak into another world',
    () {
      final records = fixture();
      expect(check(records).accepted, isTrue);
      replace(records, assertion(validity: interval(10, 19)));
      expect(check(records).accepted, isFalse);
      replace(records, record(4, rule(validity: interval(10, 19))));
      expect(check(records).accepted, isTrue);
      final a = WorldId.parse('wld_${suffix(32)}'),
          b = WorldId.parse('wld_${suffix(33)}');
      replace(
        records,
        record(4, rule(applicability: WorldsApplicability([a]))),
      );
      replace(
        records,
        assertion(
          cell: Scope(
            context: ref(99),
            applicability: WorldsApplicability([b]),
          ),
        ),
      );
      expect(check(records, footprint: [id(32), id(33)]).accepted, isFalse);
      expect(check(records, footprint: []).complete, isFalse);
    },
  );
  test('partitioned interval checks agree with every tick across record permutations', () {
    for (var start = 8; start <= 12; start++) {
      for (var end = 18; end <= 22; end++) {
        final records = fixture();
        replace(records, assertion(validity: interval(start, end)));
        final expected = List.generate(
          10,
          (i) => i + 10,
        ).every((n) => start <= n && n < end);
        for (var rotation = 0; rotation < records.length; rotation++) {
          final changed = [
            ...records.skip(rotation),
            ...records.take(rotation),
          ];
          final direct = check(changed),
              indexed = check(changed, indexed: true);
          expect(direct.accepted, expected);
          expect(indexed.accepted, direct.accepted);
          expect(indexed.complete, direct.complete);
          expect(indexed.evidence, direct.evidence);
        }
      }
    }
  });
  test(
    'narrow exceptions preserve findings and cannot disable the rest of a rule',
    () {
      final records = fixture();
      replace(records, record(4, rule(expr: const LiteralExpr(false))));
      records.addAll([decision(), record(6, exception())]);
      expect(validException(exception(), records), isTrue);
      expect(check(records).accepted, isFalse);
      replace(records, record(6, exception(validity: interval(10, 20))));
      for (final indexed in [false, true]) {
        final result = check(records, indexed: indexed);
        expect(result.accepted, isTrue);
        expect(result.complete, isTrue);
        expect(result.evidence.outcome, EvidenceOutcome.refuted);
      }
      expect(
        validException(exception(validity: interval(9, 20)), records),
        isFalse,
      );
      expect(validException(exception(pin: version(40)), records), isFalse);
      replace(records, decision(mode: IssueDecisionMode.defer));
      expect(check(records).accepted, isFalse);
    },
  );
  test('exceptions require the exact policy, decision, context and contained jurisdiction', () {
    final records = fixture()..add(decision());
    expect(
      validException(exception(rationale: '\u0085\u3000'), records),
      isFalse,
    );
    expect(validException(exception(rationale: '\ufeff'), records), isTrue);
    replace(records, decision(target: id(9).value));
    expect(validException(exception(), records), isFalse);
    replace(records, decision(rationale: '\u0085'));
    expect(validException(exception(), records), isFalse);
    replace(records, decision());
    replace(records, record(4, rule(policy: CommitPolicy.alwaysBlock)));
    expect(validException(exception(), records), isFalse);
    replace(records, record(4, rule()));
    final at = frame(time: AtFrameTime(ExactTime(calendar, '15')));
    expect(exceptionAt(exception(), records[3], at, [], records), isTrue);
    expect(
      exceptionAt(
        exception(
          cell: Scope(
            context: ref(9),
            applicability: const UniverseApplicability(),
          ),
        ),
        records[3],
        at,
        [],
        records,
      ),
      isFalse,
    );
    expect(
      exceptionAt(
        exception(),
        records[3],
        frame(time: AtFrameTime(ExactTime(calendar, '18'))),
        [],
        records,
      ),
      isFalse,
    );
    expect(exceptionAt(exception(), records[3], frame(), [], records), isFalse);
    final w = WorldId.parse('wld_${suffix(32)}');
    replace(records, record(4, rule(applicability: WorldsApplicability([w]))));
    expect(validException(exception(), records), isFalse);
    final scoped = exception(
      cell: Scope(context: ref(99), applicability: WorldsApplicability([w])),
    );
    expect(validException(scoped, records), isTrue);
    expect(
      exceptionAt(scoped, records[3], at, [id(32), id(33)], records),
      isFalse,
    );
  });
  test(
    'unsupported semantics or capabilities cannot be waived into acceptance',
    () {
      final records = fixture();
      replace(
        records,
        record(
          4,
          rule(expr: const LiteralExpr(false), capabilities: ['future.v1']),
        ),
      );
      records.addAll([
        decision(),
        record(6, exception(validity: interval(10, 20))),
      ]);
      final checked = check(records);
      expect(checked.accepted, isFalse);
      expect(checked.complete, isFalse);
      replace(
        records,
        record(
          4,
          rule(
            expr: CompareExpr(
              const VariableOperand('missing'),
              Comparator.eq,
              const ValueOperand(BooleanValue(true)),
            ),
          ),
        ),
      );
      expect(check(records).accepted, isFalse);
      expect(check(records).complete, isFalse);
    },
  );
  test('unresolved partitions and reserved numeric endpoints never become completed checks', () {
    final records = fixture();
    replace(records, record(4, rule(validity: const UnknownValidity())));
    expect(check(records).complete, isFalse);
    replace(records, record(4, rule(expr: const LiteralExpr(true))));
    replace(
      records,
      assertion(
        validity: CalendarIntervalValidity(
          calendar,
          const UnknownBound(),
          const ExactBound('20'),
        ),
      ),
    );
    expect(check(records).complete, isFalse);
    final max = (BigInt.one << 127) - BigInt.one;
    replace(records, assertion());
    replace(
      records,
      record(
        4,
        rule(
          expr: const LiteralExpr(true),
          validity: InstantValidity(ExactTime(calendar, '$max')),
        ),
      ),
    );
    expect(check(records).complete, isFalse);
    replace(
      records,
      record(
        4,
        rule(
          expr: const LiteralExpr(true),
          validity: CalendarIntervalValidity(
            calendar,
            const UnboundedBound(),
            const UnboundedBound(),
          ),
        ),
      ),
    );
    expect(check(records).accepted, isTrue);
  });
  test('dated opposition is checked outside the submitted frame without unrelated clock widening', () {
    final records = fixture();
    final expression = NoOpposingEvidenceExpr(
      RecordOperand(ref(80)),
      'test:open',
      RecordOperand(ref(99)),
    );
    replace(
      records,
      record(
        4,
        rule(
          expr: expression,
          validity: const UnspecifiedValidity(),
          capabilities: ['opposing_evidence.v1'],
        ),
      ),
    );
    records.add(
      record(
        7,
        AssertionRecord(
          attributeMode: AttributeMode.instance,
          proposition: ref(2),
          polarity: Polarity.refutation,
          scope: scope,
          validity: interval(12, 14),
          persistence: PersistenceSemantics.explicitInterval,
          precision: Precision.exact,
          basis: const AuthorDecisionBasis('opposed'),
        ),
      ),
    );
    expect(
      check(
        records,
        base: frame(time: AtFrameTime(ExactTime(calendar, '30'))),
      ).accepted,
      isFalse,
    );
    expect(
      check(records, indexed: true).evidence.outcome,
      EvidenceOutcome.refuted,
    );
    records.add(
      record(
        8,
        AssertionRecord(
          attributeMode: AttributeMode.instance,
          proposition: ref(9),
          polarity: Polarity.support,
          scope: scope,
          validity: CalendarIntervalValidity(
            CalendarId.parse('cal_${suffix(11)}'),
            const ExactBound('0'),
            const ExactBound('10'),
          ),
          persistence: PersistenceSemantics.explicitInterval,
          precision: Precision.exact,
          basis: const AuthorDecisionBasis('unrelated'),
        ),
      ),
    );
    records.add(
      record(
        9,
        PropositionRecord(
          subject: ref(81),
          predicate: ref(1),
          context: ref(99),
          value: const BooleanValue(true),
          quantification: Quantification.particular,
        ),
      ),
    );
    records.add(
      record(
        81,
        EntityRecord(
          names: [],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [],
          labels: {},
          metadata: {},
        ),
      ),
    );
    expect(check(records).complete, isTrue);
    replace(
      records,
      record(
        9,
        PropositionRecord(
          subject: ref(80),
          predicate: ref(1),
          context: ref(99),
          value: const BooleanValue(true),
          quantification: Quantification.particular,
        ),
      ),
    );
    expect(check(records).complete, isFalse);
  });
  test('temporal partition and world-product work stays bounded at one thousand cells', () {
    final records = fixture();
    replace(
      records,
      record(
        4,
        rule(expr: const LiteralExpr(true), validity: interval(0, 2000)),
      ),
    );
    for (var n = 0; n < 1000; n++) {
      records.add(
        record(
          100 + n,
          EpistemicAttitudeRecord(
            holder: ref(80),
            proposition: ref(2),
            attitude: EpistemicAttitudeKind.believes,
            validity: InstantValidity(ExactTime(calendar, '${2 * n}')),
            basis: const AuthorDecisionBasis('dated belief'),
          ),
        ),
      );
    }
    expect(check(records).complete, isFalse);
    final few = fixture();
    replace(few, record(4, rule(expr: const LiteralExpr(true))));
    expect(
      check(few, footprint: List.generate(501, (n) => id(100 + n))).complete,
      isTrue,
    );
    expect(
      check(few, footprint: List.generate(1001, (n) => id(100 + n))).complete,
      isFalse,
    );
  });
  test('unresolved relevant classification cannot pass while disjoint types are skipped', () {
    final records = fixture();
    replace(
      records,
      record(4, rule(expr: const LiteralExpr(false), types: [id(20)])),
    );
    expect(check(records).complete, isFalse);
    records.add(
      record(
        20,
        EntityTypeRecord(
          namespace: 'test',
          key: 'type',
          name: 'Type',
          labels: {},
          parentResolution: ParentResolution.root,
          applicability: const UniverseApplicability(),
          classificationExecutable: true,
        ),
      ),
    );
    records.add(
      record(
        21,
        EntityTypeRecord(
          namespace: 'test',
          key: 'other',
          name: 'Other',
          labels: {},
          parentResolution: ParentResolution.root,
          applicability: const UniverseApplicability(),
          classificationExecutable: true,
        ),
      ),
    );
    replace(
      records,
      record(
        80,
        EntityRecord(
          names: [],
          classification: id(21),
          classificationResolution: ClassificationResolution.resolved,
          worldAssociations: [],
          labels: {},
          metadata: {},
        ),
      ),
    );
    expect(check(records).accepted, isTrue);
    expect(check(records).evidence.outcome, EvidenceOutcome.supported);
  });
}
