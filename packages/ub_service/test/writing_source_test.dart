import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_service/src/operation_compilation.dart'
    show compileAllocatedOperations;

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as frames;
import 'writing_contexts_test.dart' as contexts;
import 'writing_units_test.dart' as units;
import 'writing_relations_test.dart' as relations;
import 'writing_narrative_test.dart' as narrative;
import 'writing_disclosures_test.dart' as disclosures;
import 'knowledge_checks_test.dart' as knowledge;
import 'proposal_state_test.dart' as proposals;

Matcher denied = throwsA(isA<PolicyDeniedError>());
Future<void> gate(
  List<DomainOperation> operations, {
  List<RecordVersion> rows = const [],
  bool contracts = false,
  bool authorOrigin = false,
  String? knowledgeRationale,
  List<RecordVersion> Function(ContinuityId, RevisionId)? canonAt,
}) => validateWritingSourcePreparation(
  operations: operations,
  originals: rows,
  contracts: contracts,
  authorOrigin: authorOrigin,
  knowledgeRationale: knowledgeRationale,
  canonAt: canonAt ?? (_, _) => rows,
);

void main() {
  test('source attachment changes only explicit evidence fields and preserves correction metadata', () async {
    final assertion = f.assertion(validity: f.interval);
    final belief = knowledge.attitude(
      kind: EpistemicAttitudeKind.believes,
      unqualified: true,
    );
    final operations = <DomainOperation>[
      RecordRelationOperation(
        clientRef: f.id(10).value,
        proposition: f.prop(5),
        assertion: assertion,
      ),
      SupersedeAssertionOperation(
        record: f.ref(6),
        expectedVersion: f.ver(6),
        replacement: assertion,
        rationale: 'Correct recollection',
      ),
      EndAssertionAtOperation(
        record: f.ref(6),
        expectedVersion: f.ver(6),
        at: ExactTime(f.cal, '15'),
        basis: const ImportedClaimBasis(),
      ),
      AddBeliefOperation(clientRef: f.id(11).value, record: belief),
      ReviseAttitudeOperation(
        record: f.ref(11),
        expectedVersion: f.ver(11),
        replacement: belief,
        rationale: 'Correct duration',
      ),
    ];
    final before = operations.map((o) => o.toWire().toText()).toList();
    final stage = stageWritingSource(
      universe: f.u,
      author: proposals.actor,
      label: 'Memoir',
      text: 'A corrected recollection.',
      importTime: '2026-10-12T00:00:00Z',
    );
    final attached = attachWritingSource(
      universe: f.u,
      context: frames.frame().context,
      operations: operations,
      sourceOperations: stage.operations,
      sourceVersion: stage.sourceVersion,
      text: 'A corrected recollection.',
      digest: stage.digest,
      byteSize: stage.byteSize,
    );
    final relation = attached.operations
        .whereType<RecordRelationOperation>()
        .single;
    expect(relation.assertion.basis, isA<SourceAnchorBasis>());
    expect(relation.proposition, f.prop(5));
    final replacement = attached.operations
        .whereType<SupersedeAssertionOperation>()
        .single;
    expect(replacement.replacement.basis, relation.assertion.basis);
    expect(replacement.rationale, 'Correct recollection');
    expect(replacement.expectedVersion, f.ver(6));
    expect(replacement.replacement.validity, f.interval);
    expect(
      attached.operations.whereType<EndAssertionAtOperation>().single.basis,
      relation.assertion.basis,
    );
    expect(
      attached.operations.whereType<AddBeliefOperation>().single.record.basis,
      relation.assertion.basis,
    );
    expect(
      attached.operations
          .whereType<ReviseAttitudeOperation>()
          .single
          .replacement,
      belief,
    );
    expect(operations.map((o) => o.toWire().toText()), before);
  });

  test('pinned relationship support can be ended without becoming a general retraction route', () async {
    final rows = relations.fixture();
    final target = rows.singleWhere((r) => r.payload is AssertionRecord);
    final ref = RecordRef(universe: f.u, record: target.identity.recordId);
    final end = EndAssertionAtOperation(
      record: ref,
      expectedVersion: target.recordVersionId,
      at: ExactTime(f.cal, '15'),
      basis: const ImportedClaimBasis(),
    );
    await gate([end], rows: rows);
    await expectLater(
      () => gate([
        EndAssertionAtOperation(
          record: ref,
          expectedVersion: f.ver(700),
          at: ExactTime(f.cal, '15'),
          basis: const ImportedClaimBasis(),
        ),
      ], rows: rows),
      denied,
    );
    await expectLater(
      () => gate([
        RetractAssertionOperation(
          record: ref,
          expectedVersion: target.recordVersionId,
          rationale: 'Remove relationship',
        ),
      ], rows: rows),
      denied,
    );
    final entity = rows.firstWhere((r) => r.payload is EntityRecord);
    final alias = AddNameOperation(
      record: RecordRef(universe: f.u, record: entity.identity.recordId),
      expectedVersion: entity.recordVersionId,
      name: const ContextualName(text: 'M', validity: UnspecifiedValidity()),
    );
    await gate([alias], rows: rows);
    await expectLater(() => gate([alias], rows: []), denied);
  });

  test('exact author UTF-8 source anchors survive allocated compilation and source verification', () async {
    const text = 'Aé😀\r\nZ';
    final rows = contexts.rows();
    final definitions = [
      DefinitionChange(
        name: 'Lamp',
        introduce: true,
        scope: 'universe',
        sharedAttributes: [
          FactChange(property: 'colour', value: const FactTextValue('red')),
        ],
      ),
    ];
    final types = compileWritingDefinitions(
      declarations: definitions,
      rows: rows,
      worldRows: rows,
    );
    final facts = compileWritingObjects(
      frame: frames.frame(),
      rows: rows,
      worldRows: rows,
      propertyRows: rows,
      definitions: definitions,
      introducedDefinitions: types.introduced,
      changes: [
        ObjectChange(
          name: 'Iris',
          introduce: true,
          facts: [
            FactChange(
              property: 'count',
              value: FactNumberValue(const CanonicalNumber('9007199254740993')),
            ),
          ],
        ),
      ],
    );
    final operations = [...types.operations, ...facts.operations];
    await gate(operations, rows: rows);
    final stage = stageWritingSource(
      universe: f.u,
      author: proposals.actor,
      label: 'Author passage',
      text: text,
      importTime: '2026-10-12T00:00:00Z',
    );
    expect(stage.byteSize, BigInt.from(10));
    expect(stage.digest, sha256.convert(utf8.encode(text)).toString());
    final attached = attachWritingSource(
      universe: f.u,
      context: frames.frame().context,
      operations: operations,
      sourceOperations: stage.operations,
      sourceVersion: stage.sourceVersion,
      text: text,
      digest: stage.digest,
      byteSize: stage.byteSize,
    );
    final changes = compileAllocatedOperations(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: attached.operations,
      versions: attached.versions,
    );
    final candidate = [...rows, ...changes.map(f.decode)];
    final source = candidate.singleWhere(
      (r) => r.payload is SourceVersionRecord,
    );
    final anchor =
        candidate.singleWhere((r) => r.payload is AnchorRecord).payload
            as AnchorRecord;
    expect(source.recordVersionId, attached.versions[stage.sourceVersion]);
    expect(anchor.sourceVersion.version, source.recordVersionId);
    expect(anchor.excerpt, text);
    expect(
      anchor.locator.toWire().toText(),
      ByteRangeLocator(BigInt.zero, BigInt.from(10)).toWire().toText(),
    );
    final assertions = candidate
        .where((r) => r.payload is AssertionRecord)
        .map((r) => r.payload as AssertionRecord);
    expect(assertions, hasLength(2));
    for (final assertion in assertions) {
      expect(assertion.basis, isA<SourceAnchorBasis>());
      expect((assertion.basis as SourceAnchorBasis).verified, isTrue);
      expect(
        (assertion.basis as SourceAnchorBasis).anchor.record,
        candidate
            .singleWhere((r) => r.payload is AnchorRecord)
            .identity
            .recordId,
      );
    }
    final entries = Map.fromEntries(stage.entries);
    await verifyCandidateSources(
      records: candidate,
      readWorkflow: (key) async => entries[key],
      readVersion: (_) async => throw StateError(
        'Anchor must use its allocated candidate source version',
      ),
    );
    expect(
      facts.operations
          .whereType<AssertPropositionOperation>()
          .single
          .assertion
          .basis,
      const ImportedClaimBasis(),
    );
  });

  test(
    'staging limits count UTF-8 bytes and retain immutable import metadata',
    () async {
      Object stage(String label, String text) => stageWritingSource(
        universe: f.u,
        author: proposals.actor,
        label: label,
        text: text,
        importTime: '2026-10-12T00:00:00Z',
      );
      final accepted = stageWritingSource(
        universe: f.u,
        author: proposals.actor,
        label: 'é' * 128,
        text: 'é' * 256000,
        importTime: '2026-10-12T00:00:00Z',
      );
      expect(accepted.byteSize, BigInt.from(512000));
      final source =
          (accepted.operations.last as RecordNarrativeReferenceOperation)
                  .payload
              as SourceVersionRecord;
      expect(
        source.importActor.value,
        proposals.actor.value.replaceFirst('prf_', 'prn_'),
      );
      expect(source.decoding.representation, 'exact-utf8-v1');
      expect(source.importTime, '2026-10-12T00:00:00Z');
      expect(
        () => stage('é' * 129, 'text'),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(
        () => stage('Author', 'é' * 256001),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(
        () => stage('\u3000', 'text'),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(() => stage('Author', '\ud800'), throwsFormatException);
    },
  );

  test('contract review permits finite declarations but not arbitrary author operations', () async {
    final unit = DefineUnitOperation(
      clientRef: f.id(1).value,
      record: units.unit(),
    );
    await expectLater(() => gate([unit]), denied);
    await gate([unit], contracts: true);
    final converted = DefineUnitOperation(
      clientRef: f.id(1).value,
      record: f.patch(units.unit(), {
        'base': CanonicalString(UnitId.fromRecordId(f.id(2)).value),
      }),
    );
    await expectLater(() => gate([converted], contracts: true), denied);
    final unsupported = DefineRuleOperation(
      clientRef: f.id(3).value,
      record: frames.rule(),
    );
    await expectLater(() => gate([unsupported], contracts: true), denied);
    final policy = DefineRuleOperation(
      clientRef: f.id(3).value,
      record: knowledge.policy(),
    );
    await gate([policy], contracts: true);
    await expectLater(
      () => gate([
        CreateEntityOperation(clientRef: f.id(1).value, record: f.entity()),
      ], contracts: true),
      denied,
    );
    await expectLater(
      () => gate([
        RecordIssueDecisionOperation(
          clientRef: f.id(1).value,
          record: IssueDecisionRecord(
            fingerprints: [FindingFingerprint('a' * 64)],
            mode: IssueDecisionMode.accept,
            scope: 'resource:example',
            rationale: 'Accept',
            principal: PrincipalId.generate(),
          ),
        ),
      ], contracts: true),
      denied,
    );
  });

  test('definition review changes only the supported fields of the exact pinned version', () async {
    ActionDefinitionRecord action({bool contract = true}) =>
        ActionDefinitionRecord(
          namespace: 'authoring',
          key: 'Observe',
          labels: {},
          requirements: [],
          scope: Scope(
            context: frames.frame().context,
            applicability: const UniverseApplicability(),
          ),
          validity: const UnspecifiedValidity(),
          consequenceContract: contract ? ConsequenceContract([]) : null,
        );
    await gate(
      [
        ReviseDefinitionOperation(
          record: f.ref(30),
          expectedVersion: f.ver(30),
          replacement: action(contract: false),
        ),
      ],
      rows: [f.row(30, action())],
      contracts: true,
    );
    final old = f.type(20),
        changed = f.patch(f.type(20), {
          'parent': CanonicalString(f.id(21).value),
          'parentResolution': CanonicalString('resolved'),
        });
    final rows = [f.row(20, old)];
    ReviseDefinitionOperation op(
      RecordPayload replacement, {
      RecordVersionId? version,
    }) => ReviseDefinitionOperation(
      record: f.ref(20),
      expectedVersion: version ?? f.ver(20),
      replacement: replacement,
    );
    await gate([op(changed)], rows: rows, contracts: true);
    await expectLater(() => gate([op(changed)], rows: rows), denied);
    await expectLater(
      () =>
          gate([op(changed, version: f.ver(21))], rows: rows, contracts: true),
      denied,
    );
    await expectLater(
      () => gate(
        [
          op(f.patch(changed, {'name': CanonicalString('Renamed')})),
        ],
        rows: rows,
        contracts: true,
      ),
      denied,
    );
    final relationship = relations.fixture().singleWhere(
      (r) => r.payload is RelationRecord,
    );
    final relation = relationship.payload as RelationRecord;
    final allowed = f.patch(relation, {
      'roles': CanonicalArray(
        relation.roles.map(
          (r) => RoleDefinition(
            name: r.name,
            multiplicity: Multiplicity.multiple,
            ordered: true,
            participantTypes: [f.id(20)],
          ).toWire(),
        ),
      ),
    });
    await gate(
      [
        ReviseDefinitionOperation(
          record: RecordRef(
            universe: f.u,
            record: relationship.identity.recordId,
          ),
          expectedVersion: relationship.recordVersionId,
          replacement: allowed,
        ),
      ],
      rows: [relationship],
      contracts: true,
    );
    final renamed = f.patch(relation, {
      'roles': CanonicalArray([
        RoleDefinition(
          name: 'renamed',
          multiplicity: Multiplicity.multiple,
          ordered: false,
        ).toWire(),
      ]),
    });
    await expectLater(
      () => gate(
        [
          ReviseDefinitionOperation(
            record: RecordRef(
              universe: f.u,
              record: relationship.identity.recordId,
            ),
            expectedVersion: relationship.recordVersionId,
            replacement: renamed,
          ),
        ],
        rows: [relationship],
        contracts: true,
      ),
      denied,
    );
  });

  test('author knowledge decisions remain separate from ordinary exact-source preparation', () async {
    final record = knowledge.attitude(
      declared: knowledge.acquisition(
        basis: const AuthorEstablishedKnowledge(),
      ),
      basis: const AuthorDecisionBasis('Explicit author decision'),
    );
    final add = AddBeliefOperation(clientRef: f.id(6).value, record: record);
    await expectLater(() => gate([add], authorOrigin: true), denied);
    await expectLater(
      () => gate([add], knowledgeRationale: 'Explicit author decision'),
      denied,
    );
    await expectLater(
      () => gate([add], authorOrigin: true, knowledgeRationale: 'Wrong reason'),
      denied,
    );
    await gate(
      [add],
      authorOrigin: true,
      knowledgeRationale: 'Explicit author decision',
    );
    final replacement = f.patch(record, {
      'validity': InstantValidity(ExactTime(frames.calendar, '13')).toWire(),
    });
    final revise = ReviseAttitudeOperation(
      record: f.ref(6),
      expectedVersion: f.ver(6),
      replacement: replacement,
      rationale: 'Correct duration',
    );
    await expectLater(
      () => gate([revise], rows: [f.row(6, record)], authorOrigin: true),
      denied,
    );
    await gate(
      [revise],
      rows: [f.row(6, record)],
      authorOrigin: true,
      knowledgeRationale: 'Correct duration',
    );
    final stage = stageWritingSource(
      universe: f.u,
      author: proposals.actor,
      label: 'Decision',
      text: 'Iris knows this.',
      importTime: '2026-10-12T00:00:00Z',
    );
    final attached = attachWritingSource(
      universe: f.u,
      context: frames.frame().context,
      operations: [add],
      sourceOperations: stage.operations,
      sourceVersion: stage.sourceVersion,
      text: 'Iris knows this.',
      digest: stage.digest,
      byteSize: stage.byteSize,
      knowledgeRationale: 'Explicit author decision',
    );
    expect(
      attached.operations.whereType<AddBeliefOperation>().single.record.basis,
      record.basis,
    );
    expect(
      attached.operations
          .whereType<AddBeliefOperation>()
          .single
          .record
          .acquisition!
          .toWire()
          .toText(),
      record.acquisition!.toWire().toText(),
    );
  });

  test('narrative disclosure preparation requires exact edition dependency closure', () async {
    final rows = narrative.rows();
    final result = await compileWritingNarrative(
      frame: disclosures.frame,
      rows: rows,
      input: narrative.delta(
        scenes: [
          narrative.scene(selected: [WritingObjectDisclosure(name: 'Mara')]),
        ],
      ),
      canonAt: (_, _) => rows,
    );
    expect(result.clarifications, isEmpty);
    await expectLater(() => gate(result.operations, rows: rows), denied);
    await gate(result.operations, rows: rows, contracts: true);
    final changed = [
      for (final row in rows)
        row.identity.recordId == f.id(80)
            ? RecordVersion.build(
                recordVersionId: f.ver(800),
                identity: row.identity,
                payload: row.payload,
              )
            : row,
    ];
    await expectLater(
      () => gate(
        result.operations,
        rows: changed,
        contracts: true,
        canonAt: (_, _) => rows,
      ),
      denied,
    );
  });
}
