@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending rule',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
const pendingTime = TemporalValidityInput(
  kind: 'pending',
  calendar: '\ufeffCalendar',
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled start',
    upper: '\ufeffUpper',
    amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  ),
);
const pendingScope = ScopeInput(
  applicability: 'undecided',
  worlds: ['\ufeffWorld', '', '\ufeffWorld'],
  contextRecord: '',
  contextUniverse: 'pending',
  hasRealm: false,
  realmRecord: 'disabled realm',
  realmUniverse: 'disabled universe',
);
UnfinishedRuleForm input(EditorFormScope s) {
  final ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      world = WorldId.generate(),
      subject = RecordId.generate(),
      category = VersionRef(
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
        universe: s.universe,
      );
  return UnfinishedRuleForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    namespace: '\ufeffAuthored',
    key: '\ufeffRule',
    kind: 'undecided',
    commitPolicy: 'pending',
    rationale: '\ufeffReason\r\n\u0000😀',
    labels: const [
      PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
      PropertyLabelInput(),
      PropertyLabelInput(language: '\ufeffen', text: 'Repeated'),
    ],
    scope: pendingScope,
    subjectTypes: const ['\ufeffSubject', '', '\ufeffSubject'],
    targetPredicates: const ['\ufeffPredicate', '', '\ufeffPredicate'],
    capabilities: const ['\ufeffCapability', '', '\ufeffCapability'],
    executable: false,
    validity: pendingTime,
    expression: ExpressionInput(
      kind: 'pending',
      strings: {'\ufeffKey': '\ufeffValue\r\n\u0000😀', '': ''},
      flags: {'yes': true, 'no': false, 'unset': null},
      items: [
        ExpressionInput(),
        ExpressionInput(kind: 'same'),
        ExpressionInput(kind: 'same'),
      ],
      children: {'\ufeffChild': ExpressionInput()},
      value: const QualifierInput(
        kind: 'undecided',
        value: '\ufeff9007199254740997',
        lower: QualifierInput(kind: 'integer', value: '3'),
        children: [
          QualifierInput(key: 'same'),
          QualifierInput(key: 'same'),
        ],
        temporal: pendingTime,
      ),
      original: const NotExpr(LiteralExpr(false)),
    ),
    knowledge: const RuleKnowledgeInput(
      policyEnabled: false,
      boundaryEnabled: true,
      mode: '\ufeffUnfinished mode',
      policyContext: ExpressionReferenceInput(
        record: 'disabled',
        universe: '\ufeffUniverse',
      ),
      holder: ExpressionReferenceInput(record: '', universe: 'holder universe'),
      proposition: ExpressionReferenceInput(record: 'pending proposition'),
      boundaryContext: ExpressionReferenceInput(record: 'disabled context'),
    ),
    constraints: const RuleConstraintInput(
      cardinalityEnabled: false,
      chronologyEnabled: false,
      relation: ExpressionReferenceInput(
        record: '',
        universe: '\ufeffRelation universe',
      ),
      grouping: 'undecided',
      groupingRole: '\ufeffGrouping',
      countedRole: '\ufeffCounted',
      maximum: '9007199254740997?',
      scope: pendingScope,
      validity: pendingTime,
      channel: '\ufeffChannel',
      forwardOnly: false,
      minimumEnabled: false,
      maximumEnabled: false,
      minimumDelay: 'disabled minimum',
      maximumDelay: '\ufeffDisabled maximum',
    ),
    evidence: RuleEvidenceInput(
      enabled: false,
      categories: const [
        RuleEvidenceCategoryInput(
          record: '\ufeffCategory',
          universe: '',
          version: 'pending',
        ),
        RuleEvidenceCategoryInput(),
        RuleEvidenceCategoryInput(
          record: '\ufeffCategory',
          universe: '',
          version: 'pending',
        ),
      ],
      reviewMethods: ['\ufeffMethod', '', '\ufeffMethod'],
    ),
    original: RuleRecord(
      namespace: '\ufeffOriginal',
      key: '\ufeffRule',
      labels: {'\ufeffen': '\ufeffName', '': '', 'ja': '記憶😀'},
      kind: RuleKind.physicalConstraint,
      commitPolicy: CommitPolicy.blockUnlessException,
      applicability: WorldsApplicability([world, world]),
      subjectTypes: [subject, subject],
      targetPredicates: ['\ufeffPredicate', '\ufeffPredicate'],
      capabilities: ['\ufeffCapability', '\ufeffCapability'],
      expression: CompareExpr(
        const VariableOperand('\ufeffDistance'),
        Comparator.ltEq,
        const ValueOperand(RationalValue('9007199254740997', '3')),
      ),
      executable: true,
      validity: InstantValidity(
        DurationTime(
          CalendarId.generate(),
          SequenceValue([const TextValue('\ufeffLifetime')]),
        ),
      ),
      requiredEvidence: RequiredEvidence(
        sourceCategories: [category, category],
        reviewMethods: EvidenceReviewMethod.values,
      ),
      knowledgePolicy: KnowledgePolicy(
        context: ref,
        mode: KnowledgeMode.justified,
      ),
      knowledgeBoundary: KnowledgeBoundary(
        holder: ref,
        proposition: ref,
        context: ref,
      ),
      relationCardinality: RelationCardinality(
        relation: ref,
        grouping: const RoleCardinalityKey('\ufeffSpeaker'),
        countedRole: '\ufeffListener',
        maximum: 4294967295,
        scope: Scope(
          context: ref,
          applicability: WorldsApplicability([world, world]),
          realm: RecordRef(record: ref.record),
        ),
        validity: const ConditionalValidity(),
      ),
      channelChronology: const ChannelChronology(
        channel: '\ufeffChannel',
        forwardOnly: true,
        minimumDelay: '0.00000000000001',
        maximumDelay: '9007199254740997',
      ),
    ),
    revisionTarget: const ExpressionReferenceInput(
      record: '',
      universe: '\ufeffPending',
    ),
    expectedRecordVersion: RecordVersionId.generate(),
    draftVersion: maxU64,
  );
}

