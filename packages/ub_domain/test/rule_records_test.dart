import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalObject replace(
  CanonicalObject object,
  Map<String, CanonicalValue> changes,
) => CanonicalObject(
  {for (final e in object.fields) e.key: e.value, ...changes}.entries,
);
void main() {
  RecordRef ref(int n) =>
      RecordRef(record: RecordId.parse('rec_${n.toString().padLeft(24, '0')}'));
  final scope = Scope(
    applicability: const UniverseApplicability(),
    context: ref(1),
  );
  RuleRecord rule({
    RuleKind kind = RuleKind.law,
    CommitPolicy policy = CommitPolicy.advisory,
  }) => RuleRecord(
    namespace: 'author',
    key: 'authored',
    labels: {},
    kind: kind,
    commitPolicy: policy,
    applicability: const UnspecifiedApplicability(),
    targetPredicates: ['p', 'p'],
    expression: const LiteralExpr(false),
    capabilities: ['unsupported'],
    executable: false,
    validity: const UnknownValidity(),
  );
  test(
    'rule kind and authored policy remain independent with existing defaults',
    () {
      const defaults = {
        RuleKind.structuralInvariant: CommitPolicy.alwaysBlock,
        RuleKind.physicalConstraint: CommitPolicy.blockUnlessException,
        RuleKind.operationalRequirement: CommitPolicy.recordFinding,
        RuleKind.law: CommitPolicy.recordFinding,
        RuleKind.behavioralTendency: CommitPolicy.advisory,
        RuleKind.authorialRestriction: CommitPolicy.scopeEnforced,
        RuleKind.descriptive: CommitPolicy.reportUnsupported,
      };
      for (final kind in RuleKind.values) {
        expect(kind.defaultCommitPolicy, defaults[kind]);
        final value = rule(kind: kind);
        expect(RecordPayload.fromWire(value.toWire()), value);
        expect(value.commitPolicy, CommitPolicy.advisory);
      }
      final value = rule();
      expect(value.toWire().toText(), isNot(contains('"subjectTypes"')));
      expect(value.toWire().toText(), isNot(contains('"knowledgePolicy"')));
      expect(value.targetPredicates, ['p', 'p']);
      expect(() => value.capabilities.clear(), throwsUnsupportedError);
      expect(
        () => RuleRecord.fromWire(
          replace(value.toWire(), {'subjectTypes': const CanonicalNull()}),
        ),
        throwsFormatException,
      );
    },
  );
  test('knowledge, cardinality and channel chronology declarations retain independent scopes and bounds', () {
    final cardinality = RelationCardinality(
      relation: ref(2),
      grouping: const RoleCardinalityKey('holder'),
      countedRole: 'item',
      maximum: 4294967295,
      scope: scope,
      validity: const UnknownValidity(),
    );
    final value = RuleRecord(
      namespace: 'author',
      key: 'channels',
      labels: {},
      kind: RuleKind.operationalRequirement,
      commitPolicy: CommitPolicy.recordFinding,
      applicability: const UniverseApplicability(),
      targetPredicates: [],
      expression: const LiteralExpr(true),
      capabilities: [],
      executable: true,
      validity: const UnknownValidity(),
      knowledgeBoundary: KnowledgeBoundary(
        holder: ref(3),
        proposition: ref(4),
        context: ref(1),
      ),
      knowledgePolicy: KnowledgePolicy(
        context: ref(1),
        mode: KnowledgeMode.justified,
      ),
      relationCardinality: cardinality,
      channelChronology: const ChannelChronology(
        channel: 'authored',
        forwardOnly: false,
        minimumDelay: '-0005',
        maximumDelay: '0010',
      ),
    );
    expect(RecordPayload.fromWire(value.toWire()), value);
    expect(value.channelChronology!.minimumDelay, '-0005');
    expect(value.channelChronology!.forwardOnly, isFalse);
    expect(value.relationCardinality!.maximum, 4294967295);
    expect(
      const SubjectCardinalityKey().toWire().toText(),
      '{"kind":"subject"}',
    );
    expect(
      () => RelationCardinality(
        relation: ref(2),
        grouping: const SubjectCardinalityKey(),
        countedRole: 'item',
        maximum: 4294967296,
        scope: scope,
        validity: const UnknownValidity(),
      ),
      throwsFormatException,
    );
  });
  test('all creative boundary modes and areas retain authored permission declarations', () {
    final areas = <BoundaryArea>[
      RecordBoundaryArea(ref(1)),
      const PredicateBoundaryArea('p', null),
      CategoryBoundaryArea(ref(2).record),
    ];
    for (final area in areas) {
      for (final mode in BoundaryMode.values) {
        final boundary = BoundaryRecord(
          key: 'authored',
          area: area,
          mode: mode,
          scope: scope,
          validity: const UnknownValidity(),
        );
        expect(RecordPayload.fromWire(boundary.toWire()), boundary);
        expect(boundary.toWire().toText(), isNot(contains('"constraints"')));
      }
    }
    expect(
      areas.first.toWire().toText(),
      '{"kind":"record","record":"${ref(1).record.value}"}',
    );
    expect(
      areas.last.toWire().toText(),
      '{"entity_type":"${ref(2).record.value}","kind":"category"}',
    );
    expect(
      () => BoundaryArea.fromWire(
        CanonicalValue.parseJson(
          '{"kind":"record","ref":${ref(1).toCanonical().toText()}}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('exceptions preserve exact optional rule pins and authorizing decision references', () {
    final pin = RecordVersionId.parse('ver_000000000000000000000001');
    for (final version in [null, pin]) {
      for (final marked in [false, true]) {
        final exception = ExceptionRecord(
          fictionalDeparture: marked,
          rule: ref(2),
          ruleVersion: version,
          scope: scope,
          validity: const UnknownValidity(),
          authorizingDecision: ref(3),
          rationale: 'Specific departure',
        );
        expect(RecordPayload.fromWire(exception.toWire()), exception);
        expect(exception.ruleVersion, version);
        expect(exception.authorizingDecision, ref(3));
        expect(exception.fictionalDeparture, marked);
        expect(
          exception.toWire().toText().contains('fictionalDeparture'),
          marked,
        );
        if (version == null) {
          expect(exception.toWire().toText(), isNot(contains('"ruleVersion"')));
        }
      }
    }
  });
  test('issue decisions retain exact fingerprints, scope and attribution without granting authority', () {
    final fingerprints = [
      const FindingFingerprint('specific finding 🌲'),
      const FindingFingerprint('specific finding 🌲'),
    ];
    for (final mode in IssueDecisionMode.values) {
      final decision = IssueDecisionRecord(
        fingerprints: fingerprints,
        mode: mode,
        scope: 'authored scope',
        rationale: 'Authored resolution',
        principal: PrincipalId.parse('prn_000000000000000000000001'),
      );
      expect(RecordPayload.fromWire(decision.toWire()), decision);
      expect(decision.fingerprints, fingerprints);
      expect(() => decision.fingerprints.clear(), throwsUnsupportedError);
    }
    expect(
      () => IssueDecisionMode.fromName('waive_all'),
      throwsFormatException,
    );
  });
}
