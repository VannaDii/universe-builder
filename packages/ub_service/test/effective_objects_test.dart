import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/effective_objects.dart';

import 'operation_compilation_test.dart' as f;
import 'resource_checks_test.dart' as stock;
import 'knowledge_checks_test.dart' as knowledge;
import 'communication_checks_test.dart' as channels;
import 'cardinality_checks_test.dart' as cardinality;

final cal = CalendarId.parse('cal_${f.suffix(10)}');
Scope scope({Applicability? applies, int? realm, int context = 99}) => Scope(
  context: f.ref(context),
  realm: realm == null ? null : f.ref(realm),
  applicability: applies ?? const UniverseApplicability(),
);
Frame frame({String tick = '15', Perspective? perspective}) => Frame(
  universe: f.u,
  continuity: ContinuityId.parse('cont_${f.suffix(1)}'),
  revision: f.revision,
  context: f.ref(99),
  time: AtFrameTime(ExactTime(cal, tick)),
  perspective: perspective ?? const AuthorPerspective(),
);
Validity interval(int a, int b) =>
    CalendarIntervalValidity(cal, ExactBound('$a'), ExactBound('$b'));
PropositionRecord proposition(int subject, {bool value = true}) =>
    PropositionRecord(
      subject: f.ref(subject),
      predicate: f.ref(5),
      context: f.ref(99),
      value: BooleanValue(value),
      quantification: Quantification.particular,
    );
