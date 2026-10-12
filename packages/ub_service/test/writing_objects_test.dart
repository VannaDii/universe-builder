import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as rules;
import 'writing_binding_test.dart' as binding;
import 'writing_units_test.dart' as units;

PropertyRecord property({
  String key = 'count',
  ValueShape shape = const SimpleValueShape(SimpleShapeKind.integer),
  PersistenceSemantics persistence = PersistenceSemantics.unspecified,
}) => PropertyRecord(
  namespace: 'authoring',
  key: key,
  labels: {},
  value: shape,
  multiplicity: Multiplicity.multiple,
  persistence: persistence,
  exclusive: false,
  symmetric: false,
  transitive: false,
);

FactChange fact({
  String property = 'count',
  FactValue? value,
  String scope = 'universe',
  String when = 'scene',
  String? tick,
  FactLifetime lifetime = const FactUnspecifiedLifetime(),
  bool negated = false,
  String statement = 'objective',
}) => FactChange(
  property: property,
  value: value ?? FactNumberValue(const CanonicalNumber('9007199254740993')),
  scope: scope,
  when: when,
  atTick: tick,
  lifetime: lifetime,
  negated: negated,
  statement: statement,
);

final frame = rules.frame(
  time: AtFrameTime(ExactTime(f.cal, '9007199254740993')),
);
List<RecordVersion> base() => [
  f.row(1, binding.entity(labels: {'en': 'Cedar'})),
  f.row(99, f.entity()),
];

