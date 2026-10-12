import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart'
    show InvalidArgumentError, UnsupportedSemanticsError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show eventExpansionVersion;
import 'package:ub_service/structural_checks.dart';

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as objects;
import 'knowledge_boundaries_test.dart' as boundaries;
import 'action_checks_test.dart' as actions;
import 'knowledge_checks_test.dart' as knowledge;

RecordVersion context(int n, {RecordRef? parent}) => f.row(
  n,
  RepresentedContextRecord(
    universe: f.u,
    kind: const ObjectiveContext(),
    labels: {},
    parent: parent,
  ),
);
List<RecordVersion> fixture() => [...objects.withInstance(), context(99)];
void edit(
  List<RecordVersion> rows,
  int n,
  Map<String, CanonicalValue> changes,
) => objects.edit(rows, n, changes);
void validate(List<RecordVersion> rows) => validateStructuralCandidate(rows);
void invalid(List<RecordVersion> rows, {String? repair}) => expect(
  () => validate(rows),
  throwsA(
    isA<InvalidArgumentError>().having(
      (e) => e.message,
      'repair',
      repair == null ? anything : contains(repair),
    ),
  ),
);
List<RecordVersion> actionFixture() => [
  ...actions.fixture().where((r) => r.payload is! EventRecord),
  context(10),
];
ActionDefinitionRecord action(
  EffectChange change, {
  RecordRef? predicate,
  EffectCondition? condition,
}) => ActionDefinitionRecord(
  namespace: 'test',
  key: 'action',
  labels: {},
  requirements: [],
  scope: actions.scope,
  validity: const UnspecifiedValidity(),
  consequenceContract: ConsequenceContract([
    EffectSlot(
      slot: 'change',
      order: 0,
      presence: EffectPresence.required,
      target: EffectTarget('actor', predicate ?? f.ref(2)),
      condition: condition ?? const AlwaysEffect(),
      change: change,
      lifetime: const UntilChangedEffect(),
    ),
  ]),
);
DeltaEffect delta(String amount, {UnitId? unit}) => DeltaEffect(
  delta: ConsequenceDecimal(amount),
  minimum: ConsequenceDecimal('0'),
  maximum: ConsequenceDecimal('10'),
  unit: unit,
);

