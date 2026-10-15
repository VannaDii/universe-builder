import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
RecordVersion record(int n, RecordPayload p) => RecordVersion.build(
  recordVersionId: version(n),
  identity: RecordIdentity(
    universeId: universe,
    recordId: id(n),
    recordKind: p.recordKind,
  ),
  payload: p,
);
final cell = Scope(
  context: ref(3),
  applicability: const UniverseApplicability(),
);
Frame frame({FrameTime? time}) => Frame(
  universe: universe,
  continuity: ContinuityId.parse('cont_${suffix(1)}'),
  revision: RevisionId.parse('rev_${suffix(1)}'),
  context: ref(3),
  time: time ?? AtFrameTime(ExactTime(calendar, '10')),
  perspective: const AuthorPerspective(),
);
PropertyRecord property({
  List<RecordId> types = const [],
  Multiplicity multiplicity = Multiplicity.single,
}) => PropertyRecord(
  namespace: 'author',
  key: 'attribute',
  labels: {},
  subjectTypes: types,
  value: const SimpleValueShape(SimpleShapeKind.boolean),
  multiplicity: multiplicity,
  persistence: PersistenceSemantics.explicitInterval,
  exclusive: false,
  symmetric: false,
  transitive: false,
);
RecordVersion prop(
  int n, {
  int subject = 1,
  DomainValue? value = const BooleanValue(true),
  List<PropositionRole> roles = const [],
}) => record(
  n,
  PropositionRecord(
    subject: ref(subject),
    predicate: ref(2),
    context: ref(3),
    value: value,
    quantification: Quantification.particular,
    roles: roles,
  ),
);
RecordVersion assertion(
  int n,
  int target, {
  Polarity polarity = Polarity.support,
  AttributeMode mode = AttributeMode.instance,
  Validity? validity,
  Precision precision = Precision.exact,
  Scope? scope,
  List<DomainValue> alternatives = const [],
}) => record(
  n,
  AssertionRecord(
    proposition: ref(target),
    polarity: polarity,
    attributeMode: mode,
    scope: scope ?? cell,
    validity:
        validity ??
        CalendarIntervalValidity(
          calendar,
          const ExactBound('0'),
          const UnboundedBound(),
        ),
    precision: precision,
    alternatives: alternatives,
    persistence: PersistenceSemantics.explicitInterval,
    basis: const AuthorDecisionBasis('claim fixture'),
  ),
);
List<RecordVersion> direct() => [
  record(2, property()),
  prop(4),
  assertion(5, 4),
];
ClaimExpr claim({
  Operand? subject,
  Operand? value = const ValueOperand(BooleanValue(true)),
  List<ExprRole> roles = const [],
  Operand? context,
  Polarity polarity = Polarity.support,
}) => ClaimExpr(
  subject: subject ?? RecordOperand(ref(1)),
  predicate: 'author:attribute',
  value: value,
  roles: roles,
  context: context,
  polarity: polarity,
);
(Evidence, bool) run(
  List<RecordVersion> rows, {
  Expr? expr,
  Frame? selected,
  bool indexed = false,
  List<RecordId>? worlds,
  List<(RecordId, RecordVersion?)> changes = const [],
}) => evaluateExpression(
  expr ?? claim(),
  EvaluationContext(
    baseSnapshot: rows,
    frame: selected ?? frame(),
    index: indexed ? EvaluationIndex(rows) : null,
    worldScope: worlds,
    candidateChanges: changes,
  ),
);
EntityTypeRecord type({
  RecordId? parent,
  ParentResolution resolution = ParentResolution.root,
  Applicability scope = const UniverseApplicability(),
}) => EntityTypeRecord(
  namespace: 'author',
  key: 'type',
  labels: {},
  name: 'Type',
  parent: parent,
  parentResolution: resolution,
  applicability: scope,
  classificationExecutable: true,
);
RecordVersion entity({
  ClassificationResolution resolution = ClassificationResolution.resolved,
}) => record(
  1,
  EntityRecord(
    names: [],
    labels: {},
    metadata: {},
    worldAssociations: [],
    classification: id(20),
    classificationResolution: resolution,
  ),
);
List<RecordVersion> inherited() => [
  entity(),
  record(20, type()),
  record(2, property()),
  prop(4, subject: 20),
  assertion(5, 4, mode: AttributeMode.shared),
];
RecordVersion closed({
  CompletenessKind kind = const ObjectiveCompleteness(),
  List<RecordRef> members = const [],
  Scope? scope,
  Validity? validity,
}) => record(
  30,
  CompletenessRecord(
    subject: ref(1),
    predicate: 'author:attribute',
    members: members,
    completeness: kind,
    validity:
        validity ??
        CalendarIntervalValidity(
          calendar,
          const ExactBound('0'),
          const UnboundedBound(),
        ),
    scope: scope ?? cell,
  ),
);
void main() {
  test('indexed direct claims for unclassified entities keep coverage above the linear scan limit', () {
    final owner = record(
      1,
      EntityRecord(
        names: [],
        labels: {},
        metadata: {},
        worldAssociations: [],
        classificationResolution: ClassificationResolution.unclassified,
      ),
    );
    final small = [...direct(), owner];
    final large = [
      ...small,
      for (var n = 1000; n < 12000; n++)
        record(
          n,
          SourceRecord(
            label: 'Unrelated $n',
            origin: const OriginMetadata(),
            versions: [],
          ),
        ),
    ];
    final expected = run(small);
    final indexed = run(large, indexed: true);
    expect(indexed.$1, expected.$1);
    expect(indexed.$2, isTrue);
    expect(indexed.$1.support.sources, [version(5)]);
    expect(run(large).$2, isFalse);
    // Unknown classification plus shared evidence still requires the broader
    // conservative evaluation; indexing must not turn it into a complete claim.
    final shared = [
      ...large,
      record(20, type()),
      prop(21, subject: 20),
      assertion(22, 21, mode: AttributeMode.shared),
    ];
    expect(run(shared, indexed: true).$2, isFalse);
    final scoped = [
      ...small,
      record(20, type()),
      prop(21, subject: 20),
      assertion(22, 21, mode: AttributeMode.shared),
    ];
    expect(run(scoped, indexed: true), run(scoped));
  });

  test('direct claims retain both evidence sides, negation and existence semantics', () {
    final rows = direct()..add(assertion(6, 4, polarity: Polarity.refutation));
    for (final indexed in [false, true]) {
      final (e, c) = run(rows, indexed: indexed);
      expect(e.outcome, EvidenceOutcome.conflicting);
      expect(e.support.sources, [version(5)]);
      expect(e.refutation.sources, [version(6)]);
      expect(c, isTrue);
      expect(
        run(rows, expr: claim(polarity: Polarity.refutation)).$1,
        e.negate(),
      );
      expect(
        run(
          rows,
          expr: NegatedClaimExpr(
            subject: RecordOperand(ref(1)),
            predicate: 'author:attribute',
            value: const ValueOperand(BooleanValue(true)),
          ),
        ).$1,
        e.negate(),
      );
      final existence = run(
        rows,
        expr: ExistenceExpr(
          subject: RecordOperand(ref(1)),
          predicate: 'author:attribute',
          value: const ValueOperand(BooleanValue(true)),
        ),
      ).$1;
      expect(existence.outcome, EvidenceOutcome.supported);
      expect(existence.refutation.sources, isEmpty);
    }
    expect(
      run([record(2, property())]).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    expect(run([record(2, property())]).$2, isTrue);
  });
  test(
    'missing or ambiguous definitions and unresolved operands cannot pass',
    () {
      expect(run([]).$2, isFalse);
      expect(run(direct()..add(record(9, property()))).$2, isFalse);
      expect(
        run(
          direct(),
          expr: claim(subject: const ValueOperand(BooleanValue(true))),
        ).$2,
        isFalse,
      );
      expect(
        run(direct(), expr: claim(value: const VariableOperand('missing'))).$2,
        isFalse,
      );
      expect(
        run(
          direct(),
          expr: claim(
            subject: RecordOperand(
              RecordRef(
                universe: UniverseId.parse('unv_${suffix(9)}'),
                record: id(1),
              ),
            ),
          ),
        ).$2,
        isFalse,
      );
      expect(
        run(
          direct(),
          expr: claim(subject: RecordOperand(RecordRef(record: id(1)))),
        ).$1.outcome,
        EvidenceOutcome.notEstablished,
      );
      expect(
        evaluateExpression(
          claim(),
          EvaluationContext(baseSnapshot: direct()),
        ).$2,
        isFalse,
      );
    },
  );
  test(
    'candidate additions, replacements and removals bypass the old index',
    () {
      final rows = direct();
      expect(
        run(rows, indexed: true, changes: [(id(5), null)]).$1.outcome,
        EvidenceOutcome.notEstablished,
      );
      expect(
        run(
          rows,
          indexed: true,
          changes: [(id(5), assertion(5, 4, polarity: Polarity.refutation))],
        ).$1.outcome,
        EvidenceOutcome.refuted,
      );
      expect(
        run(
          rows,
          indexed: true,
          changes: [(id(6), assertion(6, 4, polarity: Polarity.refutation))],
        ).$1.outcome,
        EvidenceOutcome.conflicting,
      );
      expect(run(rows, changes: [(id(2), null)]).$2, isFalse);
    },
  );
  test(
    'uncertainty stays incomplete unless another dimension proves disjointness',
    () {
      for (final a in [
        assertion(5, 4, precision: Precision.approximate),
        assertion(5, 4, alternatives: [const BooleanValue(false)]),
        assertion(5, 4, validity: const UnknownValidity()),
        assertion(
          5,
          4,
          scope: Scope(
            context: ref(3),
            applicability: const UnspecifiedApplicability(),
          ),
        ),
        assertion(
          5,
          4,
          scope: Scope(
            context: ref(3),
            applicability: const UniverseApplicability(),
            realm: ref(40),
          ),
        ),
      ]) {
        final result = run([record(2, property()), prop(4), a]);
        expect(result.$1.outcome, EvidenceOutcome.notEstablished);
        expect(result.$2, isFalse);
      }
      final expired = assertion(
        5,
        4,
        precision: Precision.approximate,
        validity: CalendarIntervalValidity(
          calendar,
          const ExactBound('1'),
          const ExactBound('10'),
        ),
      );
      expect(run([record(2, property()), prop(4), expired]).$2, isTrue);
      final elsewhere = assertion(
        5,
        4,
        validity: const UnknownValidity(),
        scope: Scope(
          context: ref(3),
          applicability: WorldsApplicability([
            WorldId.parse('wld_${suffix(41)}'),
          ]),
        ),
      );
      expect(
        run([record(2, property()), prop(4), elsewhere], worlds: [id(42)]).$2,
        isTrue,
      );
      expect(
        run([
          record(2, property()),
          prop(4),
          assertion(5, 4, validity: const UnspecifiedValidity()),
        ], selected: frame(time: const TimelessFrameTime())).$1.outcome,
        EvidenceOutcome.supported,
      );
      expect(
        run([
          record(2, property()),
          prop(4),
          expired,
        ], selected: frame(time: const TimelessFrameTime())).$2,
        isFalse,
      );
    },
  );
  test('world applicability is explicit and covers every selected world', () {
    final scoped = assertion(
      5,
      4,
      scope: Scope(
        context: ref(3),
        applicability: WorldsApplicability([
          WorldId.parse('wld_${suffix(41)}'),
        ]),
      ),
    );
    final rows = [record(2, property()), prop(4), scoped];
    expect(run(rows).$2, isFalse);
    expect(run(rows, worlds: [id(41)]).$1.outcome, EvidenceOutcome.supported);
    expect(
      run(rows, worlds: [id(41), id(42)]).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    expect(run(rows, worlds: [id(41), id(42)]).$2, isTrue);
    expect(
      run(rows, expr: claim(context: RecordOperand(ref(99)))).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
  });
  test('exact-role claims differ from partial role-existence queries', () {
    final rows = [
      record(2, property()),
      prop(
        4,
        roles: [PropositionRole('from', ref(7)), PropositionRole('to', ref(8))],
      ),
      assertion(5, 4),
    ];
    final role = ExprRole('from', RecordOperand(ref(7)));
    expect(
      run(rows, expr: claim(roles: [role])).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    expect(
      run(
        rows,
        expr: claim(roles: [role, ExprRole('to', RecordOperand(ref(8)))]),
      ).$1.outcome,
      EvidenceOutcome.supported,
    );
    expect(
      run(
        rows,
        expr: RoleHoldsExpr(
          RecordOperand(ref(1)),
          'author:attribute',
          'from',
          RecordOperand(ref(7)),
        ),
      ).$1.outcome,
      EvidenceOutcome.supported,
    );
    rows[2] = assertion(5, 4, polarity: Polarity.refutation);
    expect(
      run(
        rows,
        expr: RoleHoldsExpr(
          RecordOperand(ref(1)),
          'author:attribute',
          'from',
          RecordOperand(ref(7)),
        ),
      ).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
  });
  test('numeric equality is exact while mismatching direct values do not imply refutation', () {
    final rows = [
      record(2, property()),
      prop(4, value: const IntegerValue('1')),
      assertion(5, 4),
    ];
    expect(
      run(
        rows,
        expr: claim(value: const ValueOperand(RationalValue('2', '2'))),
      ).$1.outcome,
      EvidenceOutcome.supported,
    );
    expect(
      run(
        rows,
        expr: claim(value: const ValueOperand(IntegerValue('2'))),
      ).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
  });
  test('shared inheritance retains owner, proposition and complete ancestry provenance', () {
    final rows = inherited();
    for (final indexed in [false, true]) {
      final (e, c) = run(rows, indexed: indexed);
      expect(e.outcome, EvidenceOutcome.supported);
      expect(e.support.sources, [
        version(1),
        version(4),
        version(5),
        version(20),
      ]);
      expect(c, isTrue);
    }
    rows[4] = assertion(5, 4);
    expect(run(rows).$1.outcome, EvidenceOutcome.notEstablished);
    rows[4] = assertion(5, 4, mode: AttributeMode.shared);
    rows[0] = entity(resolution: ClassificationResolution.ambiguous);
    expect(run(rows).$2, isFalse);
    expect(run(rows).$1.outcome, EvidenceOutcome.notEstablished);
  });
  test('single shared definitions and incompatible instance claims retain conflicts', () {
    final rows = inherited()
      ..addAll([prop(6, value: const BooleanValue(false)), assertion(7, 6)]);
    expect(run(rows).$1.outcome, EvidenceOutcome.conflicting);
    expect(
      run(
        rows,
        expr: claim(value: const ValueOperand(BooleanValue(false))),
      ).$1.outcome,
      EvidenceOutcome.conflicting,
    );
    rows[2] = record(2, property(multiplicity: Multiplicity.multiple));
    expect(run(rows).$1.outcome, EvidenceOutcome.supported);
    expect(
      run(
        rows,
        expr: claim(value: const ValueOperand(BooleanValue(false))),
      ).$1.outcome,
      EvidenceOutcome.supported,
    );
  });
  test('subject type admission distinguishes impossible, unresolved and applicable claims', () {
    final rows = inherited();
    rows[2] = record(2, property(types: [id(21)]));
    expect(run(rows).$1.outcome, EvidenceOutcome.notEstablished);
    expect(run(rows).$2, isTrue);
    rows[0] = entity(resolution: ClassificationResolution.ambiguous);
    expect(run(rows).$2, isFalse);
    rows[0] = entity();
    rows[2] = record(2, property(types: [id(20)]));
    expect(run(rows).$1.outcome, EvidenceOutcome.supported);
  });
  test('closed objective membership alone can establish absence, never observer knowledge', () {
    final rows = [record(2, property()), closed()];
    expect(
      run(
        rows,
        expr: claim(
          value: ValueOperand(
            ReferenceValue(ValueReferenceKind.entity, ref(7)),
          ),
        ),
      ).$1.refutation.sources,
      [version(30)],
    );
    expect(
      run(rows, expr: claim(value: null)).$1.outcome,
      EvidenceOutcome.refuted,
    );
    expect(run(rows).$1.outcome, EvidenceOutcome.notEstablished);
    rows[1] = closed(kind: ObserverCompleteness(id(1)));
    expect(
      run(rows, expr: claim(value: null)).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    rows[1] = closed(members: [ref(7)]);
    expect(
      run(
        rows,
        expr: claim(
          value: ValueOperand(
            ReferenceValue(ValueReferenceKind.entity, ref(7)),
          ),
        ),
      ).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    rows[1] = closed(
      scope: Scope(
        context: ref(3),
        applicability: WorldsApplicability([
          WorldId.parse('wld_${suffix(41)}'),
        ]),
      ),
    );
    expect(
      run(rows, expr: claim(value: null), worlds: [id(41)]).$1.outcome,
      EvidenceOutcome.refuted,
    );
    expect(
      run(rows, expr: claim(value: null), worlds: [id(41), id(42)]).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
  });
  test('powers remain visible through claim indexing and candidate custody removal', () {
    final rows = [
      record(2, property()),
      record(
        6,
        ItemPowerRecord(
          item: ref(10),
          holderPredicate: ref(11),
          powerPredicate: ref(2),
          value: const BooleanValue(true),
          scope: cell,
          validity: CalendarIntervalValidity(
            calendar,
            const ExactBound('0'),
            const UnboundedBound(),
          ),
        ),
      ),
      record(
        7,
        PropositionRecord(
          subject: ref(10),
          predicate: ref(11),
          context: ref(3),
          value: ReferenceValue(ValueReferenceKind.entity, ref(1)),
          quantification: Quantification.particular,
        ),
      ),
      assertion(8, 7),
    ];
    for (final indexed in [false, true]) {
      expect(run(rows, indexed: indexed).$1.support.sources, [
        version(6),
        version(7),
        version(8),
      ]);
      expect(
        run(rows, indexed: indexed, changes: [(id(8), null)]).$1.outcome,
        EvidenceOutcome.notEstablished,
      );
    }
    expect(
      run(rows, selected: frame(time: const TimelessFrameTime())).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
  });
  test('claims use candidate event boundaries while completeness keeps its base event binding', () {
    final event = record(
      40,
      EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        time: ExactTime(calendar, '10'),
        participants: [],
        labels: {},
      ),
    );
    final validity = CalendarIntervalValidity(
      calendar,
      const ExactBound('10'),
      const ExactBound('20'),
    );
    final rows = [
      record(2, property()),
      prop(4),
      assertion(5, 4, validity: validity),
      event,
    ];
    expect(
      run(
        rows,
        selected: frame(time: AtEventFrameTime(ref(40), EventTimeSide.before)),
      ).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    expect(
      run(
        rows,
        selected: frame(time: AtEventFrameTime(ref(40), EventTimeSide.after)),
        indexed: true,
      ).$1.outcome,
      EvidenceOutcome.supported,
    );
    expect(
      run(
        rows,
        selected: frame(time: AtEventFrameTime(ref(40), EventTimeSide.after)),
        changes: [(id(40), null)],
      ).$2,
      isFalse,
    );
    final closedRows = [record(2, property()), closed(validity: validity)];
    expect(
      run(
        closedRows,
        expr: claim(value: null),
        selected: frame(time: AtEventFrameTime(ref(40), EventTimeSide.after)),
        changes: [(id(40), event)],
      ).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    closedRows.add(event);
    expect(
      run(
        closedRows,
        expr: claim(value: null),
        selected: frame(time: AtEventFrameTime(ref(40), EventTimeSide.after)),
      ).$1.outcome,
      EvidenceOutcome.refuted,
    );
  });
  test('scoped powers and shared definitions retain incompatible evidence', () {
    final world = WorldId.parse('wld_${suffix(41)}');
    final rows = inherited();
    rows[3] = prop(4, subject: 20, value: const BooleanValue(false));
    rows.addAll([
      record(
        6,
        ItemPowerRecord(
          item: ref(10),
          holderPredicate: ref(11),
          powerPredicate: ref(2),
          value: const BooleanValue(true),
          scope: Scope(
            context: ref(3),
            applicability: WorldsApplicability([world]),
          ),
          validity: CalendarIntervalValidity(
            calendar,
            const ExactBound('0'),
            const UnboundedBound(),
          ),
        ),
      ),
      record(
        7,
        PropositionRecord(
          subject: ref(10),
          predicate: ref(11),
          context: ref(3),
          value: ReferenceValue(ValueReferenceKind.entity, ref(1)),
          quantification: Quantification.particular,
        ),
      ),
      assertion(8, 7),
    ]);
    final (e, c) = run(rows, worlds: [id(41)], indexed: true);
    expect(c, isTrue);
    expect(e.outcome, EvidenceOutcome.conflicting);
    expect(e.support.sources, [version(6), version(7), version(8)]);
    expect(e.refutation.sources, [
      version(1),
      version(4),
      version(5),
      version(20),
    ]);
    expect(
      run(
        rows,
        expr: claim(value: const ValueOperand(BooleanValue(false))),
        worlds: [id(41)],
      ).$1.outcome,
      EvidenceOutcome.conflicting,
    );
    expect(run(rows, worlds: [id(42)]).$1.outcome, EvidenceOutcome.refuted);
  });
  test(
    'claim traversal retains the existing shared expression work budget',
    () {
      final rows = List.generate(
        9999,
        (n) => record(n + 100, WorldRecord(selector: 'filler')),
      )..addAll(direct());
      expect(run(rows).$2, isFalse);
      expect(run(rows, indexed: true).$2, isTrue);
      expect(run(rows, indexed: true).$1.outcome, EvidenceOutcome.supported);
      final repeated = AllExpr(List.generate(2500, (_) => claim()));
      expect(run(direct(), expr: repeated, indexed: true).$2, isFalse);
    },
  );
}