void main() {
  test('world grants and temporal names bind only the pinned writer view', () {
    final world = WorldId.parse('wld_${f.suffix(80)}');
    final rows = [
      ...base(),
      f.row(80, WorldRecord(selector: 'Campaign', aliases: ['Shared Realm'])),
      f.row(
        81,
        binding.entity(
          names: [
            ContextualName(
              text: 'Expired',
              validity: CalendarIntervalValidity(
                f.cal,
                const ExactBound('1'),
                const ExactBound('5'),
              ),
            ),
            const ContextualName(
              text: 'Uncertain',
              validity: UnspecifiedValidity(),
            ),
          ],
        ),
      ),
    ];
    final compiled = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      worldScope: {world},
      definitions: [],
      changes: [
        ObjectChange(
          name: 'Uncertain',
          facts: [fact(scope: ' shared realm ')],
        ),
        ObjectChange(name: 'Expired', facts: [fact()]),
      ],
    );
    expect(compiled.clarifications, [
      "Which existing object is 'Expired', or is this a new independent object?",
    ]);
    final assertion = compiled.operations
        .whereType<AssertPropositionOperation>()
        .single;
    expect(assertion.proposition.subject.record, f.id(81));
    expect(
      assertion.assertion.scope.applicability,
      WorldsApplicability([world]),
    );
    final denied = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      worldScope: {},
      definitions: [],
      changes: [
        ObjectChange(
          name: 'Cedar',
          facts: [fact(scope: 'Campaign')],
        ),
      ],
    );
    expect(denied.operations, isEmpty);
    expect(denied.clarifications, [
      "Which accessible authored world is 'Campaign'?",
    ]);
    final ambiguous = compileWritingObjects(
      frame: frame,
      rows: [
        ...rows,
        f.row(82, binding.entity(labels: {'en': 'Uncertain'})),
      ],
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [
        ObjectChange(name: 'Uncertain', facts: [fact()]),
      ],
    );
    expect(ambiguous.operations, isEmpty);
    expect(ambiguous.clarifications, hasLength(1));
  });

  test('invalid author tokens fail without inventing object or property definitions', () {
    final rows = base();
    Object compile(ObjectChange change) => compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [change],
    );
    Matcher invalid(String field) => throwsA(
      isA<InvalidArgumentError>().having((e) => e.field, 'field', field),
    );
    expect(
      () => compile(ObjectChange(name: '\u00a0\u3000', introduce: true)),
      invalid('changes.name'),
    );
    expect(
      () => compile(
        ObjectChange(
          name: 'Cedar',
          facts: [fact(statement: 'inferred')],
        ),
      ),
      invalid('statement'),
    );
    expect(
      () => compile(
        ObjectChange(
          name: 'Cedar',
          facts: [fact(property: '\u2009')],
        ),
      ),
      invalid('property'),
    );
    expect(
      () => compile(
        ObjectChange(
          name: 'Cedar',
          facts: [fact(when: 'now')],
        ),
      ),
      invalid('when'),
    );
    final ambiguousProperty = compileWritingObjects(
      frame: frame,
      rows: [...rows, f.row(2, property()), f.row(3, property())],
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [
        ObjectChange(name: 'Cedar', facts: [fact()]),
      ],
    );
    expect(ambiguousProperty.operations, isEmpty);
    expect(ambiguousProperty.clarifications, [
      "Which authored property named 'count' applies?",
    ]);
  });

  test('forward identities and exact numeric kinds compile into canonical candidate facts', () {
    final rows = base();
    final before = rows.map((r) => r.toWire().toText()).toList();
    final compiled = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [
        ObjectChange(
          name: 'Iris',
          introduce: true,
          facts: [
            fact(),
            fact(),
            fact(property: 'companion', value: const FactObjectValue('Ash')),
            fact(
              property: 'fraction',
              value: FactNumberValue(
                const CanonicalNumber('9007199254740993.25'),
              ),
            ),
          ],
        ),
        ObjectChange(name: 'Ash', introduce: true),
      ],
    );
    expect(compiled.clarifications, isEmpty);
    expect(compiled.unknowns, isEmpty);
    expect(compiled.unchanged, ['Iris: count']);
    final introductions = compiled.operations
        .whereType<IntroduceInstanceOperation>()
        .toList();
    expect(introductions, hasLength(2));
    final asserted = compiled.operations
        .whereType<AssertPropositionOperation>()
        .toList();
    expect(asserted, hasLength(3));
    expect(
      asserted[0].proposition.value,
      const IntegerValue('9007199254740993'),
    );
    expect(
      asserted[2].proposition.value,
      const DecimalValue('9007199254740993.25'),
    );
    expect(
      (asserted[1].proposition.value as ReferenceValue).record.record.value,
      introductions[1].clientRef,
    );
    expect(
      asserted[0].assertion.validity,
      InstantValidity(ExactTime(f.cal, '9007199254740993')),
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: compiled.operations,
    );
    expect(
      candidate.where((r) => r.payload is PropositionRecord),
      hasLength(3),
    );
    expect(candidate.where((r) => r.payload is AssertionRecord), hasLength(3));
    expect(rows.map((r) => r.toWire().toText()), before);
  });

  test('objective introductions are explicit and repeated identities stay ambiguous', () {
    final rows = base();
    final compiled = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [
        ObjectChange(
          name: 'Dream',
          introduce: true,
          facts: [fact(statement: 'hypothetical')],
        ),
        ObjectChange(name: 'Iris', introduce: true),
        ObjectChange(name: 'Iris', introduce: true),
        ObjectChange(
          name: 'Cedar',
          facts: [
            fact(property: 'companion', value: const FactObjectValue('Iris')),
            fact(statement: 'belief'),
          ],
        ),
      ],
    );
    expect(compiled.operations, isEmpty);
    expect(compiled.excluded, hasLength(2));
    expect(compiled.clarifications, [
      "Are the repeated introductions of 'Iris' the same object or separate identities?",
      "Does the objective narration separately establish 'Dream' as a real new object?",
      "Which object does 'Iris' refer to?",
    ]);
    final collision = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [
        ObjectChange(name: 'Cedar', introduce: true),
        ObjectChange(
          name: 'Missing',
          facts: [
            fact(property: 'companion', value: const FactObjectValue('Cedar')),
          ],
        ),
        ObjectChange(name: 'Cedar', facts: [fact()]),
      ],
    );
    expect(
      collision.operations.whereType<IntroduceInstanceOperation>(),
      hasLength(1),
    );
    expect(collision.clarifications, hasLength(2));
  });

  test('definition bindings distinguish shared facts and initial values', () {
    final rows = base();
    final declarations = [
      DefinitionChange(
        name: 'Lantern',
        introduce: true,
        scope: 'universe',
        sharedAttributes: [
          fact(property: 'colour', value: const FactTextValue('red')),
        ],
        initialValues: [fact()],
      ),
    ];
    final definitions = compileWritingDefinitions(
      declarations: declarations,
      rows: rows,
      worldRows: rows,
    );
    final compiled = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      changes: [],
      definitions: declarations,
      introducedDefinitions: definitions.introduced,
      ambiguousDefinitions: definitions.ambiguous,
    );
    expect(compiled.clarifications, isEmpty);
    final attributes = compiled.operations
        .whereType<AddNamedAttributeOperation>()
        .toList();
    expect(attributes.map((a) => a.evidence.attributeMode), [
      AttributeMode.shared,
      AttributeMode.initialValue,
    ]);
    expect(attributes.map((a) => a.subject.record).toSet(), {
      definitions.introduced['Lantern'],
    });
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: [...definitions.operations, ...compiled.operations],
    );
    expect(candidate.where((r) => r.payload is PropertyRecord), hasLength(2));
    expect(
      candidate
          .where((r) => r.payload is AssertionRecord)
          .map((r) => (r.payload as AssertionRecord).attributeMode)
          .toSet(),
      {AttributeMode.shared, AttributeMode.initialValue},
    );
    final explicit = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      changes: [],
      definitions: declarations,
      introducedDefinitions: definitions.introduced,
      declaredProperties: {'count': (f.id(50), property())},
    );
    expect(
      explicit.operations.whereType<AddNamedAttributeOperation>(),
      hasLength(1),
    );
    expect(
      explicit.operations
          .whereType<AssertPropositionOperation>()
          .single
          .assertion
          .attributeMode,
      AttributeMode.initialValue,
    );
  });

  test(
    'classification refinement requires exact pinned identity and version',
    () {
      final rows = [
        f.row(
          1,
          f.patch(f.entity(classification: f.id(20)), {
            'labels': CanonicalObject([
              MapEntry('en', CanonicalString('Cedar')),
            ]),
          }),
        ),
        f.row(20, f.type(20, key: 'Tree')),
        f.row(21, f.type(21, parent: 20, key: 'Oak')),
      ];
      final compiled = compileWritingObjects(
        frame: frame,
        rows: rows,
        propertyRows: rows,
        worldRows: rows,
        definitions: [],
        changes: [
          ObjectChange(name: 'Cedar', classification: 'Tree'),
          ObjectChange(name: 'Cedar', classification: 'Oak'),
          ObjectChange(name: 'Cedar', classification: 'Unknown'),
        ],
      );
      expect(compiled.unchanged, ['Cedar: classification']);
      final refinement =
          compiled.operations.single as RefineClassificationOperation;
      expect(refinement.entityType, f.id(21));
      expect(refinement.expectedVersion, f.ver(1));
      expect(refinement.record.record, f.id(1));
      expect(compiled.clarifications, [
        "Which exact classification definition is 'Unknown'?",
      ]);
      final candidate = compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: rows,
        operations: compiled.operations,
      );
      expect(
        (candidate.singleWhere((r) => r.identity.recordId == f.id(1)).payload
                as EntityRecord)
            .classification,
        f.id(21),
      );
    },
  );

  test('pinned duplicate matching preserves polarity mode precision scope and validity', () {
    final scope = Scope(
      context: frame.context,
      applicability: const UniverseApplicability(),
    );
    final rows = [
      ...base(),
      f.row(2, property()),
      f.row(
        3,
        PropositionRecord(
          subject: f.ref(1),
          predicate: f.ref(2),
          value: const IntegerValue('9007199254740993'),
          context: frame.context,
          quantification: Quantification.particular,
        ),
      ),
      f.row(
        4,
        AssertionRecord(
          attributeMode: AttributeMode.instance,
          proposition: f.ref(3),
          polarity: Polarity.support,
          scope: scope,
          validity: CalendarIntervalValidity(
            f.cal,
            const ExactBound('9007199254740990'),
            const UnboundedBound(),
          ),
          persistence: PersistenceSemantics.explicitInterval,
          precision: Precision.exact,
          basis: const ImportedClaimBasis(),
        ),
      ),
    ];
    final compiled = compileWritingObjects(
      frame: frame,
      rows: rows,
      propertyRows: rows,
      worldRows: rows,
      definitions: [],
      changes: [
        ObjectChange(
          name: 'Cedar',
          facts: [
            fact(),
            fact(negated: true),
            fact(scope: 'unspecified', when: 'unspecified'),
          ],
        ),
      ],
    );
    expect(compiled.unchanged, ['Cedar: count']);
    final assertions = compiled.operations
        .whereType<AssertPropositionOperation>()
        .toList();
    expect(assertions, hasLength(2));
    expect(assertions[0].assertion.polarity, Polarity.refutation);
    expect(
      assertions[1].assertion.scope.applicability,
      isA<UnspecifiedApplicability>(),
    );
    expect(assertions[1].assertion.validity, isA<UnspecifiedValidity>());
    expect(compiled.unknowns, hasLength(2));
    final imprecise = [
      ...rows.take(rows.length - 1),
      f.row(
        4,
        f.patch(rows.last.payload as AssertionRecord, {
          'precision': CanonicalString('approximate'),
        }),
      ),
    ];
    final uncertain = compileWritingObjects(
      frame: frame,
      rows: imprecise,
      propertyRows: imprecise,
      worldRows: imprecise,
      definitions: [],
      changes: [
        ObjectChange(name: 'Cedar', facts: [fact()]),
      ],
    );
    expect(uncertain.unchanged, isEmpty);
    expect(uncertain.operations, hasLength(1));
  });

  test(
    'units remain exact and explicit lifetimes require authored scene time',
    () {
      final rows = [
        ...base(),
        f.row(2, units.unit()),
        f.row(
          3,
          property(
            key: 'stock',
            persistence: PersistenceSemantics.persistentUntilChanged,
          ),
        ),
      ];
      final compiled = compileWritingObjects(
        frame: frame,
        rows: rows,
        propertyRows: rows,
        worldRows: rows,
        definitions: [],
        changes: [
          ObjectChange(
            name: 'Cedar',
            facts: [
              fact(
                property: 'distance',
                value: FactQuantityValue(
                  amount: const CanonicalNumber('9007199254740993'),
                  unit: 'm',
                ),
              ),
              fact(
                property: 'distance',
                value: FactQuantityValue(
                  amount: const CanonicalNumber('2'),
                  unit: 'unknown',
                ),
              ),
              fact(property: 'stock', tick: '9007199254740994'),
              fact(
                property: 'temporary',
                lifetime: const FactUntilLifetime(endTick: '9007199254740996'),
              ),
              fact(
                property: 'unstarted',
                when: 'unspecified',
                lifetime: const FactUntilChangedLifetime(),
              ),
              fact(property: 'badShape', value: const FactTextValue('three')),
            ],
          ),
        ],
        declaredProperties: {'badShape': (f.id(60), property())},
      );
      expect(compiled.clarifications, hasLength(3));
      expect(
        compiled.operations.whereType<DefinePropertyOperation>(),
        hasLength(2),
      );
      final assertions = compiled.operations
          .whereType<AssertPropositionOperation>()
          .toList();
      expect(assertions, hasLength(3));
      expect(
        assertions[0].proposition.value,
        QuantityValue(
          const IntegerValue('9007199254740993'),
          UnitId.fromRecordId(f.id(2)),
        ),
      );
      expect(
        assertions[1].assertion.validity,
        CalendarIntervalValidity(
          f.cal,
          const ExactBound('9007199254740994'),
          const UnboundedBound(),
        ),
      );
      expect(
        assertions[2].assertion.validity,
        CalendarIntervalValidity(
          f.cal,
          const ExactBound('9007199254740993'),
          const ExactBound('9007199254740996'),
        ),
      );
      final timeless = compileWritingObjects(
        frame: rules.frame(),
        rows: rows,
        propertyRows: rows,
        worldRows: rows,
        definitions: [],
        changes: [
          ObjectChange(name: 'Cedar', facts: [fact()]),
        ],
      );
      expect(timeless.operations, isEmpty);
      expect(timeless.clarifications, [
        'What story time do these scene facts hold at?',
      ]);
    },
  );
}