void main() {
  test(
    'event expansion is required before typed world and region admission',
    () {
      final rows = [...actions.fixture(), context(10)];
      invalid(rows, repair: 'expansion version');
      edit(rows, 6, {
        'expansionVersion': CanonicalString(eventExpansionVersion),
      });
      validate(rows);
      edit(rows, 6, {'region': f.ref(2).toCanonical()});
      invalid(rows, repair: 'entity or realm');
      edit(rows, 6, {
        'region': const CanonicalNull(),
        'worlds': CanonicalArray([CanonicalString('wld_${f.suffix(2)}')]),
      });
      invalid(rows, repair: 'event world');
    },
  );
  test('valid inherited and conflicting facts pass structure without resolving canon', () {
    validate(fixture());
  });
  test('property facts require typed subjects contexts predicates explicit matching values', () {
    for (final change in <Map<String, CanonicalValue>>[
      {'subject': f.ref(5).toCanonical()},
      {'context': f.ref(5).toCanonical()},
      {'predicate': f.ref(1).toCanonical()},
      {'value': const CanonicalNull()},
      {'value': IntegerValue('1').toWire()},
      {
        'roles': CanonicalArray([PropositionRole('actor', f.ref(4)).toWire()]),
      },
    ]) {
      final rows = fixture();
      edit(rows, 8, change);
      invalid(rows);
    }
    final rows = fixture();
    edit(rows, 5, {
      'subjectTypes': CanonicalArray([CanonicalString(f.id(3).value)]),
    });
    invalid(rows, repair: 'declared property type');
  });
  test(
    'unresolved classification does not manufacture definite type mismatch',
    () {
      final rows = fixture();
      edit(rows, 1, {'parentResolution': CanonicalString('ambiguous')});
      validate(rows);
    },
  );
  test('numeric lexical and nested sequence validation cannot be bypassed by shape', () {
    final rows = fixture();
    edit(rows, 5, {
      'value': const SimpleValueShape(SimpleShapeKind.integer).toWire(),
    });
    edit(rows, 6, {'value': IntegerValue('1').toWire()});
    edit(rows, 8, {'value': IntegerValue('1e3').toWire()});
    expect(() => validate(rows), throwsFormatException);
    edit(rows, 5, {
      'value': const SequenceShape(SimpleValueShape(SimpleShapeKind.integer))
          .toWire(),
    });
    edit(rows, 6, {
      'value': SequenceValue([IntegerValue('1')]).toWire(),
    });
    edit(rows, 8, {
      'value': SequenceValue([const BooleanValue(true)]).toWire(),
    });
    invalid(rows);
  });
  test('relation facts forbid property values undefined roles and duplicate single roles', () {
    final rows = fixture();
    objects.put(
      rows,
      5,
      RelationRecord(
        namespace: 'test',
        key: 'related',
        labels: {},
        roles: [
          RoleDefinition(
            name: 'target',
            multiplicity: Multiplicity.single,
            ordered: false,
          ),
        ],
      ),
    );
    for (final n in [6, 8]) {
      edit(rows, n, {
        'value': const CanonicalNull(),
        'roles': CanonicalArray([PropositionRole('target', f.ref(4)).toWire()]),
      });
    }
    validate(rows);
    edit(rows, 8, {
      'roles': CanonicalArray([PropositionRole('unknown', f.ref(4)).toWire()]),
    });
    invalid(rows, repair: 'undefined relation role');
    edit(rows, 8, {
      'roles': CanonicalArray([PropositionRole('target', f.ref(1)).toWire()]),
    });
    invalid(rows, repair: 'participant must be an entity');
    edit(rows, 8, {
      'roles': CanonicalArray([
        PropositionRole('target', f.ref(4)).toWire(),
        PropositionRole('target', f.ref(4)).toWire(),
      ]),
    });
    invalid(rows, repair: 'single role');
  });
  test(
    'assertion references context and interval ordering remain explicit',
    () {
      for (final change in <Map<String, CanonicalValue>>[
        {'proposition': f.ref(5).toCanonical()},
        {
          'scope': Scope(
            context: f.ref(5),
            applicability: const UniverseApplicability(),
          ).toWire(),
        },
        {'validity': objects.interval(20, 10).toWire()},
      ]) {
        final rows = fixture();
        edit(rows, 9, change);
        invalid(rows);
      }
      final rows = fixture();
      edit(rows, 9, {'validity': objects.interval(10, 10).toWire()});
      validate(rows);
    },
  );
  test(
    'derived and event evidence require evaluator rather than a submitted flag',
    () {
      for (final basis in [
        EventEffectBasis(f.ref(80), 'change'),
        DerivationBasis([], null),
      ]) {
        final rows = fixture();
        edit(rows, 9, {'basis': basis.toWire()});
        expect(() => validate(rows), throwsA(isA<UnsupportedSemanticsError>()));
      }
      final rows = fixture();
      edit(rows, 9, {'basis': SourceAnchorBasis(f.ref(4), true).toWire()});
      invalid(rows, repair: 'anchor record');
    },
  );
  test(
    'action names scope requirements and duplicate keys preserve source bounds',
    () {
      validate(actionFixture());
      for (final change in <Map<String, CanonicalValue>>[
        {'namespace': CanonicalString(' \u3000')},
        {'key': CanonicalString('é' * 65)},
        {
          'scope': Scope(
            context: f.ref(10),
            realm: f.ref(1),
            applicability: const UniverseApplicability(),
          ).toWire(),
        },
        {
          'scope': Scope(
            context: f.ref(10),
            applicability: const ConditionalApplicability(),
          ).toWire(),
        },
        {
          'requirements': CanonicalArray([
            AttributeRequirement('actor', f.ref(2), IntegerValue('1')).toWire(),
          ]),
        },
        {
          'requirements': CanonicalArray([
            AttributeRequirement(
              '',
              f.ref(2),
              const BooleanValue(true),
            ).toWire(),
          ]),
        },
      ]) {
        final rows = actionFixture();
        edit(rows, 5, change);
        invalid(rows);
      }
      final rows = actionFixture();
      rows.add(f.row(80, objects.get(rows, 5).payload));
      invalid(rows, repair: 'duplicate action');
    },
  );
  test('set and condition consequence values bind exact property shapes and namespace', () {
    final rows = actionFixture();
    objects.put(
      rows,
      5,
      action(const SetEffect(Polarity.support, BooleanValue(true))),
    );
    validate(rows);
    objects.put(
      rows,
      5,
      action(SetEffect(Polarity.support, IntegerValue('1'))),
    );
    invalid(rows, repair: 'set value');
    objects.put(
      rows,
      5,
      action(
        const SetEffect(Polarity.support, BooleanValue(true)),
        predicate: RecordRef(record: f.id(2)),
      ),
    );
    invalid(rows, repair: 'action universe');
    objects.put(
      rows,
      5,
      action(
        const SetEffect(Polarity.support, BooleanValue(true)),
        condition: AttributeEqualsEffect('actor', f.ref(2), IntegerValue('1')),
      ),
    );
    invalid(rows, repair: 'condition value');
  });
  test('delta declarations require single numeric property with integral integer deltas', () {
    final rows = actionFixture();
    objects.put(rows, 5, action(delta('1')));
    invalid(rows, repair: 'consequence delta');
    edit(rows, 2, {
      'value': const SimpleValueShape(SimpleShapeKind.integer).toWire(),
    });
    edit(rows, 3, {'value': IntegerValue('1').toWire()});
    validate(rows);
    objects.put(rows, 5, action(delta('1.5')));
    invalid(rows, repair: 'consequence delta');
    objects.put(rows, 5, action(delta('1.0')));
    validate(rows);
    edit(rows, 2, {'multiplicity': CanonicalString('multiple')});
    invalid(rows, repair: 'consequence delta');
  });
  test('contexts reject cycles wrong parents and depth beyond 32', () {
    final rows = fixture();
    edit(rows, 99, {'parent': f.ref(99).toCanonical()});
    invalid(rows, repair: 'cyclic');
    edit(rows, 99, {'parent': f.ref(4).toCanonical()});
    invalid(rows, repair: 'represented context');
    final deep = [
      for (var n = 1; n <= 33; n++)
        context(n, parent: n == 33 ? null : f.ref(n + 1)),
    ];
    invalid(deep, repair: '32 levels');
    validate(deep.sublist(1));
  });
  test(
    'protected rule wrappers and typed knowledge boundaries validate together',
    () {
      final rows = boundaries.fixture();
      edit(rows, 1, {'value': IntegerValue('1').toWire()});
      validate(rows);
      edit(rows, 3, {'commitPolicy': CanonicalString('advisory')});
      invalid(rows);
      final ordinary = fixture();
      ordinary.add(
        f.row(
          80,
          RuleRecord(
            namespace: 'test',
            key: 'fixed',
            labels: {},
            kind: RuleKind.structuralInvariant,
            commitPolicy: CommitPolicy.advisory,
            applicability: const UniverseApplicability(),
            targetPredicates: [],
            expression: const LiteralExpr(true),
            capabilities: [],
            executable: true,
            validity: const UnspecifiedValidity(),
          ),
        ),
      );
      invalid(ordinary, repair: 'cannot be waived');
    },
  );
  test('communication and knowledge require recipients receipt and correctly typed links', () {
    final rows = knowledge.fixture();
    rows.add(f.row(81, f.entity()));
    validate(rows);
    edit(rows, 9, {'receivedAt': const CanonicalNull()});
    invalid(rows, repair: 'receipt time');
    final missing = knowledge.fixture();
    invalid(missing, repair: 'recipients must be entities');
    final wrong = knowledge.fixture()..add(f.row(81, f.entity()));
    edit(wrong, 6, {'holder': f.ref(2).toCanonical()});
    invalid(wrong, repair: 'holder and a proposition');
  });
  test('appearance requires content typed media and exact known-calendar intervals', () {
    final rows = fixture();
    AppearanceRecord appearance({
      String description = 'Green leaves',
      Validity? validity,
    }) => AppearanceRecord(
      target: EntryAppearance(f.ref(4)),
      label: 'Tree',
      physicalDescription: description,
      atmosphere: '',
      images: [],
      links: [],
      validity: validity ?? const UnspecifiedValidity(),
    );
    rows.add(f.row(80, appearance()));
    validate(rows);
    objects.put(rows, 80, appearance(description: ''));
    invalid(rows, repair: 'appearance needs content');
    objects.put(rows, 80, appearance(validity: objects.interval(10, 20)));
    invalid(rows, repair: 'known calendar');
    rows.add(
      f.row(
        10,
        CalendarRecord(
          namespace: 'test',
          key: 'days',
          labels: {},
          unitStructure: {},
        ),
      ),
    );
    validate(rows);
    objects.put(rows, 80, appearance(validity: objects.interval(10, 10)));
    invalid(rows, repair: 'exact increasing');
    objects.put(rows, 80, appearance(validity: const UnknownValidity()));
    invalid(rows, repair: 'unspecified or exact');
  });
}
