import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/src/universe_evidence_policy.dart';
import 'package:ub_service/definition_registry.dart';
import 'package:ub_service/effective_objects.dart';
import 'package:ub_service/ub_service.dart' show buildContextBrief;
import 'package:ub_store/ub_store.dart' show Assignment, StoredVersion;

import 'candidate_validation_test.dart' as candidate;
import 'rule_checks_test.dart' as f;
import 'required_evidence_sources_test.dart' as evidence;
import 'knowledge_boundaries_test.dart' as knowledge;
import 'knowledge_checks_test.dart' as acquisition;
import 'communication_checks_test.dart' as channels;
import 'cardinality_checks_test.dart' as cardinality;
import 'resource_checks_test.dart' as resources;
import 'structural_checks_test.dart' as structural;
import 'operation_compilation_test.dart' as operations;

RecordVersion replace(RecordVersion original, RecordPayload payload) =>
    RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: original.identity,
      payload: payload,
    );

RecordVersion availablePolicy(
  UniverseId universe,
  String name,
  List<RecordId> members,
) => RecordVersion.build(
  recordVersionId: RecordVersionId.generate(),
  identity: RecordIdentity(
    universeId: universe,
    recordId: RecordId.generate(),
    recordKind: RecordKind.domainPack,
  ),
  payload: DomainPackRecord(
    key: '$universePolicyDefinitionPrefix$name',
    version: '1',
    dependencies: {},
    capabilities: [],
    records: members,
  ),
);

RecordVersion selectPolicy(RecordVersion selection, RecordVersion definition) {
  final pack = definition.payload as DomainPackRecord;
  return replace(
    selection,
    DomainPackRecord(
      key: universePolicySelectionKey,
      version: '2',
      dependencies: {pack.key: pack.version},
      capabilities: [],
      records: [definition.identity.recordId],
    ),
  );
}

