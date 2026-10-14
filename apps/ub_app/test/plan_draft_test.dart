import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/plan_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('plans retain nested prerequisites ordered repeated steps and exact validity', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final first = ref(), second = ref();
    final record = GoalRecord(
      actor: ref(),
      desired: ref(),
      prerequisites: [
        AllExpr([const LiteralExpr(true), const LiteralExpr(false)]),
        CompareExpr(
          ValueOperand(IntegerValue('9007199254740993')),
          Comparator.ltEq,
          ValueOperand(IntegerValue('9007199254740997')),
        ),
      ],
      steps: [first, first, second],
      status: PlanStatus.active,
      validity: InstantValidity(
        ExactTime(CalendarId.generate(), '9007199254740997'),
      ),
    );
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [RecordPlanOperation(clientRef: 'plan', record: record)],
        rationale: 'Keep a declaration separate from execution.',
      ),
    );
    final form = UnfinishedPlanForm.fromWire(
      planFormFromDraft(draft, 0).toWire(),
    );
    expect(
      planOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = form.copyWith(
      desiredEnabled: false,
      status: 'abandoned',
      steps: form.steps.reversed.toList(),
    );
    final request = planDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as RecordPlanOperation).record;
    expect(next.desired, isNull);
    expect(next.status, PlanStatus.abandoned);
    expect(next.steps, [second, first, first]);
    expect(
      next.prerequisites.map((p) => p.toWire().toText()),
      record.prerequisites.map((p) => p.toWire().toText()),
    );
    expect(next.validity.toWire().toText(), record.validity.toWire().toText());
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => planDraftRequest(
        draft: SavedDraft(version: BigInt.from(7), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished plans recover without assuming active status or successful prerequisites', () {
    final root = Directory('/tmp').createTempSync('ub-plan-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedPlanForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      prerequisites: [
        ExpressionInput(kind: 'all', items: [ExpressionInput()]),
      ],
      steps: [const ExpressionReferenceInput(record: 'unfinished step 記憶 😀')],
    );
    var store = PlanFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = PlanFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.status, isEmpty);
      expect(() => planOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(status: 'active'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