AssertionRecord assertion(
  int prop, {
  AttributeMode mode = AttributeMode.instance,
  bool refute = false,
}) => AssertionRecord(
  attributeMode: mode,
  proposition: f.ref(prop),
  polarity: refute ? Polarity.refutation : Polarity.support,
  scope: scope(),
  validity: interval(10, 20),
  persistence: PersistenceSemantics.explicitInterval,
  precision: Precision.exact,
  basis: const AuthorDecisionBasis('Authored capability'),
);
List<RecordVersion> fixture() => [
  f.row(1, f.type(1)),
  f.row(2, f.type(2, parent: 1)),
  f.row(3, f.type(3)),
  f.row(4, f.entity(classification: f.id(2))),
  f.row(
    5,
    PropertyRecord(
      namespace: 'test',
      key: 'grows',
      labels: {},
      subjectTypes: [f.id(1)],
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  f.row(6, proposition(1)),
  f.row(7, assertion(6, mode: AttributeMode.shared)),
];
RecordVersion get(List<RecordVersion> rows, int n) =>
    rows.firstWhere((r) => r.identity.recordId == f.id(n));
void put(List<RecordVersion> rows, int n, RecordPayload p) =>
    rows[rows.indexOf(get(rows, n))] = f.row(n, p);
void edit(List<RecordVersion> rows, int n, Map<String, CanonicalValue> edits) =>
    put(rows, n, f.patch(get(rows, n).payload, edits));
EffectiveObject object(
  List<RecordVersion> rows, {
  int owner = 4,
  List<int> predicates = const [],
  Frame? base,
  WorldId? world,
  bool restricted = false,
}) => assembleEffectiveObjects(
  records: rows,
  ids: [f.id(owner)],
  predicates: predicates.map(f.id).toList(),
  frame: base ?? frame(),
  world: world,
  restricted: restricted,
).single;
List<RecordVersion> withInstance() => [
  ...fixture(),
  f.row(8, proposition(4, value: false)),
  f.row(9, assertion(8)),
];
WorldId world(int n) => WorldId.parse('wld_${f.suffix(n)}');

void main() {
  test('inherited attributes retain provenance and do not establish instance state', () {
    final o = object(fixture());
    expect(o.ancestry.map((r) => r.identity.recordId), [f.id(2), f.id(1)]);
    expect(o.ancestryComplete, isTrue);
    expect(o.sharedAttributes.single.record.recordVersionId, f.ver(7));
    expect(o.sharedAttributes.single.applicability, isTrue);
    expect(o.instanceFacts, isEmpty);
    expect(o.unknowns, contains('instance_state_not_established'));
    expect(o.coverage, Coverage.partial);
    expect(o.initializationReceipts, isEmpty);
    expect(o.initializationHistoryCoverage, Coverage.partial);
    expect(o.dependencies.map((r) => r.identity.recordId), [f.id(5), f.id(6)]);
  });

  test('visible unresolved endpoint survives with source and uncertain applicability', () {
    final rows = fixture();
    edit(rows, 1, {'parentResolution': CanonicalString('ambiguous')});
    edit(rows, 4, {
      'names': CanonicalArray([
        ContextualName(
          text: 'Cedar',
          validity: const UnknownValidity(),
        ).toWire(),
      ]),
    });
    final o = object(rows);
    expect(o.ancestry.map((r) => r.identity.recordId), [f.id(2), f.id(1)]);
    expect(o.ancestryComplete, isFalse);
    expect(o.sharedAttributes.single.applicability, isNull);
    expect(o.sharedAttributes.single.unknowns, contains('definition_ancestry'));
    expect(o.contextualNames.single.applicability, isNull);
    expect(o.coverage, Coverage.partial);
    final character = object(
      rows,
      base: frame(perspective: CharacterPerspective(f.id(4))),
      restricted: true,
    );
    expect(character.contextualNames, isEmpty);
    expect(
      character.identity.payload.toWire().toText(),
      o.identity.payload.toWire().toText(),
    );
    expect(character.coverage, Coverage.restricted);
  });

  test('cyclic missing and disabled ancestry terminates without invented definitions', () {
    for (final change in <Map<String, CanonicalValue>>[
      {'classificationExecutable': const CanonicalBool(false)},
      {
        'parentResolution': CanonicalString('resolved'),
        'parent': CanonicalString(f.id(2).value),
      },
      {
        'parentResolution': CanonicalString('resolved'),
        'parent': CanonicalString(f.id(80).value),
      },
    ]) {
      final rows = fixture();
      edit(rows, 1, change);
      final o = object(rows);
      expect(o.ancestryComplete, isFalse);
      expect(o.ancestry.length, 2);
      expect(o.unknowns, contains('classification_or_ancestry_unresolved'));
    }
  });

  test(
    'current and historical snapshots keep independent authored ancestry',
    () {
      final old = fixture(), current = fixture();
      edit(current, 2, {'parent': CanonicalString(f.id(3).value)});
      expect(object(old).sharedAttributes.length, 1);
      expect(object(current).sharedAttributes, isEmpty);
      expect(object(old).sharedAttributes.length, 1);
    },
  );

  test('only entities and types are assembled in requested order', () {
    final rows = fixture();
    final objects = assembleEffectiveObjects(
      records: rows,
      ids: [f.id(80), f.id(5), f.id(2), f.id(4)],
      frame: frame(),
      restricted: false,
    );
    expect(objects.map((o) => o.identity.identity.recordId), [
      f.id(2),
      f.id(4),
    ]);
    expect(objects.first.ancestry.map((r) => r.identity.recordId), [
      f.id(2),
      f.id(1),
    ]);
  });

  test(
    'conflicts retain both inherited and instance witnesses without precedence',
    () {
      final o = object(withInstance());
      expect(o.sharedAttributes.length, 1);
      expect(o.instanceFacts.length, 1);
      final c = o.conflicts.single;
      expect(c.assertions, [f.ver(7), f.ver(9)]);
      expect(c.predicate, f.id(5));
      expect(c.applicability, isTrue);
      expect(c.initialValues, isFalse);
      expect(o.coverage, Coverage.complete);
    },
  );

  test(
    'multiple values permit coexistence unless the property is exclusive',
    () {
      final rows = withInstance();
      edit(rows, 5, {'multiplicity': CanonicalString('multiple')});
      expect(object(rows).conflicts, isEmpty);
      edit(rows, 5, {'exclusive': const CanonicalBool(true)});
      expect(object(rows).conflicts.length, 1);
      edit(rows, 9, {'precision': CanonicalString('approximate')});
      final o = object(rows);
      expect(o.conflicts.single.applicability, isNull);
      expect(
        o.unknowns,
        containsAll([
          'conflict_applicability_unresolved',
          'assertion_value_or_precision_unresolved',
        ]),
      );
    },
  );

  test(
    'equal supporting and refuting evidence conflicts even for multiple values',
    () {
      final rows = withInstance();
      put(rows, 8, proposition(4));
      edit(rows, 9, {'polarity': Polarity.refutation.toWire()});
      edit(rows, 5, {'multiplicity': CanonicalString('multiple')});
      expect(object(rows).conflicts.single.applicability, isTrue);
    },
  );

  test(
    'initial candidates compare separately and never become continuing facts',
    () {
      final rows = withInstance();
      edit(rows, 7, {'attributeMode': CanonicalString('initial_value')});
      final initialOnly = object(rows);
      expect(initialOnly.initialValueCandidates.length, 1);
      expect(initialOnly.sharedAttributes, isEmpty);
      expect(initialOnly.conflicts, isEmpty);
      rows.addAll([
        f.row(10, proposition(2, value: false)),
        f.row(11, assertion(10, mode: AttributeMode.initialValue)),
      ]);
      final o = object(rows);
      expect(o.conflicts.single.initialValues, isTrue);
      expect(o.conflicts.single.assertions, [f.ver(7), f.ver(11)]);
      expect(o.instanceFacts.single.record.recordVersionId, f.ver(9));
    },
  );

  test(
    'time and context filter evidence while unknown time remains visible',
    () {
      final rows = withInstance();
      expect(object(rows, base: frame(tick: '20')).instanceFacts, isEmpty);
      expect(object(rows, base: frame(tick: '10')).instanceFacts.length, 1);
      edit(rows, 9, {'validity': const UnknownValidity().toWire()});
      expect(object(rows).instanceFacts.single.applicability, isNull);
      edit(rows, 9, {'scope': scope(context: 80).toWire()});
      expect(object(rows).instanceFacts, isEmpty);
    },
  );

  test(
    'world omission remains unresolved and explicit worlds filter facts',
    () {
      final rows = withInstance();
      edit(rows, 9, {
        'scope': scope(applies: WorldsApplicability([world(20)])).toWire(),
      });
      expect(object(rows).instanceFacts.single.applicability, isNull);
      expect(
        object(rows, world: world(20)).instanceFacts.single.applicability,
        isTrue,
      );
      expect(object(rows, world: world(21)).instanceFacts, isEmpty);
      edit(rows, 1, {
        'applicability': WorldsApplicability([world(21)])
            .encode(canonical: false),
      });
      expect(object(rows, world: world(20)).sharedAttributes, isEmpty);
    },
  );

  test(
    'realm evidence retains uncertainty and distinct realms do not conflict',
    () {
      final rows = withInstance();
      edit(rows, 7, {'scope': scope(realm: 80).toWire()});
      edit(rows, 9, {'scope': scope(realm: 81).toWire()});
      final o = object(rows);
      expect(o.conflicts, isEmpty);
      expect(o.instanceFacts.single.applicability, isNull);
      expect(o.instanceFacts.single.unknowns, contains('realm_applicability'));
      edit(rows, 9, {'scope': scope(realm: 80).toWire()});
      expect(object(rows).conflicts.single.applicability, isNull);
    },
  );

  test('predicate filters show missing state without promoting an initial candidate', () {
    final rows = fixture();
    edit(rows, 7, {'attributeMode': CanonicalString('initial_value')});
    final o = object(rows, predicates: [5, 80]);
    expect(
      o.unknowns,
      containsAll([
        'predicate_not_established:${f.id(5).value}',
        'predicate_not_established:${f.id(80).value}',
      ]),
    );
    expect(object(withInstance(), predicates: [80]).instanceFacts, isEmpty);
  });

  test('behavioral requirements establish relevance but never capability', () {
    final rows = fixture();
    rows.add(
      f.row(
        80,
        ActionDefinitionRecord(
          namespace: 'test',
          key: 'grow',
          labels: {},
          requirements: [
            AttributeRequirement('actor', f.ref(5), const BooleanValue(true)),
          ],
          scope: scope(),
          validity: interval(10, 20),
        ),
      ),
    );
    final o = object(rows);
    expect(o.behavioralRequirements.single.applicability, isTrue);
    expect(o.instanceFacts, isEmpty);
    expect(o.dependencies.map((r) => r.identity.recordId), contains(f.id(5)));
    edit(rows, 5, {
      'subjectTypes': CanonicalArray([CanonicalString(f.id(3).value)]),
    });
    expect(object(rows).behavioralRequirements, isEmpty);
  });

  test('typed policies retain context and contract scope with wrapper time semantics', () {
    final rows = fixture();
    rows.add(f.row(80, knowledge.policy()));
    rows.add(f.row(81, channels.policy()));
    rows.add(
      f.row(82, cardinality.rule(cell: scope(), validity: interval(10, 20))),
    );
    final o = object(rows);
    expect(o.rules.map((r) => r.record.identity.recordId), [
      f.id(80),
      f.id(81),
      f.id(82),
    ]);
    expect(o.rules.every((r) => r.applicability == true), isTrue);
    expect(
      object(
        rows,
        base: frame(tick: '20'),
      ).rules.map((r) => r.record.identity.recordId),
      [f.id(80), f.id(81)],
    );
    put(rows, 80, knowledge.policy(context: f.ref(98)));
    expect(object(rows).rules.map((r) => r.record.identity.recordId), [
      f.id(81),
      f.id(82),
    ]);
  });

  test('event entry and exit frames preserve pre-event state boundaries', () {
    final rows = withInstance();
    edit(rows, 9, {'validity': interval(15, 20).toWire()});
    rows.add(
      f.row(
        80,
        EventRecord(
          occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
          time: ExactTime(cal, '15'),
          participants: [],
          labels: {},
        ),
      ),
    );
    Frame eventFrame(EventTimeSide side) => Frame(
      universe: f.u,
      continuity: frame().continuity,
      revision: f.revision,
      context: f.ref(99),
      time: AtEventFrameTime(f.ref(80), side),
      perspective: const AuthorPerspective(),
    );
    expect(
      object(rows, base: eventFrame(EventTimeSide.before)).instanceFacts,
      isEmpty,
    );
    expect(
      object(
        rows,
        base: eventFrame(EventTimeSide.after),
      ).instanceFacts.single.applicability,
      isTrue,
    );
  });

  test('numeric equivalence preserves corroboration and opposing evidence', () {
    final rows = withInstance();
    edit(rows, 5, {
      'value': const SimpleValueShape(SimpleShapeKind.integer).toWire(),
    });
    edit(rows, 6, {'value': IntegerValue('1').toWire()});
    edit(rows, 8, {'value': DecimalValue('1.0').toWire()});
    expect(object(rows).conflicts, isEmpty);
    edit(rows, 9, {'polarity': Polarity.refutation.toWire()});
    expect(object(rows).conflicts.single.applicability, isTrue);
  });

  test(
    'knowledge boundary rules bind holder context and retained dependencies',
    () {
      final rows = fixture();
      final rule = f.patch(channels.policy(), {
        'channelChronology': const CanonicalNull(),
        'knowledgeBoundary': KnowledgeBoundary(
          holder: f.ref(4),
          proposition: f.ref(6),
          context: f.ref(99),
        ).toWire(),
        'validity': interval(10, 20).toWire(),
      });
      rows.add(f.row(80, rule));
      final o = object(rows);
      expect(o.rules.single.applicability, isTrue);
      expect(
        o.dependencies.map((r) => r.identity.recordId),
        containsAll([f.id(4), f.id(6)]),
      );
      expect(object(rows, owner: 2).rules, isEmpty);
      expect(object(rows, base: frame(tick: '20')).rules, isEmpty);
    },
  );

  test('restricted projections do not recover filtered evidence or certify completeness', () {
    final rows = withInstance()
      ..removeWhere((r) => [8, 9].map(f.id).contains(r.identity.recordId));
    final o = object(rows, restricted: true);
    expect(o.conflicts, isEmpty);
    expect(o.instanceFacts, isEmpty);
    expect(o.coverage, Coverage.restricted);
    expect(
      o.unknowns,
      contains('current_permissions_or_perspective_limit_evidence'),
    );
  });

  test('accepted resource arrival stays unexplained and exposes exact dependencies', () {
    final rows = stock.fixture();
    rows.add(f.row(40, f.type(40)));
    edit(rows, 3, {
      'classification': CanonicalString(f.id(40).value),
      'classificationResolution': CanonicalString('resolved'),
    });
    var o = object(rows, owner: 3, base: stock.frame);
    expect(o.unknowns, contains('resource_arrival_unexplained'));
    final gap = stock.assess(rows).single;
    rows.add(f.row(14, stock.accept(gap)));
    o = object(rows, owner: 3, base: stock.frame);
    expect(o.unknowns, contains('resource_arrival_unexplained'));
    expect(
      o.dependencies.map((r) => r.identity.recordId),
      containsAll([f.id(9), f.id(12), f.id(14)]),
    );
    expect(
      o.instanceFacts.last.unknowns,
      contains('resource_arrival_unexplained:${gap.fingerprint.value}'),
    );
  });

  test(
    'failed resource accounting remains visible as unresolved row evidence',
    () {
      final rows = stock.fixture();
      edit(rows, 13, {'precision': CanonicalString('unresolved')});
      final o = object(rows, owner: 3, base: stock.frame);
      expect(
        o.instanceFacts.every(
          (r) => r.unknowns.contains('resource_accounting_unresolved'),
        ),
        isTrue,
      );
      expect(o.unknowns, contains('assertion_value_or_precision_unresolved'));
    },
  );

  test(
    'comparison budget spans requested objects and leaves explicit unknowns',
    () {
      final rows = fixture();
      rows.add(f.row(8, proposition(4)));
      for (var i = 0; i < 1450; i++) {
        rows.add(f.row(100 + i, assertion(8)));
      }
      final objects = assembleEffectiveObjects(
        records: rows,
        ids: [f.id(4), f.id(4)],
        frame: frame(),
        restricted: false,
      );
      expect(
        objects.every(
          (o) => o.unknowns.contains('conflict_comparison_budget_exhausted'),
        ),
        isTrue,
      );
      expect(objects.every((o) => o.coverage == Coverage.partial), isTrue);
    },
  );
}