void main() {
  final universe = candidate.fixture().first.identity.universeId;
  test('first Real World adoption uses explicit sources without rewriting historical claims', () {
    final legacy = evidence.fixture();
    List<Assignment> define(List<RecordId> members) => operations.compile(legacy, [
      DefineUniversePolicyOperation(clientRef: RecordId.generate().value,
        key: 'Memoir root', realWorld: true, activate: true,
        sourceCategoryMembers: members),
    ]);
    final empty = define([]);
    expect(candidate.check([...legacy, ...empty.map(operations.decode)],
      base: legacy, changes: empty, requireRootPolicy: true).admissible, isFalse);
    final chosen = define([f.id(12)]);
    final adopted = [...legacy, ...chosen.map(operations.decode)];
    final policy = UniversePolicySelection.fromRecords(universe, adopted);
    final requirement = (policy.rules.single.payload as RuleRecord).requiredEvidence!;
    expect(requirement.reviewMethods, isEmpty);
    final pin = requirement.sourceCategories.single;
    final category = adopted.singleWhere((r) => r.recordVersionId == pin.version);
    expect((category.payload as DomainPackRecord).records, [f.id(12)]);
    expect(candidate.check(adopted, base: legacy, changes: chosen,
      requireRootPolicy: true).admissible, isTrue);
    expect(adopted.take(legacy.length).map((r) => r.toWire().toText()),
      legacy.map((r) => r.toWire().toText()));
  });
  test('policy source selection rejects missing, non-source, duplicate and scratch members', () {
    final legacy = evidence.fixture();
    for (final members in [[f.id(1)], [RecordId.generate()], [f.id(12), f.id(12)]]) {
      expect(() => operations.compile(legacy, [DefineUniversePolicyOperation(
        clientRef: RecordId.generate().value, key: 'Real World',
        realWorld: true, activate: true, sourceCategoryMembers: members)]),
        throwsA(isA<protocol.InvalidArgumentError>()));
    }
    expect(() => operations.compile(legacy, [DefineUniversePolicyOperation(
      clientRef: RecordId.generate().value, key: 'Scratch',
      realWorld: false, activate: true, sourceCategoryMembers: [f.id(12)])]),
      throwsA(isA<protocol.InvalidArgumentError>()));
  });
  test('legacy analysis stays readable but publication requires explicit root adoption', () {
    final legacy = candidate.fixture();
    expect(candidate.check(legacy).admissible, isTrue);
    expect(() => candidate.check(legacy, requireRootPolicy: true),
      throwsA(isA<protocol.InvalidArgumentError>()));
    final changes = operations.compile(legacy, [DefineUniversePolicyOperation(
      clientRef: RecordId.generate().value, key: 'Adopted policy',
      realWorld: false, activate: true)]);
    final adopted = [...legacy, ...changes.map(operations.decode)];
    expect(candidate.check(adopted, base: legacy, changes: changes,
      requireRootPolicy: true).admissible, isTrue);
    expect(adopted.take(legacy.length).map((r) => r.toWire().toText()),
      legacy.map((r) => r.toWire().toText()));
  });
  for (final realWorld in [false, true]) {
    test(
      'creation defines and selects ${realWorld ? 'Real World' : 'scratch'} root',
      () {
        final rows = initialUniversePolicyRecords(universe, realWorld);
        final selected = UniversePolicySelection.fromRecords(universe, rows);
        expect(selected.rules, hasLength(realWorld ? 1 : 0));
        final policy = selected.definition.payload as DomainPackRecord;
        final binding = selected.selection.payload as DomainPackRecord;
        expect(binding.records, [selected.definition.identity.recordId]);
        expect(binding.dependencies, {policy.key: policy.version});
        expect(rows.every((r) => r.verifiesDigest), isTrue);
        // Re-decoding canonical records preserves the exact selection and members.
        final restored = UniversePolicySelection.fromRecords(
          universe,
          rows.map((r) => RecordVersion.fromWire(r.toWire())),
        );
        expect(
          restored.selection.payloadDigest,
          selected.selection.payloadDigest,
        );
        expect(
          restored.definition.payloadDigest,
          selected.definition.payloadDigest,
        );
      },
    );
  }

  test('a declared root cannot be removed together with all definitions', () {
    final root = initialUniversePolicyRecords(universe, false);
    final base = [...candidate.fixture(), ...root];
    expect(candidate.check(base).admissible, isTrue);
    expect(
      () => candidate.check(candidate.fixture(), base: base),
      throwsA(isA<protocol.InvalidArgumentError>()),
    );
  });

  for (final realWorld in [false, true]) {
    test('defines a fresh ${realWorld ? 'Real World clone' : 'scratch policy'} through operations', () {
      final initial = initialUniversePolicyRecords(universe, false);
      final base = [...candidate.fixture(), ...initial];
      final root = UniversePolicySelection.fromRecords(universe, base);
      final id = RecordId.generate();
      final changes = operations.compile(base, [
        DefineUniversePolicyOperation(
          clientRef: id.value,
          key: 'replacement',
          realWorld: realWorld,
          activate: true,
          expectedRootVersion: root.selection.recordVersionId,
        ),
      ]);
      final replaced = changes.map((c) => c.recordId).toSet();
      final after = [
        for (final row in base)
          if (!replaced.contains(row.identity.recordId)) row,
        ...changes.map(operations.decode),
      ];
      final selected = UniversePolicySelection.fromRecords(universe, after);
      expect(selected.definition.identity.recordId, id);
      expect(selected.rules, hasLength(realWorld ? 1 : 0));
      expect(after, contains(root.definition));
      // The fixture already contains unsourced claims: activating Real World
      // correctly requires evidence before this root switch can be published.
      expect(candidate.check(after, base: base, changes: changes).admissible,
          !realWorld);
      if (realWorld) {
        final source = (selected.rules.single.payload as RuleRecord)
            .requiredEvidence!.sourceCategories.single;
        final category = after.singleWhere((r) => r.identity.recordId == source.record);
        expect(source.version, category.recordVersionId);
        expect(source.universe, universe);
      }
    });
  }

  test('available Real World clones have independent rules and categories', () {
    final base = [
      ...candidate.fixture(),
      ...initialUniversePolicyRecords(universe, true),
    ];
    final original = UniversePolicySelection.fromRecords(universe, base);
    final changes = operations.compile(base, [
      DefineUniversePolicyOperation(
        clientRef: RecordId.generate().value,
        key: 'available',
        realWorld: true,
        activate: false,
      ),
    ]);
    final after = [...base, ...changes.map(operations.decode)];
    final selected = UniversePolicySelection.fromRecords(universe, after);
    expect(selected.definition, original.definition);
    expect(selected.inactiveRuleIds, hasLength(1));
    expect(candidate.check(after, base: base, changes: changes).admissible, isTrue);
    final refs = after.where((row) => row.payload is RuleRecord)
        .map((row) => (row.payload as RuleRecord)
            .requiredEvidence!.sourceCategories.single.record).toSet();
    expect(refs, hasLength(2));
  });

  test('root definition rejects stale selection, duplicate names and rootless availability', () {
    final legacy = candidate.fixture();
    final base = [...legacy, ...initialUniversePolicyRecords(universe, false)];
    DefineUniversePolicyOperation define(String key, {bool activate = true}) =>
        DefineUniversePolicyOperation(
          clientRef: RecordId.generate().value,
          key: key,
          realWorld: false,
          activate: activate,
        );
    expect(() => operations.compile(base, [define('replacement')]),
        throwsA(isA<protocol.InvalidArgumentError>()));
    expect(() => operations.compile(base, [define('custom', activate: false)]),
        throwsA(isA<protocol.InvalidArgumentError>()));
    expect(() => operations.compile(legacy, [define('first', activate: false)]),
        throwsA(isA<protocol.InvalidArgumentError>()));
    final adopted = operations.compile(legacy, [define('first')]);
    expect(UniversePolicySelection.fromRecords(universe,
        [...legacy, ...adopted.map(operations.decode)]).rules, isEmpty);
  });

  test('another defined root can be selected without deleting the former definition', () {
    final initial = initialUniversePolicyRecords(universe, false);
    final old = UniversePolicySelection.fromRecords(universe, initial);
    final alternative = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.domainPack,
      ),
      payload: DomainPackRecord(
        key: '${universePolicyDefinitionPrefix}alternative',
        version: '1',
        dependencies: {},
        capabilities: [],
        records: [],
      ),
    );
    final definition = alternative.payload as DomainPackRecord;
    final selected = replace(
      old.selection,
      DomainPackRecord(
        key: universePolicySelectionKey,
        version: '2',
        dependencies: {definition.key: definition.version},
        capabilities: [],
        records: [alternative.identity.recordId],
      ),
    );
    final rows = [
      ...candidate.fixture(),
      old.definition,
      alternative,
      selected,
    ];
    expect(
      candidate
          .check(rows, base: [...candidate.fixture(), ...initial])
          .admissible,
      isTrue,
    );
    expect(
      UniversePolicySelection.fromRecords(universe, rows).definition,
      alternative,
    );
    expect(rows, contains(old.definition));
    expect(
      () => candidate.check(
        rows.where((r) => r != alternative).toList(),
        base: rows,
      ),
      throwsA(isA<DefinitionAdmissionError>()),
    );
  });

  test(
    'only the selected root executes; independent rules remain in force',
    () {
      final initial = initialUniversePolicyRecords(universe, false);
      final empty = UniversePolicySelection.fromRecords(universe, initial);
      final blocked = f.record(701, candidate.rule());
      final alternate = availablePolicy(universe, 'alternate', [
        blocked.identity.recordId,
      ]);
      final rows = [...candidate.fixture(), ...initial, blocked, alternate];
      expect(candidate.check(rows).admissible, isTrue);
      final selected = selectPolicy(empty.selection, alternate);
      final activated = [
        for (final r in rows) r == empty.selection ? selected : r,
      ];
      expect(candidate.check(activated, base: rows).admissible, isFalse);
      expect(candidate.check(rows, base: activated).admissible, isTrue);
      expect(
        (blocked.payload as RuleRecord).applicability,
        isA<UniverseApplicability>(),
      );
      final independent = f.record(702, candidate.rule());
      final withIndependent = [...rows, independent];
      expect(candidate.check(withIndependent).admissible, isFalse);
      final inactive = UniversePolicySelection.fromRecords(
        universe,
        withIndependent,
      ).inactiveRuleIds;
      expect(inactive, {blocked.identity.recordId});
      final objects = assembleEffectiveObjects(
        records: withIndependent,
        ids: [f.id(1)],
        frame: f.frame(),
        restricted: false,
        excludedRules: inactive,
      );
      expect(
        objects.single.rules.map((r) => r.record.identity.recordId),
        contains(independent.identity.recordId),
      );
      expect(
        objects.single.rules.map((r) => r.record.identity.recordId),
        isNot(contains(blocked.identity.recordId)),
      );
      final brief = buildContextBrief(
        all: withIndependent,
        accessible: withIndependent,
        visibility: withIndependent.map((r) => r.identity.recordId).toSet(),
        focusIds: [f.id(1)],
        frame: f.frame(),
        world: null,
        restricted: false,
        byteBudget: 100000,
        offset: 0,
      );
      final ids = brief.brief.records.map((r) => r.identity.recordId).toSet();
      expect(
        ids,
        containsAll([
          empty.selection.identity.recordId,
          empty.definition.identity.recordId,
          independent.identity.recordId,
        ]),
      );
      expect(ids, isNot(contains(blocked.identity.recordId)));
      expect(withIndependent, contains(blocked)); // Canon is not filtered away.
    },
  );

  test('removing policy membership cannot implicitly activate its rule', () {
    final initial = initialUniversePolicyRecords(universe, false);
    final rule = f.record(701, candidate.rule());
    final definition = availablePolicy(universe, 'alternate', [
      rule.identity.recordId,
    ]);
    final base = [...candidate.fixture(), ...initial, rule, definition];
    final empty = replace(
      definition,
      DomainPackRecord(
        key: (definition.payload as DomainPackRecord).key,
        version: '2',
        dependencies: {},
        capabilities: [],
        records: [],
      ),
    );
    for (final after in [
      base.where((row) => row != definition).toList(),
      [for (final row in base) row == definition ? empty : row],
    ]) {
      expect(
        () => candidate.check(after, base: base),
        throwsA(isA<protocol.InvalidArgumentError>()),
      );
    }
    expect(
      candidate.check(
        base.where((row) => row != rule && row != definition).toList(),
        base: base,
      ).admissible,
      isTrue,
    );
    final replacement = availablePolicy(universe, 'replacement', [
      rule.identity.recordId,
    ]);
    expect(
      candidate.check([
        for (final row in base) if (row != definition) row,
        replacement,
      ], base: base).admissible,
      isTrue,
    );
  });

  test('root activation reopens source duties even when no claim changed', () {
    final initial = initialUniversePolicyRecords(universe, false);
    final root = UniversePolicySelection.fromRecords(universe, initial);
    final available = availablePolicy(universe, 'sourced', [f.id(10)]);
    final facts = evidence.fixture();
    evidence.replace(
      facts,
      4,
      evidence.assertion(
        basis: const AuthorDecisionBasis('No supporting source'),
      ),
    );
    final before = [...facts, ...initial, available];
    expect(candidate.check(before).admissible, isTrue);
    final selected = selectPolicy(root.selection, available);
    final after = [
      for (final row in before) row == root.selection ? selected : row,
    ];
    final result = candidate.check(
      after,
      base: before,
      changes: [
        Assignment(
          recordId: selected.identity.recordId,
          expected: root.selection.recordVersionId,
          next: StoredVersion(
            versionId: selected.recordVersionId,
            identity: selected.identity,
            payload: selected.payload.toWire(),
            digest: selected.payloadDigest,
          ),
        ),
      ],
    );
    expect(result.admissible, isFalse);
    expect(
      result.validation.findings.any(
        (finding) =>
            finding.ruleId == f.id(10) &&
            finding.outcome == protocol.EvidenceOutcome.notEstablished,
      ),
      isTrue,
    );
  });

  final knowledgeRows = knowledge.fixture();
  knowledge.edit(knowledgeRows, 1, {'value': IntegerValue('1').toWire()});
  final lanes = <({String name, List<RecordVersion> rows, Frame frame})>[
    (name: 'knowledge boundary', rows: knowledgeRows, frame: f.frame()),
    (
      name: 'resource accounting',
      rows: [...resources.fixture(), structural.context(5)],
      frame: resources.frame,
    ),
    (
      name: 'channel chronology',
      rows: [
        ...candidate.fixture(),
        f.record(10, operations.entity()),
        f.record(8, channels.policy()),
        f.record(
          9,
          CommunicationRecord(
            sender: f.ref(1),
            intendedRecipients: [f.ref(10)],
            actualRecipients: [],
            content: [f.ref(3)],
            channel: 'speech',
            sentAt: ExactTime(channels.cal, '10'),
            distorted: false,
          ),
        ),
      ],
      frame: f.frame(),
    ),
    (
      name: 'relation cardinality',
      rows: [
        ...cardinality.base(),
        for (final n in [10, 11, 12]) f.record(n, operations.entity()),
        ...cardinality.fact(20, 11, cardinality.interval(0, 10)),
        ...cardinality.fact(30, 12, cardinality.interval(5, 15)),
      ],
      frame: f.frame(),
    ),
    (
      name: 'knowledge acquisition',
      rows: [
        ...candidate.fixture(),
        f.record(
          8,
          EpistemicAttitudeRecord(
            holder: f.ref(1),
            proposition: f.ref(3),
            attitude: EpistemicAttitudeKind.knows,
            validity: const UnspecifiedValidity(),
            basis: const AuthorDecisionBasis('Explicit statement'),
          ),
        ),
        f.record(9, acquisition.policy(mode: KnowledgeMode.authorEstablished)),
      ],
      frame: f.frame(),
    ),
  ];
  for (final lane in lanes) {
    test('${lane.name} obeys root selection without changing its facts', () {
      final ids = lane.rows
          .where((r) => r.payload is RuleRecord)
          .map((r) => r.identity.recordId)
          .toSet();
      final baseline = candidate.check(lane.rows, frame: lane.frame);
      expect(
        baseline.validation.findings.any((f) => ids.contains(f.ruleId)),
        isTrue,
      );
      final initial = initialUniversePolicyRecords(universe, false);
      final root = UniversePolicySelection.fromRecords(universe, initial);
      final definition = availablePolicy(universe, 'lane', ids.toList());
      final before = [...lane.rows, ...initial, definition];
      final inactive = candidate.check(before, frame: lane.frame);
      expect(
        inactive.validation.findings.any((f) => ids.contains(f.ruleId)),
        isFalse,
      );
      final selected = selectPolicy(root.selection, definition);
      final after = [
        for (final row in before) row == root.selection ? selected : row,
      ];
      final active = candidate.check(after, base: before, frame: lane.frame);
      expect(
        active.validation.findings.any((f) => ids.contains(f.ruleId)),
        isTrue,
      );
      for (final row in lane.rows) {
        expect(after, contains(row));
      }
    });
  }

  test(
    'selection refuses missing, duplicate, foreign and mismatched definitions',
    () {
      final initial = initialUniversePolicyRecords(universe, false);
      final selected = UniversePolicySelection.fromRecords(universe, initial);
      final definition = selected.definition.payload as DomainPackRecord;
      expect(
        () => UniversePolicySelection.fromRecords(universe, []),
        throwsFormatException,
      );
      expect(
        () =>
            UniversePolicySelection.fromRecords(universe, [selected.selection]),
        throwsFormatException,
      );
      expect(
        () => UniversePolicySelection.fromRecords(universe, [
          ...initial,
          selected.selection,
        ]),
        throwsFormatException,
      );
      expect(
        () =>
            UniversePolicySelection.fromRecords(UniverseId.generate(), initial),
        throwsFormatException,
      );
      final wrongVersion = replace(
        selected.selection,
        DomainPackRecord(
          key: universePolicySelectionKey,
          version: '2',
          dependencies: {definition.key: 'not-the-defined-version'},
          capabilities: [],
          records: [selected.definition.identity.recordId],
        ),
      );
      expect(
        () => UniversePolicySelection.fromRecords(universe, [
          selected.definition,
          wrongVersion,
        ]),
        throwsFormatException,
      );
    },
  );
}
