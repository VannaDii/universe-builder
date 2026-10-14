import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/action_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('action revision preserves exact requirements, slot order, consequences, scope and version through recovery', () {
    final root = Directory('/tmp').createTempSync('ub-action-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final predicate = RecordRef(
      record: RecordId.generate(),
      universe: UniverseId.generate(),
    );
    final payload = ActionDefinitionRecord(
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
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.actionDefinition,
      ),
      payload: payload,
    );
    UnfinishedActionForm patch(
      UnfinishedActionForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedActionForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = actionRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      actionRevisionOperation(form).replacement.toWire().toText(),
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
    var store = ActionFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = ActionFormRecoveryStore.open('${root.path}/forms.sqlite');
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
      final add = actionDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = actionFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = actionDraftRequest(
        draft: saved,
        form: patch(pending, {
          'slots': CanonicalArray(
            pending.slots!.reversed.map((slot) => slot.toWire()),
          ),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseDefinitionOperation,
          next = op.replacement as ActionDefinitionRecord;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(next.namespace, payload.namespace);
      expect(next.key, payload.key);
      expect(next.labels, payload.labels);
      expect(next.scope.toWire().toText(), payload.scope.toWire().toText());
      expect(
        next.validity.toWire().toText(),
        payload.validity.toWire().toText(),
      );
      expect(
        next.requirements.map((r) => r.toWire().toText()),
        payload.requirements.map((r) => r.toWire().toText()),
      );
      expect(
        next.consequenceContract!.slots.map((slot) => slot.toWire().toText()),
        payload.consequenceContract!.slots.reversed.map(
          (slot) => slot.toWire().toText(),
        ),
      );
      expect(next.consequenceContract!.slots.map((slot) => slot.order), [1, 0]);
      expect(
        () => actionDraftRequest(
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
        () => actionRevisionOperation(
          patch(form, {'namespace': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => actionRevisionOperation(
          patch(form, {'key': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => actionDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => actionDraftRequest(
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
        'slots': CanonicalArray([
          ActionSlotInput(
            fields: {
              'slot': 'incomplete',
              'order': 'unfinished',
              'delta': '0.00000000000000000001',
            },
          ).toWire(),
        ]),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => actionRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
