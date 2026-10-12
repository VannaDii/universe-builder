import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'writing_binding_test.dart' as binding;
import 'rule_checks_test.dart' as facts;

final frame = facts.frame(time: AtFrameTime(ExactTime(facts.calendar, '10')));
List<RecordVersion> base() => [
  f.row(1, binding.entity(labels: {'en': 'Mara'})),
  f.row(2, binding.entity(labels: {'en': 'Lena'})),
  f.row(3, binding.entity(labels: {'en': 'Iris'})),
  f.row(
    99,
    RepresentedContextRecord(
      universe: f.u,
      kind: const ObjectiveContext(),
      labels: {},
    ),
  ),
];
WritingRelationDefinition definition() => WritingRelationDefinition(
  name: 'knows',
  introduce: true,
  roles: [
    WritingRelationRole(name: 'person', multiple: false),
    WritingRelationRole(name: 'witness', multiple: true),
  ],
);
WritingRelationLimit limit() => WritingRelationLimit(
  name: 'oneFriend',
  relation: 'knows',
  grouping: WritingSubjectGrouping(),
  countedRole: 'person',
  maximum: 1,
  scope: 'universe',
  atTick: '10',
  lifetime: const FactUntilLifetime(endTick: '30'),
);
WritingRelationship relationship({
  Map<String, List<String>> participants = const {
    'person': ['Lena'],
  },
  String statement = 'objective',
}) => WritingRelationship(
  relation: 'knows',
  subject: 'Mara',
  participants: participants,
  scope: 'universe',
  atTick: '10',
  lifetime: const FactUntilLifetime(endTick: '30'),
  statement: statement,
);
CheckChangesRequest input({
  List<WritingRelationDefinition> definitions = const [],
  List<WritingRelationLimit> limits = const [],
  List<WritingRelationship> relationships = const [],
  List<WritingRelationCorrection> contracts = const [],
  List<WritingRelationLimitCorrection> limitCorrections = const [],
  List<WritingRelationshipCorrection> corrections = const [],
  List<WritingRelationshipEnding> endings = const [],
}) => CheckChangesRequest(
  universe: const Selector('World'),
  contextId: ContextId.generate(),
  relationDefinitions: definitions,
  relationLimits: limits,
  relationships: relationships,
  relationCorrections: contracts,
  relationLimitCorrections: limitCorrections,
  relationshipCorrections: corrections,
  relationshipEndings: endings,
);
List<RecordVersion> fixture() => compileWritingCandidate(
  universe: f.u,
  revision: f.revision,
  base: base(),
  operations: compileWritingRelations(
    universe: f.u,
    frame: frame,
    base: base(),
    input: input(
      definitions: [definition()],
      limits: [limit()],
      relationships: [relationship()],
    ),
  ).operations,
);

