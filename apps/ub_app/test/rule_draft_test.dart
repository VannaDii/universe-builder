import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/rule_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'rule edits preserve policies exact expressions and specialized extensions',
    () {
      final context = RecordId.generate(),
          reference = RecordRef(
            record: RecordId.generate(),
            universe: UniverseId.generate(),
          );
      final scope = Scope(
        context: RecordRef(record: context),
        applicability: const UniverseApplicability(),
      );
      final record = RuleRecord(
        requiredEvidence: RequiredEvidence(
          sourceCategories: [
            VersionRef(
              universe: reference.universe,
              record: reference.record,
              version: RecordVersionId.generate(),
            ),
          ],
          reviewMethods: EvidenceReviewMethod.values,
        ),
        namespace: 'authored',
        key: 'continuity',
        labels: {'en': 'Continuity 記憶 😀', 'fr': 'Continuité'},
        kind: RuleKind.physicalConstraint,
        commitPolicy: CommitPolicy.blockUnlessException,
        applicability: WorldsApplicability([
          WorldId.generate(),
          WorldId.generate(),
        ]),
        subjectTypes: [RecordId.generate()],
        targetPredicates: ['authored:hometown', 'authored:hometown'],
        expression: CompareExpr(
          const VariableOperand('distance'),
          Comparator.ltEq,
          ValueOperand(IntegerValue('9007199254740993')),
        ),
        capabilities: ['basic.v1', 'authored.v1'],
        executable: true,
        validity: const ConditionalValidity(),
        knowledgeBoundary: KnowledgeBoundary(
          holder: reference,
          proposition: reference,
          context: reference,
        ),
        knowledgePolicy: KnowledgePolicy(
          context: reference,
          mode: KnowledgeMode.justified,
        ),
        channelChronology: const ChannelChronology(
          channel: 'letter',
          forwardOnly: true,
          minimumDelay: '0.25',
          maximumDelay: '9007199254740993',
        ),
        relationCardinality: RelationCardinality(
          relation: reference,
          grouping: const RoleCardinalityKey('speaker'),
          countedRole: 'listener',
          maximum: 4294967295,
          scope: scope,
          validity: const UnknownValidity(),
        ),
      );
      final draft = SavedDraft(
        version: BigInt.from(4),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          operations: [
            DefineRuleOperation(clientRef: 'continuity', record: record),
          ],
          rationale: 'Reviewed rule.',
        ),
      );
      final form = UnfinishedRuleForm.fromWire(
        ruleFormFromDraft(draft, 0).toWire(),
      );
      expect(
        ruleOperation(form).record.toWire().toText(),
        record.toWire().toText(),
      );
      final oldEvidenceForm = UnfinishedRuleForm.fromWire(
        CanonicalObject(form.toWire().fields.where((f) => f.key != 'evidence')),
      );
      expect(
        ruleOperation(oldEvidenceForm).record.toWire().toText(),
        record.toWire().toText(),
      );
      UnfinishedRuleForm withEvidence(RuleEvidenceInput input) =>
          UnfinishedRuleForm.fromWire(
            CanonicalObject([
              ...form.toWire().fields.where((f) => f.key != 'evidence'),
              MapEntry('evidence', input.toWire()),
            ]),
          );
      expect(
        ruleOperation(withEvidence(form.evidence!.copyWith(enabled: false)))
            .record
            .requiredEvidence,
        isNull,
      );
      for (final methods in <List<String>>[
        [],
        ['human_review'],
        ['external_model_review'],
        ['human_review', 'external_model_review'],
      ]) {
        final editedEvidence = withEvidence(
          form.evidence!.copyWith(reviewMethods: methods),
        );
        final policy = ruleOperation(editedEvidence).record.requiredEvidence!;
        expect(policy.reviewMethods.map((m) => m.wireName), methods);
        expect(
          policy.sourceCategories.single.version,
          record.requiredEvidence!.sourceCategories.single.version,
        );
      }
      final nextCategory = RecordVersionId.generate();
      final changedEvidence = withEvidence(
        form.evidence!.copyWith(
          categories: [
            RuleEvidenceCategoryInput(
              universe: reference.universe!.value,
              record: reference.record.value,
              version: nextCategory.value,
            ),
          ],
        ),
      );
      expect(
        ruleOperation(changedEvidence)
            .record
            .requiredEvidence!
            .sourceCategories
            .single
            .version,
        nextCategory,
      );
      expect(
        () => buildRuleEvidence(RuleEvidenceInput(enabled: true)),
        throwsFormatException,
      );
      expect(
        () => buildRuleEvidence(
          form.evidence!.copyWith(reviewMethods: ['unknown']),
        ),
        throwsFormatException,
      );
      final knowledge = form.knowledge!.copyWith(
        mode: 'author_established',
        boundaryEnabled: false,
      );
      final edited = UnfinishedRuleForm.fromWire(
        CanonicalObject([
          ...form.toWire().fields.where((f) => f.key != 'knowledge'),
          MapEntry('knowledge', knowledge.toWire()),
        ]),
      );
      final editedRecord = ruleOperation(edited).record;
      expect(editedRecord.knowledgeBoundary, isNull);
      expect(
        editedRecord.knowledgePolicy!.mode,
        KnowledgeMode.authorEstablished,
      );
      expect(
        editedRecord.knowledgePolicy!.context,
        record.knowledgePolicy!.context,
      );
      expect(
        editedRecord.relationCardinality!.toWire().toText(),
        record.relationCardinality!.toWire().toText(),
      );
      expect(
        editedRecord.channelChronology!.toWire().toText(),
        record.channelChronology!.toWire().toText(),
      );
      final removed = UnfinishedRuleForm.fromWire(
        CanonicalObject([
          ...form.toWire().fields.where((f) => f.key != 'knowledge'),
          MapEntry('knowledge', const RuleKnowledgeInput().toWire()),
        ]),
      );
      expect(ruleOperation(removed).record.knowledgePolicy, isNull);
      expect(ruleOperation(removed).record.knowledgeBoundary, isNull);
      final oldConstraintForm = UnfinishedRuleForm.fromWire(
        CanonicalObject(
          form.toWire().fields.where((f) => f.key != 'constraints'),
        ),
      );
      expect(
        ruleOperation(oldConstraintForm).record.toWire().toText(),
        record.toWire().toText(),
      );
      final changedConstraints = form.constraints!.copyWith(
        maximum: '0',
        minimumEnabled: false,
        maximumEnabled: true,
        maximumDelay: '9007199254740995',
        forwardOnly: false,
      );
      final changedConstraintForm = UnfinishedRuleForm.fromWire(
        CanonicalObject([
          ...form.toWire().fields.where((f) => f.key != 'constraints'),
          MapEntry('constraints', changedConstraints.toWire()),
        ]),
      );
      final changedConstraintRecord = ruleOperation(changedConstraintForm)
          .record;
      expect(changedConstraintRecord.relationCardinality!.maximum, 0);
      expect(
        changedConstraintRecord.relationCardinality!.scope.toWire().toText(),
        record.relationCardinality!.scope.toWire().toText(),
      );
      expect(changedConstraintRecord.channelChronology!.minimumDelay, isNull);
      expect(
        changedConstraintRecord.channelChronology!.maximumDelay,
        '9007199254740995',
      );
      expect(changedConstraintRecord.channelChronology!.forwardOnly, isFalse);
      expect(
        changedConstraintRecord.knowledgePolicy!.toWire().toText(),
        record.knowledgePolicy!.toWire().toText(),
      );
      final noConstraints = UnfinishedRuleForm.fromWire(
        CanonicalObject([
          ...form.toWire().fields.where((f) => f.key != 'constraints'),
          MapEntry('constraints', const RuleConstraintInput().toWire()),
        ]),
      );
      expect(ruleOperation(noConstraints).record.relationCardinality, isNull);
      expect(ruleOperation(noConstraints).record.channelChronology, isNull);
      final request = ruleDraftRequest(
        draft: draft,
        form: form,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => ruleDraftRequest(
          draft: SavedDraft(version: BigInt.from(5), content: draft.content),
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    },
  );
  test('unfinished rules recover without defaulting an executable choice or expression', () {
    final root = Directory('/tmp').createTempSync('ub-rule-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedRuleForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      namespace: 'authored',
      key: 'incomplete',
      targetPredicates: ['incomplete predicate 記憶 😀'],
      evidence: RuleEvidenceInput(
        enabled: true,
        categories: [
          const RuleEvidenceCategoryInput(
            record: 'unfinished category 記憶 😀',
            version: 'not chosen',
          ),
        ],
        reviewMethods: ['still deciding'],
      ),
      constraints: const RuleConstraintInput(
        cardinalityEnabled: true,
        chronologyEnabled: true,
        maximum: 'unfinished',
        minimumEnabled: true,
        minimumDelay: '9007199254740993',
      ),
      knowledge: const RuleKnowledgeInput(
        policyEnabled: true,
        mode: 'still deciding',
        policyContext: ExpressionReferenceInput(
          record: 'unfinished context 記憶 😀',
        ),
      ),
      expression: ExpressionInput(
        kind: 'compare',
        operands: {
          'left': const OperandInput(kind: 'variable', name: 'unfinished'),
        },
      ),
    );
    var store = RuleFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = RuleFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!;
      expect(
        recovered.form.evidence!.toWire().toText(),
        form.evidence!.toWire().toText(),
      );
      expect(
        () => buildRuleEvidence(recovered.form.evidence!),
        throwsFormatException,
      );
      expect(recovered.form.executable, isNull);
      expect(recovered.form.constraints!.forwardOnly, isNull);
      expect(recovered.form.constraints!.minimumDelay, '9007199254740993');
      expect(
        () => buildRuleChronology(recovered.form.constraints!),
        throwsFormatException,
      );
      expect(
        () => buildRuleCardinality(recovered.form.constraints!, null),
        throwsFormatException,
      );
      expect(
        recovered.form.knowledge!.policyContext.record,
        'unfinished context 記憶 😀',
      );
      expect(
        () => buildRuleKnowledgePolicy(recovered.form.knowledge!),
        throwsFormatException,
      );
      expect(recovered.form.expression.operands['right'], isNull);
      expect(
        recovered.form.targetPredicates.single,
        'incomplete predicate 記憶 😀',
      );
      expect(() => ruleOperation(recovered.form), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
