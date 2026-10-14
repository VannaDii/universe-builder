import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/action_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('action edits retain exact requirements, consequence contract and current draft identity', () {
    final context = RecordId.generate(),
        predicate = RecordRef(
          record: RecordId.generate(),
          universe: UniverseId.generate(),
        );
    final record = ActionDefinitionRecord(
      namespace: 'authored',
      key: 'journey',
      labels: {'en': 'Journey 記憶 😀', 'fr': 'Voyage'},
      requirements: [
        AttributeRequirement(
          'traveler',
          predicate,
          IntegerValue('9007199254740993'),
        ),
      ],
      scope: Scope(
        context: RecordRef(record: context),
        applicability: const UniverseApplicability(),
      ),
      validity: const ConditionalValidity(),
      consequenceContract: ConsequenceContract([
        EffectSlot(
          slot: 'set',
          order: 0,
          presence: EffectPresence.required,
          target: EffectTarget('traveler', predicate),
          condition: AttributeEqualsEffect(
            'traveler',
            predicate,
            IntegerValue('9007199254740993'),
          ),
          change: SetEffect(
            Polarity.refutation,
            IntegerValue('9007199254740994'),
          ),
          lifetime: TicksEffect(ConsequenceInteger('9007199254740995')),
        ),
        EffectSlot(
          slot: 'delta',
          order: 1,
          presence: EffectPresence.optional,
          target: EffectTarget('witness', predicate),
          condition: const AlwaysEffect(),
          change: DeltaEffect(
            delta: ConsequenceDecimal('0.25'),
            minimum: ConsequenceDecimal('0'),
            maximum: ConsequenceDecimal('10'),
            unit: UnitId.generate(),
          ),
          lifetime: const UntilChangedEffect(),
        ),
      ]),
    );
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          DefineActionOperation(clientRef: 'journey', record: record),
        ],
        rationale: 'Preserve the review rationale.',
      ),
    );
    final input = UnfinishedActionForm.fromWire(
      actionFormFromDraft(draft, 0).toWire(),
    );
    final request = actionDraftRequest(
      draft: draft,
      form: input,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final rebuilt =
        (request.content.operations.single as DefineActionOperation).record;
    expect(rebuilt.toWire().toText(), record.toWire().toText());
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => actionDraftRequest(
        draft: SavedDraft(version: BigInt.from(7), content: draft.content),
        form: input,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    final absent = UnfinishedActionForm(
      baseRevision: input.baseRevision,
      representedContext: context,
      clientRef: input.clientRef,
      namespace: input.namespace,
      key: input.key,
      scope: input.scope,
    );
    expect(actionOperation(absent).record.consequenceContract, isNull);
    final empty = UnfinishedActionForm(
      baseRevision: input.baseRevision,
      representedContext: context,
      clientRef: input.clientRef,
      namespace: input.namespace,
      key: input.key,
      scope: input.scope,
      slots: [],
    );
    expect(actionOperation(empty).record.consequenceContract!.slots, isEmpty);
    final reordered = ConsequenceContract(
      input.slots!.reversed.map(buildActionSlot),
    );
    expect(reordered.slots.map((s) => s.order), [1, 0]);
    expect(
      () => ConsequenceContract([
        buildActionSlot(input.slots!.first),
        buildActionSlot(input.slots!.first),
      ]),
      throwsFormatException,
    );
  });
  test('incomplete action input survives restart and competing recovery writes are rejected', () {
    final root = Directory('/tmp').createTempSync('ub-action-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedActionForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      requirements: [const ActionRequirementInput(role: '記憶 😀')],
      slots: [
        ActionSlotInput(
          fields: {'order': 'unfinished', 'delta': '0.00000000000000000001'},
        ),
      ],
    );
    var store = ActionFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = ActionFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!;
      expect(recovered.form.requirements.single.role, '記憶 😀');
      expect(
        recovered.form.slots!.single.fields['delta'],
        '0.00000000000000000001',
      );
      expect(() => actionOperation(recovered.form), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      final changed = UnfinishedActionForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        key: 'competing',
      );
      expect(
        () => store.save(scope, changed, BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
