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
      expect(recovered.form.executable, isNull);
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
