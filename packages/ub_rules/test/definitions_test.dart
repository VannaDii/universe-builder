import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
WorldId world(int n) => WorldId.parse('wld_${suffix(n)}');
UniverseId universe(int n) => UniverseId.parse('unv_${suffix(n)}');
RecordVersion record(int n, RecordPayload payload, {int owner = 1}) =>
    RecordVersion.build(
      recordVersionId: RecordVersionId.parse('ver_${suffix(n)}'),
      identity: RecordIdentity(
        universeId: universe(owner),
        recordId: id(n),
        recordKind: payload.recordKind,
      ),
      payload: payload,
    );
EntityTypeRecord type({
  RecordId? parent,
  ParentResolution resolution = ParentResolution.root,
  bool executable = true,
  Applicability scope = const UniverseApplicability(),
}) => EntityTypeRecord(
  namespace: 'author',
  key: 'type',
  labels: {},
  name: 'Type',
  parent: parent,
  parentResolution: resolution,
  applicability: scope,
  classificationExecutable: executable,
);
EntityRecord entity({
  RecordId? classification,
  ClassificationResolution resolution = ClassificationResolution.resolved,
}) => EntityRecord(
  names: [],
  classification: classification,
  classificationResolution: resolution,
  worldAssociations: [],
  labels: {},
  metadata: {},
);
RuleRecord rule(List<RecordId> targets) => RuleRecord(
  namespace: 'author',
  key: 'rule',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: RuleKind.physicalConstraint.defaultCommitPolicy,
  applicability: const UniverseApplicability(),
  subjectTypes: targets,
  targetPredicates: [],
  expression: const LiteralExpr(true),
  capabilities: [],
  executable: true,
  validity: const UnspecifiedValidity(),
);

