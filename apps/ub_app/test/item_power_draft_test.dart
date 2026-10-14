import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/item_power_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'item powers preserve predicate links exact values scope and validity',
    () {
      final universe = UniverseId.generate(), context = RecordId.generate();
      RecordRef ref() =>
          RecordRef(universe: universe, record: RecordId.generate());
      final record = ItemPowerRecord(
        item: ref(),
        holderPredicate: ref(),
        powerPredicate: ref(),
        value: IntegerValue('9007199254740997'),
        scope: Scope(
          context: RecordRef(universe: universe, record: context),
          realm: ref(),
          applicability: const UniverseApplicability(),
        ),
        validity: const ConditionalValidity(),
      );
      final draft = SavedDraft(
        version: BigInt.from(6),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          operations: [
            DefineItemPowerOperation(clientRef: 'power', record: record),
          ],
          rationale: 'Keep possession separate from location and ownership.',
        ),
      );
      final form = UnfinishedItemPowerForm.fromWire(
        itemPowerFormFromDraft(draft, 0).toWire(),
      );
      expect(
        itemPowerOperation(form).record.toWire().toText(),
        record.toWire().toText(),
      );
      final changed = form.copyWith(
        value: const QualifierInput(kind: 'integer', value: '9007199254740999'),
      );
      final request = itemPowerDraftRequest(
        draft: draft,
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final next =
          (request.content.operations.single as DefineItemPowerOperation)
              .record;
      expect((next.value as IntegerValue).digits, '9007199254740999');
      expect(next.item, record.item);
      expect(next.holderPredicate, record.holderPredicate);
      expect(next.powerPredicate, record.powerPredicate);
      expect(next.scope.toWire().toText(), record.scope.toWire().toText());
      expect(
        next.validity.toWire().toText(),
        record.validity.toWire().toText(),
      );
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => itemPowerDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: changed,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => itemPowerOperation(
          form.copyWith(scope: const ScopeInput(applicability: 'conditional')),
        ),
        throwsFormatException,
      );
    },
  );
  test('unfinished powers recover without inferring a universe-wide scope', () {
    final root = Directory('/tmp').createTempSync('ub-item-power-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedItemPowerForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      item: const ExpressionReferenceInput(record: 'unfinished item 記憶 😀'),
      value: const QualifierInput(
        kind: 'rational',
        value: '7',
        denominator: '',
      ),
    );
    var store = ItemPowerFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = ItemPowerFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.scope.applicability, 'unspecified');
      expect(() => itemPowerOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(
          scope,
          form.copyWith(rationale: 'another edit'),
          BigInt.zero,
        ),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