void main() {
  test('typed rule recovery retains expressions, disabled extension fields, duplicate input and all original policies', () {
    final root = Directory('/tmp').createTempSync('ub-typed-rule-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = RuleFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = RuleFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(rule_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select('SELECT count(*) AS n FROM rule_evidence_category')
              .single['n'],
          3,
        );
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('rule replacement clears superseded expressions and policies and distinguishes absent extensions from disabled defaults', () {
    final root = Directory('/tmp').createTempSync('ub-rule-clear-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = RuleFormRecoveryStore.open(path), generation = BigInt.zero;
    try {
      generation = store.save(s, form, generation).generation;
      generation = store.save(s, form, generation).generation;
      final empty = UnfinishedRuleForm(
        baseRevision: form.baseRevision,
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
      );
      generation = store.save(s, empty, generation).generation;
      store.close();
      store = RuleFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name!='rule_form'",
        )) {
          expect(
            db.select('SELECT count(*) AS n FROM "${row['name']}"').single['n'],
            row['name'] == 'rule_expression' || row['name'] == 'rule_temporal'
                ? 1
                : row['name'] == 'rule_bound'
                ? 2
                : 0,
            reason: row['name'] as String,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
      for (final flag in <bool?>[null, false, true]) {
        final defaults = UnfinishedRuleForm(
          baseRevision: form.baseRevision,
          representedContext: s.representedContext!,
          clientRef: s.typeClientRef!,
          executable: flag,
          knowledge: const RuleKnowledgeInput(),
          constraints: RuleConstraintInput(forwardOnly: flag),
          evidence: RuleEvidenceInput(),
        );
        generation = store.save(s, defaults, generation).generation;
        store.close();
        store = RuleFormRecoveryStore.open(path);
        expect(
          store.load(s)!.form.toWire().toText(),
          defaults.toWire().toText(),
        );
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