void main() {
  List<RecordVersion> chain() => [
    record(1, type()),
    record(2, type(parent: id(1), resolution: ParentResolution.resolved)),
    record(3, entity(classification: id(2))),
  ];

  test('instances and definitions resolve nearest-first ancestry from the supplied snapshot', () {
    final records = chain();
    final index = RecordIndex(records);
    expect(index.ancestry(id(3)), definitionAncestry(id(3), records));
    expect(definitionAncestry(id(3), records).types, [id(2), id(1)]);
    expect(index.ancestry(id(2)).types, [id(2), id(1)]);
    expect(index.ancestry(id(1)).complete, isTrue);
    expect(index.matches(id(3), [id(1)], null), isTrue);
    expect(index.matches(id(3), [id(9)], null), isFalse);
    expect(definitionMatches(id(3), [id(1)], records, null), isTrue);
    records.clear();
    expect(index.ancestry(id(3)).complete, isTrue);
    expect(() => index.ancestry(id(3)).types.clear(), throwsUnsupportedError);
    expect(definitionAncestry(id(3), records).complete, isFalse);
  });

  test('missing, ambiguous, nonexecutable and contradictory parents do not establish membership', () {
    for (final root in [
      type(parent: id(9), resolution: ParentResolution.resolved),
      type(resolution: ParentResolution.ambiguous),
      type(executable: false),
      type(parent: id(9)),
      type(resolution: ParentResolution.resolved),
    ]) {
      final records = [
        record(1, root),
        record(3, entity(classification: id(1))),
      ];
      expect(definitionAncestry(id(3), records).complete, isFalse);
      expect(definitionMatches(id(3), [id(1)], records, null), isNull);
      expect(RecordIndex(records).matches(id(3), [id(9)], null), isNull);
    }
    final cyclic = [
      record(1, type(parent: id(2), resolution: ParentResolution.resolved)),
      record(2, type(parent: id(1), resolution: ParentResolution.resolved)),
    ];
    expect(definitionAncestry(id(1), cyclic).types, [id(1), id(2)]);
    expect(definitionAncestry(id(1), cyclic).complete, isFalse);
  });

  test('classification is never inferred from labels, missing identities or another universe', () {
    for (final e in [
      entity(),
      entity(
        classification: id(1),
        resolution: ClassificationResolution.unclassified,
      ),
      entity(
        classification: id(1),
        resolution: ClassificationResolution.ambiguous,
      ),
    ]) {
      expect(
        definitionMatches(
          id(3),
          [id(1)],
          [record(1, type()), record(3, e)],
          null,
        ),
        isNull,
      );
    }
    final otherUniverse = [
      record(1, type(), owner: 2),
      record(3, entity(classification: id(1))),
    ];
    expect(RecordIndex(otherUniverse).ancestry(id(3)).complete, isFalse);
    expect(definitionMatches(id(9), [id(1)], otherUniverse, null), isNull);
    expect(definitionMatches(id(9), [], otherUniverse, null), isTrue);
    expect(
      definitionAncestry(id(1), [
        record(1, WorldRecord(selector: 'world')),
      ]).complete,
      isFalse,
    );
  });

  test('each ancestor has independent world applicability and multiworld requests cover every world', () {
    final records = [
      record(1, type(scope: WorldsApplicability([world(1)]))),
      record(
        2,
        type(
          parent: id(1),
          resolution: ParentResolution.resolved,
          scope: WorldsApplicability([world(2)]),
        ),
      ),
      record(3, entity(classification: id(2))),
    ];
    final index = RecordIndex(records);
    expect(index.matches(id(3), [id(1)], [id(1)]), isTrue);
    expect(index.matches(id(3), [id(2)], [id(1)]), isFalse);
    expect(index.matches(id(3), [id(1), id(2)], [id(1), id(2)]), isTrue);
    expect(index.matches(id(3), [id(1)], [id(1), id(2)]), isFalse);
    expect(index.matches(id(3), [id(1)], []), isNull);
    expect(index.matches(id(3), [id(1)], null), isTrue);
    expect(worldApplies(WorldsApplicability([]), []), isFalse);
    expect(worldApplies(const ConditionalApplicability(), [id(1)]), isNull);
    expect(worldApplies(const UniverseApplicability(), []), isTrue);
  });

  test('whole fact scope requires explicit universe-wide type permission', () {
    final records = [
      record(1, type(scope: WorldsApplicability([world(1)]))),
      record(3, entity(classification: id(1))),
    ];
    expect(
      coversDefinitionScope(
        id(3),
        [id(1)],
        records,
        WorldsApplicability([world(1)]),
      ),
      isTrue,
    );
    expect(
      coversDefinitionScope(
        id(3),
        [id(1)],
        records,
        WorldsApplicability([world(1), world(2)]),
      ),
      isFalse,
    );
    expect(
      coversDefinitionScope(
        id(3),
        [id(1)],
        records,
        const UniverseApplicability(),
      ),
      isFalse,
    );
    expect(
      coversDefinitionScope(
        id(3),
        [id(1)],
        records,
        const ConditionalApplicability(),
      ),
      isNull,
    );
    expect(
      coversDefinitionScope(id(9), [id(1)], records, WorldsApplicability([])),
      isTrue,
    );
    records[0] = record(1, type());
    expect(
      coversDefinitionScope(
        id(3),
        [id(1)],
        records,
        const UniverseApplicability(),
      ),
      isTrue,
    );
    records[0] = record(1, type(scope: const UnspecifiedApplicability()));
    expect(
      coversDefinitionScope(
        id(3),
        [id(1)],
        records,
        const UniverseApplicability(),
      ),
      isNull,
    );
  });

  test('type hints establish rule relevance without selecting or filtering expression operands', () {
    final records = chain();
    records.add(
      record(4, entity(resolution: ClassificationResolution.unclassified)),
    );
    final index = RecordIndex(records);
    expect(ruleApplies(rule([id(1)]), records, []), isTrue);
    expect(ruleAppliesIndexed(rule([id(1)]), records, index, []), isTrue);
    expect(ruleApplies(rule([id(9)]), records, []), isNull);
    expect(ruleAppliesIndexed(rule([id(9)]), records, index, []), isNull);
    expect(ruleApplies(rule([]), [], []), isTrue);
    expect(ruleApplies(rule([id(1)]), [], []), isFalse);
    expect(rule([id(1)]).expression, const LiteralExpr(true));
  });

  test('reference and indexed lookups retain their existing duplicate identity precedence', () {
    final records = [record(1, type()), record(1, type(executable: false))];
    expect(definitionAncestry(id(1), records).complete, isTrue);
    expect(RecordIndex(records).ancestry(id(1)).complete, isFalse);
  });
}
