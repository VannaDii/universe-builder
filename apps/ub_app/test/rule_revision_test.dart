import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/rule_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('rule revision preserves policies, expression and extensions through recovery', () {
    final root = Directory('/tmp').createTempSync('ub-rule-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final reference = RecordRef(
      record: RecordId.generate(),
      universe: UniverseId.generate(),
    );
    final ruleScope = Scope(
      context: RecordRef(record: context),
      applicability: const UniverseApplicability(),
    );
    final payload = RuleRecord(
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
        scope: ruleScope,
        validity: const UnknownValidity(),
      ),
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.rule,
      ),
      payload: payload,
    );
    UnfinishedRuleForm patch(
      UnfinishedRuleForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedRuleForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = ruleRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      ruleRevisionOperation(form).replacement.toWire().toText(),
      payload.toWire().toText(),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    var store = RuleFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = RuleFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final empty = SavedDraft(
        version: BigInt.one,
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: context,
          operations: [],
          rationale: 'Review calendar changes.',
        ),
      );
      final add = ruleDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = ruleFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = ruleDraftRequest(
        draft: saved,
        form: patch(pending, {
          'knowledge': pending.knowledge!
              .copyWith(mode: 'author_established', boundaryEnabled: false)
              .toWire(),
          'constraints': pending.constraints!
              .copyWith(
                maximum: '0',
                forwardOnly: false,
                minimumEnabled: false,
                maximumDelay: '9007199254740995',
              )
              .toWire(),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseDefinitionOperation,
          next = op.replacement as RuleRecord;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(next.namespace, payload.namespace);
      expect(next.key, payload.key);
      expect(next.labels, payload.labels);
      expect(
        next.expression.toWire().toText(),
        payload.expression.toWire().toText(),
      );
      expect(
        next.applicability.toWire().toText(),
        payload.applicability.toWire().toText(),
      );
      expect(next.subjectTypes, payload.subjectTypes);
      expect(next.targetPredicates, payload.targetPredicates);
      expect(next.capabilities, payload.capabilities);
      expect(next.executable, payload.executable);
      expect(next.commitPolicy, payload.commitPolicy);
      expect(next.kind, payload.kind);
      expect(
        next.validity.toWire().toText(),
        payload.validity.toWire().toText(),
      );
      expect(next.knowledgeBoundary, isNull);
      expect(next.knowledgePolicy!.mode, KnowledgeMode.authorEstablished);
      expect(next.knowledgePolicy!.context, payload.knowledgePolicy!.context);
      expect(next.relationCardinality!.maximum, 0);
      expect(
        next.relationCardinality!.scope.toWire().toText(),
        payload.relationCardinality!.scope.toWire().toText(),
      );
      expect(
        next.relationCardinality!.validity.toWire().toText(),
        payload.relationCardinality!.validity.toWire().toText(),
      );
      expect(next.channelChronology!.forwardOnly, isFalse);
      expect(next.channelChronology!.minimumDelay, isNull);
      expect(next.channelChronology!.maximumDelay, '9007199254740995');
      expect(
        next.channelChronology!.channel,
        payload.channelChronology!.channel,
      );
      expect(
        () => ruleDraftRequest(
          draft: saved,
          form: patch(form, {
            'labels': CanonicalArray([
              const PropertyLabelInput(
                language: 'en',
                text: 'Different',
              ).toWire(),
            ]),
          }),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      expect(
        () => ruleRevisionOperation(
          patch(form, {'namespace': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => ruleRevisionOperation(
          patch(form, {'key': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => ruleDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => ruleDraftRequest(
          draft: saved,
          form: patch(pending, {
            'expected_record_version': CanonicalString(
              RecordVersionId.generate().value,
            ),
          }),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final incomplete = patch(form, {
        'expression': ExpressionInput(
          kind: 'compare',
          strings: {'operator': 'unfinished'},
        ).toWire(),
        'constraints': form.constraints!
            .copyWith(maximumDelay: 'unfinished delay 記憶 😀')
            .toWire(),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => ruleRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