void main() {
  test('participant role maps retain canonical name order and authored participant order', () {
    final result = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: base(),
      input: input(
        definitions: [definition()],
        relationships: [
          relationship(
            participants: {
              'witness': ['Iris', 'Mara'],
              'person': ['Lena'],
            },
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    final occurrence = result.operations.last as RecordRelationOperation;
    expect(occurrence.proposition.roles.map((r) => r.role), [
      'person',
      'witness',
      'witness',
    ]);
    expect(occurrence.proposition.roles.map((r) => r.participant), [
      f.ref(2),
      f.ref(3),
      f.ref(1),
    ]);
  });
  test('relationship declarations limits and repeated occurrences share transient candidate bindings', () {
    final rows = base();
    final result = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(
        definitions: [definition()],
        limits: [limit()],
        relationships: [
          relationship(),
          relationship(),
          relationship(statement: 'dialogue'),
          relationship(statement: 'unknown'),
        ],
      ),
    );
    expect(result.operations, hasLength(3));
    expect(result.unchanged, ['Mara: relationship knows']);
    expect(result.excluded, ['Mara: knows (dialogue)']);
    expect(result.clarifications, ['Unknown relationship statement intent.']);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: result.operations,
    );
    final relation = candidate.singleWhere((r) => r.payload is RelationRecord);
    final rule =
        candidate.singleWhere((r) => r.payload is RuleRecord).payload
            as RuleRecord;
    expect(supportedWritingRelationLimit(rule), isTrue);
    validateCardinalityRule(rule, candidate);
    expect(
      rule.relationCardinality!.relation.record,
      relation.identity.recordId,
    );
    final assertion =
        candidate.singleWhere((r) => r.payload is AssertionRecord).payload
            as AssertionRecord;
    expect(assertion.attributeMode, AttributeMode.instance);
    expect(assertion.basis, isA<ImportedClaimBasis>());
    expect(assertion.persistence, PersistenceSemantics.explicitInterval);
    final proposition =
        candidate.singleWhere((r) => r.payload is PropositionRecord).payload
            as PropositionRecord;
    expect(proposition.subject, f.ref(1));
    expect(proposition.roles.single.participant, f.ref(2));
    expect(rows, hasLength(4));
  });

  test('role and limit corrections preserve omitted settings pin originals and bind candidate types', () {
    final rows = fixture();
    final prior = compileWritingDefinitions(
      declarations: [
        DefinitionChange(name: 'Person', introduce: true, scope: 'universe'),
      ],
      rows: rows,
      worldRows: [],
    ).operations;
    final result = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      priorOperations: prior,
      input: input(
        contracts: [
          WritingRelationCorrection(
            name: 'knows',
            reason: 'Order witnesses',
            roles: [
              WritingRelationRoleCorrection(
                name: 'witness',
                ordered: true,
                participantTypes: ['Person'],
              ),
            ],
          ),
        ],
        limitCorrections: [
          WritingRelationLimitCorrection(
            name: 'oneFriend',
            reason: 'Allow two',
            maximum: 2,
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    expect(result.operations, hasLength(2));
    final original = rows.singleWhere((r) => r.payload is RelationRecord);
    final op = result.operations.first as ReviseDefinitionOperation;
    expect(op.expectedVersion, original.recordVersionId);
    final replacement = op.replacement as RelationRecord;
    expect(
      replacement.roles.first.toWire().toText(),
      (original.payload as RelationRecord).roles.first.toWire().toText(),
    );
    expect(replacement.roles.last.ordered, isTrue);
    expect(replacement.roles.last.multiplicity, Multiplicity.multiple);
    expect(replacement.roles.last.participantTypes, [
      RecordId.parse((prior.single as IntroduceDefinitionOperation).clientRef),
    ]);
    final limitOp = result.operations.last as ReviseDefinitionOperation;
    final previous = rows.singleWhere((r) => r.payload is RuleRecord);
    expect(limitOp.expectedVersion, previous.recordVersionId);
    expect((limitOp.replacement as RuleRecord).relationCardinality!.maximum, 2);
    expect(
      (limitOp.replacement as RuleRecord).relationCardinality!.validity,
      (previous.payload as RuleRecord).relationCardinality!.validity,
    );
    final revised = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: [...prior, ...result.operations],
    );
    expect(
      () => compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: revised,
        operations: result.operations,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    final duplicates = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(
        contracts: [
          WritingRelationCorrection(
            name: 'knows',
            reason: 'First',
            roles: [
              WritingRelationRoleCorrection(name: 'witness', ordered: true),
            ],
          ),
          WritingRelationCorrection(
            name: 'knows',
            reason: 'Second',
            roles: [
              WritingRelationRoleCorrection(name: 'witness', multiple: false),
            ],
          ),
        ],
      ),
    );
    expect(duplicates.operations, hasLength(1));
    expect(duplicates.clarifications, [
      'Revise each relationship contract only once per delta.',
    ]);
  });

  test('participant corrections retain assertion identity while replacing the authored proposition', () {
    final rows = fixture();
    final original = rows.singleWhere((r) => r.payload is AssertionRecord);
    final result = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(
        corrections: [
          WritingRelationshipCorrection(
            relationshipHandle: original.recordVersionId.value,
            participants: {
              'person': ['Iris'],
            },
            reason: 'Correct person',
          ),
        ],
        endings: [
          WritingRelationshipEnding(
            relationshipHandle: original.recordVersionId.value,
            endTick: '20',
            reason: 'Duplicate edit',
          ),
        ],
      ),
    );
    expect(result.operations, hasLength(2));
    expect(result.clarifications, [
      'Submit only one correction or ending for each relationship in a delta.',
    ]);
    final proposition =
        (result.operations.first as DefinePropositionOperation).record;
    expect(proposition.roles.single.participant, f.ref(3));
    final change = result.operations.last as SupersedeAssertionOperation;
    expect(change.record.record, original.identity.recordId);
    expect(change.expectedVersion, original.recordVersionId);
    expect(change.rationale, 'Correct person');
    expect(
      change.replacement.scope,
      (original.payload as AssertionRecord).scope,
    );
    expect(
      change.replacement.validity,
      (original.payload as AssertionRecord).validity,
    );
    final unchanged = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(
        corrections: [
          WritingRelationshipCorrection(
            relationshipHandle: original.recordVersionId.value,
            participants: {
              'person': ['Lena'],
            },
            reason: 'Already correct',
          ),
        ],
      ),
    );
    expect(unchanged.operations, isEmpty);
    expect(unchanged.unchanged, ['Relationship participants unchanged.']);
    final wrongHandle = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(
        corrections: [
          WritingRelationshipCorrection(
            relationshipHandle: original.identity.recordId.value,
            participants: {
              'person': ['Iris'],
            },
            reason: 'Identity is not version',
          ),
        ],
      ),
    );
    expect(wrongHandle.operations, isEmpty);
    expect(
      wrongHandle.clarifications.single,
      contains('current pinned authored relationship handle'),
    );
  });

  test('relationship endings use original calendars and canonical lifetime validation', () {
    final rows = fixture();
    final original = rows.singleWhere((r) => r.payload is AssertionRecord);
    final result = compileWritingRelations(
      universe: f.u,
      frame: facts.frame(),
      base: rows,
      input: input(
        endings: [
          WritingRelationshipEnding(
            relationshipHandle: original.recordVersionId.value,
            endTick: '20',
            reason: 'Friendship ends',
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    final op = result.operations.single as EndAssertionAtOperation;
    expect(op.at, ExactTime(facts.calendar, '20'));
    expect(op.expectedVersion, original.recordVersionId);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: result.operations,
    );
    final revised =
        candidate
                .singleWhere(
                  (r) => r.identity.recordId == original.identity.recordId,
                )
                .payload
            as AssertionRecord;
    expect(
      revised.validity,
      CalendarIntervalValidity(
        facts.calendar,
        const ExactBound('10'),
        const ExactBound('20'),
      ),
    );
    expect(
      () => compileWritingRelations(
        universe: f.u,
        frame: frame,
        base: rows,
        input: input(
          endings: [
            WritingRelationshipEnding(
              relationshipHandle: original.recordVersionId.value,
              endTick: '5',
              reason: 'Invalid end',
            ),
          ],
        ),
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
  });

  test('invalid role names participants and incomplete limit changes clarify without publication', () {
    final rows = fixture();
    final result = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(
        definitions: [definition()],
        limits: [
          WritingRelationLimit(
            name: 'invalid',
            relation: 'knows',
            grouping: WritingRoleGrouping(role: 'missing'),
            countedRole: 'person',
            maximum: 1,
            scope: 'universe',
          ),
        ],
        contracts: [
          WritingRelationCorrection(
            name: 'knows',
            reason: 'Unknown role',
            roles: [
              WritingRelationRoleCorrection(name: 'missing', ordered: true),
            ],
          ),
        ],
        limitCorrections: [
          WritingRelationLimitCorrection(
            name: 'oneFriend',
            reason: 'Partial time',
            atTick: '20',
          ),
        ],
        relationships: [
          relationship(
            participants: {
              'person': ['Lena', 'Iris'],
            },
          ),
          relationship(
            participants: {
              'missing': ['Lena'],
            },
          ),
          relationship(
            participants: {
              'person': ['Hidden'],
            },
          ),
        ],
      ),
    );
    expect(result.operations, isEmpty);
    expect(result.clarifications, hasLength(7));
    final empty = compileWritingRelations(
      universe: f.u,
      frame: frame,
      base: rows,
      input: input(),
    );
    expect(empty.operations, isEmpty);
  });
}
