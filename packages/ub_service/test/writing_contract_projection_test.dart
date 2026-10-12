import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'action_checks_test.dart' as a;
import 'consequence_execution_test.dart' as effects;
import 'knowledge_checks_test.dart' as knowledge;
import 'rule_checks_test.dart' as facts;
import 'cardinality_checks_test.dart' as cardinality;
import 'writing_projection_test.dart' as w;

ReadContractsRequest request({List<String> actions = const []}) =>
    ReadContractsRequest(
      universe: const Selector('World'),
      contextId: ContextId.generate(),
      actionNames: actions,
    );

void main() {
  test('plain relationships powers and completeness remain declarations with explicit scope', () {
    PropertyRecord property(String key, ValueShape shape) => PropertyRecord(
      namespace: 'test',
      key: key,
      labels: {},
      subjectTypes: [],
      value: shape,
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.unspecified,
      exclusive: false,
      symmetric: false,
      transitive: false,
    );
    final rows = [
      ...cardinality.base(),
      f.row(10, f.entity()),
      f.row(11, f.entity()),
      ...cardinality.fact(20, 11, const UnspecifiedValidity()),
      f.row(31, property('holder', EntityRefShape([]))),
      f.row(
        32,
        property('able', const SimpleValueShape(SimpleShapeKind.boolean)),
      ),
      f.row(
        37,
        property('stock', const SimpleValueShape(SimpleShapeKind.integer)),
      ),
      f.row(
        33,
        ItemPowerRecord(
          item: f.ref(10),
          holderPredicate: f.ref(31),
          powerPredicate: f.ref(32),
          value: const BooleanValue(true),
          scope: cardinality.scope(),
          validity: const UnspecifiedValidity(),
        ),
      ),
      f.row(
        34,
        CompletenessRecord(
          subject: f.ref(10),
          predicate: 'test:holder',
          members: [f.ref(11)],
          completeness: const ObjectiveCompleteness(),
          validity: const UnspecifiedValidity(),
          scope: cardinality.scope(),
        ),
      ),
      f.row(
        35,
        UnitRecord(
          namespace: 'test',
          key: 'metre',
          dimension: 'length',
          symbol: 'm',
          labels: {},
          validity: const UnspecifiedValidity(),
        ),
      ),
      f.row(
        36,
        RuleRecord(
          namespace: 'test',
          key: 'stock-accounting',
          labels: {},
          kind: RuleKind.physicalConstraint,
          commitPolicy: CommitPolicy.blockUnlessException,
          applicability: const UniverseApplicability(),
          targetPredicates: ['test:stock'],
          expression: const LiteralExpr(true),
          capabilities: ['resources.accounting.v1'],
          executable: true,
          validity: const UnspecifiedValidity(),
        ),
      ),
    ];
    final base = a.frame;
    final frame = Frame(
      universe: f.u,
      continuity: base.continuity,
      revision: base.revision,
      context: f.ref(3),
      time: AtFrameTime(ExactTime(cardinality.cal, '15')),
      perspective: const AuthorPerspective(),
    );
    final result = projectWritingContracts(
      request: request(),
      rows: rows,
      frame: frame,
      restricted: false,
    );
    expect(w.list(result, 'relations').length, 1);
    expect(w.list(result, 'relationships').length, 1);
    expect(
      w.field(w.list(result, 'relationships').single, 'time_applicable'),
      isA<CanonicalNull>(),
    );
    expect(
      wireString(w.field(w.list(result, 'relation_limits').single, 'policy')),
      'always_block',
    );
    expect(
      wireString(w.field(w.list(result, 'item_powers').single, 'limitation')),
      contains('Declaration only'),
    );
    expect(
      wireString(w.field(w.list(result, 'exhaustive_sets').single, 'kind')),
      'objective',
    );
    expect(
      w.field(w.list(result, 'units').single, 'conversion_declared').toText(),
      'false',
    );
    expect(
      wireString(w.field(w.list(result, 'constraints').single, 'kind')),
      'resource_accounting',
    );
  });

  test('plain action preserves exact delta conditions and lifetimes as declarations', () {
    final action = effects.action(
      effects.delta('9007199254740993', maximum: '9007199254740993'),
      presence: EffectPresence.optional,
      condition: AttributeEqualsEffect(
        'actor',
        f.ref(2),
        const BooleanValue(true),
      ),
    );
    final rows = effects.fixture()
      ..removeWhere((r) => r.identity.recordId == f.id(5));
    rows.add(f.row(5, action));
    final result = projectWritingContracts(
      request: request(),
      rows: rows,
      frame: a.frame,
      restricted: false,
    );
    final projected = w.list(result, 'actions').single;
    final slot = w.list(projected, 'effects').single;
    expect(
      w.field(w.field(slot, 'change'), 'amount').toText(),
      '9007199254740993',
    );
    expect(w.field(slot, 'optional').toText(), 'true');
    expect(w.field(w.field(slot, 'condition'), 'value').toText(), 'true');
    expect(
      wireString(w.field(w.field(slot, 'lifetime'), 'kind')),
      'until_changed',
    );
    final set = plainWritingAction(
      effects.action(
        const SetEffect(Polarity.refutation, BooleanValue(false)),
        lifetime: TicksEffect(ConsequenceInteger('2')),
      ),
      (_) => 'charged',
    );
    final setSlot = w.list(set, 'effects').single;
    expect(w.field(w.field(setSlot, 'lifetime'), 'count').toText(), '2');
    expect(w.field(w.field(setSlot, 'change'), 'negated').toText(), 'true');
    expect(w.field(projected, 'contract_declared').toText(), 'true');
    expect(
      w.list(
        projectWritingContracts(
          request: request(actions: ['Other']),
          rows: rows,
          frame: a.frame,
          restricted: false,
        ),
        'actions',
      ),
      isEmpty,
    );
  });
  test(
    'plain knowledge declarations retain receipt and eligibility distinctions',
    () {
      final rows = knowledge.fixture();
      final result = projectWritingContracts(
        request: request(),
        rows: rows,
        frame: facts.frame(),
        restricted: false,
      );
      expect(w.list(result, 'knowledge_policies').length, 1);
      expect(w.list(result, 'channels').length, 1);
      expect(w.list(result, 'communications').length, 1);
      final attitude = w.list(result, 'attitudes').single;
      expect(
        w.field(attitude, 'message_handle').toText(),
        CanonicalString(f.id(9).value).toText(),
      );
      expect(
        wireString(
          w.field(w.list(result, 'knowledge_policies').single, 'limitation'),
        ),
        contains('actual receipt'),
      );
      final frame = facts.frame();
      final restricted = projectWritingContracts(
        request: request(),
        rows: rows,
        frame: Frame(
          universe: frame.universe,
          continuity: frame.continuity,
          revision: frame.revision,
          context: frame.context,
          time: frame.time,
          perspective: CharacterPerspective(f.id(1)),
        ),
        restricted: true,
      );
      expect(
        w.field(w.list(restricted, 'attitudes').single, 'attitude_handle'),
        isA<CanonicalNull>(),
      );
      expect(
        w.field(
          w.list(restricted, 'communications').single,
          'message_edit_handle',
        ),
        isA<CanonicalNull>(),
      );
      expect(w.list(restricted, 'properties'), isEmpty);
      expect(wireString(w.field(restricted, 'coverage')), 'restricted');
    },
  );
  test(
    'plain narrative keeps depiction disclosure and reader ordering distinct',
    () {
      final rows = a.fixture();
      rows.addAll([
        f.row(
          55,
          WorkRecord(
            kind: WorkKind.novel,
            title: 'Novel',
            labels: {},
            sourceRefs: [],
            versions: [f.id(56)],
            worldAssociations: [],
          ),
        ),
        f.row(
          56,
          WorkVersionRecord(
            work: f.ref(55),
            versionLabel: 'First',
            binding: BoundWork(a.frame.continuity, f.revision),
          ),
        ),
        f.row(
          57,
          SceneRecord(
            workVersion: VersionRef(
              universe: f.u,
              record: f.id(56),
              version: f.ver(56),
            ),
            sceneId: 'Opening',
            narrativePosition: BigInt.parse('9007199254740993'),
            disclosedRecords: [f.ref(4)],
            depictedEvents: [f.ref(6)],
            worldAssociations: [],
          ),
        ),
      ]);
      final result = projectWritingContracts(
        request: request(),
        rows: rows,
        frame: a.frame,
        restricted: false,
      );
      final narrative = w.list(result, 'narrative');
      final scene = narrative.last;
      expect(w.field(scene, 'reader_order').toText(), '9007199254740993');
      expect(w.list(scene, 'depicted_events').length, 1);
      expect(w.list(scene, 'disclosures').length, 1);
      expect(
        w
            .field(
              w.field(w.list(scene, 'disclosures').single, 'declared_fact'),
              'value',
            )
            .toText(),
        'true',
      );
      expect(
        wireString(w.field(scene, 'limitation')),
        contains('never establish'),
      );
    },
  );
}
