import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_contexts_test.dart' as contexts;
import 'writing_units_test.dart' as units;
import 'writing_properties_test.dart' as properties;
import 'writing_relations_test.dart' as relations;
import 'writing_connected_test.dart' as connected;
import 'writing_initializations_test.dart' as initializations;
import 'action_checks_test.dart' as actions;

void main() {
  test('new action contracts feed sequential generated resource balances', () {
    final rows = connected
        .eventRows()
        .where((r) => r.payload is! ActionDefinitionRecord)
        .toList();
    final result = compileWritingChanges(
      frame: actions.frame,
      base: rows,
      visibleRows: rows,
      canonAt: (_, _) => rows,
      input: CheckChangesRequest(
        universe: const Selector('Test'),
        contextId: ContextId.generate(),
        actions: [
          WritingAction(
            name: 'Spend',
            introduce: true,
            scope: 'universe',
            requirements: [],
            effects: [
              WritingEffect(
                role: 'actor',
                property: 'charged',
                change: WritingDeltaChange(
                  amount: const CanonicalNumber('-2'),
                  minimum: const CanonicalNumber('0'),
                  maximum: const CanonicalNumber('10'),
                ),
                lifetime: WritingUntilChangedEffectLifetime(),
              ),
            ],
          ),
        ],
        events: [
          WritingEvent(
            action: 'Spend',
            participants: {'actor': 'Actor'},
            atTick: '11',
          ),
          WritingEvent(
            action: 'Spend',
            participants: {'actor': 'Actor'},
            atTick: '12',
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    expect(
      result.operations.whereType<DefinePropositionOperation>().map(
        (op) => op.record.value,
      ),
      [const IntegerValue('3'), const IntegerValue('1')],
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: result.operations,
    );
    expect(candidate.where((r) => r.payload is EventRecord), hasLength(2));
    expect(
      candidate.where(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).establishedBy != null,
      ),
      hasLength(2),
    );
    validateActionConsequences(
      records: candidate,
      base: rows,
      changed: candidate
          .where(
            (r) => !rows.any((b) => b.identity.recordId == r.identity.recordId),
          )
          .map((r) => r.identity.recordId)
          .toSet(),
      frame: actions.frame,
    );
  });

  test('world declarations distinguish normalized existing names and repeated new names', () {
    final rows = [
      f.row(80, WorldRecord(selector: 'Campaign', aliases: ['Shared Realm'])),
    ];
    final result = compileWritingWorlds(
      rows: rows,
      declarations: [
        WritingWorld(name: ' shared realm '),
        WritingWorld(name: 'Ashen', introduce: true),
        WritingWorld(name: ' ASHEN ', introduce: true),
        WritingWorld(name: 'Missing'),
      ],
    );
    expect(result.operations, hasLength(1));
    expect(
      (result.operations.single as CreateWorldOperation).record.selector,
      'Ashen',
    );
    expect(result.additions, ['New world: Ashen']);
    expect(result.unchanged, [
      'Existing world:  shared realm ',
      'World already introduced in this delta:  ASHEN ',
    ]);
    expect(result.clarifications, hasLength(1));
    final scoped = compileWritingWorlds(
      rows: rows,
      worldScope: {},
      declarations: [WritingWorld(name: 'Ashen', introduce: true)],
    );
    expect(scoped.operations, isEmpty);
    expect(scoped.clarifications, hasLength(1));
    final ambiguous = compileWritingWorlds(
      rows: [
        ...rows,
        f.row(81, WorldRecord(selector: 'Other', aliases: ['Campaign'])),
      ],
      declarations: [WritingWorld(name: 'Campaign', introduce: true)],
    );
    expect(ambiguous.operations, isEmpty);
    expect(ambiguous.clarifications, hasLength(1));
    expect(
      () => compileWritingWorlds(
        rows: rows,
        declarations: [WritingWorld(name: '\u3000', introduce: true)],
      ),
      throwsFormatException,
    );
  });

  test('world unit property definition object relation and action stages share only intended candidates', () {
    final rows = contexts.rows();
    final frame = facts.frame(
      time: AtFrameTime(ExactTime(facts.calendar, '10')),
    );
    final before = rows.map((r) => r.toWire().toText()).toList();
    final result = compileWritingChanges(
      frame: frame,
      base: rows,
      visibleRows: rows,
      canonAt: (_, _) => rows,
      input: CheckChangesRequest(
        universe: const Selector('Test'),
        contextId: ContextId.generate(),
        worlds: [WritingWorld(name: 'Campaign', introduce: true)],
        units: [units.declaration(introduce: true)],
        properties: [
          properties.declaration(
            'distance',
            type: PlainPropertyType.quantity,
            unit: 'm',
          ),
        ],
        definitions: [
          DefinitionChange(
            name: 'Traveller',
            introduce: true,
            scope: 'Campaign',
          ),
        ],
        changes: [
          ObjectChange(
            name: 'Iris',
            introduce: true,
            classification: 'Traveller',
            facts: [
              FactChange(
                property: 'distance',
                value: FactQuantityValue(
                  amount: const CanonicalNumber('9007199254740993'),
                  unit: 'm',
                ),
                scope: 'campaign',
                when: 'scene',
              ),
            ],
          ),
        ],
        relationDefinitions: [relations.definition()],
        relationships: [
          relations.relationship(
            participants: {
              'person': ['Iris'],
              'witness': ['Mara'],
            },
          ),
        ],
        actions: [
          WritingAction(
            name: 'Observe',
            introduce: true,
            requirements: [],
            effects: [],
            scope: 'Campaign',
          ),
        ],
        events: [
          WritingEvent(
            action: 'Observe',
            participants: {},
            atTick: '11',
            world: 'Campaign',
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    expect(result.unknowns, isEmpty);
    final kinds = result.operations.map((o) => o.kind).toList();
    expect(
      kinds.indexOf(DomainOperationKind.createWorld),
      lessThan(kinds.indexOf(DomainOperationKind.defineUnit)),
    );
    expect(
      kinds.indexOf(DomainOperationKind.defineProperty),
      lessThan(kinds.indexOf(DomainOperationKind.introduceDefinition)),
    );
    expect(
      kinds.indexOf(DomainOperationKind.introduceInstance),
      lessThan(kinds.indexOf(DomainOperationKind.defineAction)),
    );
    expect(kinds.last, DomainOperationKind.recordEvent);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: result.operations,
    );
    final worldRow = candidate.singleWhere((r) => r.payload is WorldRecord);
    final world = WorldId.parse(
      'wld_${worldRow.identity.recordId.value.substring(4)}',
    );
    final traveller = candidate.singleWhere(
      (r) => r.payload is EntityTypeRecord,
    );
    final iris = candidate.singleWhere(
      (r) =>
          r.payload is EntityRecord &&
          (r.payload as EntityRecord).names.any((n) => n.text == 'Iris'),
    );
    expect(
      (iris.payload as EntityRecord).classification,
      traveller.identity.recordId,
    );
    expect(
      (traveller.payload as EntityTypeRecord).applicability,
      WorldsApplicability([world]),
    );
    expect(candidate.where((r) => r.payload is EventRecord), hasLength(1));
    final quantity = candidate
        .where((r) => r.payload is PropositionRecord)
        .map((r) => r.payload as PropositionRecord)
        .singleWhere((p) => p.value is QuantityValue);
    expect(
      (quantity.value as QuantityValue).value,
      const IntegerValue('9007199254740993'),
    );
    expect(rows.map((r) => r.toWire().toText()), before);
  });

  test('messages and explicit knowledge can use earlier object facts and policy declarations', () {
    final rows = contexts.rows();
    final frame = facts.frame(
      time: AtFrameTime(ExactTime(facts.calendar, '10')),
    );
    final result = compileWritingChanges(
      frame: frame,
      base: rows,
      visibleRows: rows,
      canonAt: (_, _) => rows,
      input: CheckChangesRequest(
        universe: const Selector('Test'),
        contextId: ContextId.generate(),
        properties: [
          properties.declaration(
            'open',
            persistence: PlainPersistence.untilChanged,
          ),
        ],
        changes: [
          ObjectChange(
            name: 'Mara',
            facts: [
              FactChange(
                property: 'open',
                value: const FactBooleanValue(true),
                scope: 'universe',
                when: 'scene',
              ),
            ],
          ),
          ObjectChange(name: 'Lena', introduce: true),
        ],
        knowledgePolicies: [
          const WritingKnowledgeModePolicy(
            name: 'Knowledge',
            mode: KnowledgeMode.justified,
          ),
        ],
        messages: [connected.message()],
        attitudes: [connected.attitude()],
      ),
    );
    expect(result.clarifications, isEmpty);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: result.operations,
    );
    expect(
      candidate.where((r) => r.payload is CommunicationRecord),
      hasLength(1),
    );
    expect(
      candidate.where((r) => r.payload is EpistemicAttitudeRecord),
      hasLength(1),
    );
    expect(candidate.where((r) => r.payload is AssertionRecord), hasLength(1));
    final attitude =
        candidate
                .singleWhere((r) => r.payload is EpistemicAttitudeRecord)
                .payload
            as EpistemicAttitudeRecord;
    expect(attitude.acquisition!.basis, isA<CommunicationKnowledge>());
  });

  test('unpublished narrative dependencies remain pinned and clarification strings are sorted and unique', () {
    final rows = contexts.rows();
    final result = compileWritingChanges(
      frame: facts.frame(),
      base: rows,
      visibleRows: rows,
      canonAt: (_, _) => throw StateError('No edition canon should be read'),
      input: CheckChangesRequest(
        universe: const Selector('Test'),
        contextId: ContextId.generate(),
        storyContexts: [
          contexts.declaration(
            kind: StoryContextKind.narrator,
            name: 'Narration',
            narrator: 'Mara',
          ),
        ],
        narrativeWorks: [
          WritingNarrativeWork(
            name: 'Book',
            introduce: true,
            kind: WorkKind.novel,
          ),
        ],
        workEditions: [
          WritingWorkEdition(
            work: 'Book',
            name: 'First',
            introduce: true,
            binding: WritingEditionBinding.current,
          ),
        ],
        aliases: [WritingAlias(object: 'Iris', text: 'Star')],
        changes: [ObjectChange(name: 'Iris', introduce: true)],
        questions: ['\u{10000}', '\ue000', '\u{10000}'],
      ),
    );
    expect(
      result.operations.whereType<RecordNarrativeReferenceOperation>().where(
        (o) => o.record == RecordKind.workVersion,
      ),
      isEmpty,
    );
    expect(result.operations.whereType<AddNameOperation>(), isEmpty);
    expect(
      result.clarifications,
      contains("Select one accessible existing work named 'Book'."),
    );
    expect(result.clarifications.last, '\u{10000}');
    expect(result.clarifications[result.clarifications.length - 2], '\ue000');
    expect(
      result.clarifications.toSet(),
      hasLength(result.clarifications.length),
    );
    expect(
      result.operations.whereType<IntroduceInstanceOperation>(),
      hasLength(1),
    );
  });

  test('instance initialization uses pinned source versions and compiles only once in the aggregate', () {
    final rows = initializations.rows();
    final result = compileWritingChanges(
      frame: initializations.frame,
      base: rows,
      visibleRows: rows,
      canonAt: (_, _) => rows,
      input: initializations.delta([initializations.request()]),
    );
    expect(result.clarifications, isEmpty);
    expect(result.operations, hasLength(1));
    expect(result.operations.single, isA<InitializeInstanceOperation>());
    final candidate = compileWritingCandidate(
      universe: initializations.frame.universe,
      revision: initializations.frame.revision,
      base: rows,
      operations: result.operations,
    );
    expect(candidate.where((r) => r.payload is AssertionRecord), hasLength(2));
  });
}
