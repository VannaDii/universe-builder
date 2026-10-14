import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/saga_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('saga edits preserve roles, nullable exact order and list order without renumbering', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final work = ref();
    final record = SagaRecord(
      title: 'Collected accounts 記憶 😀',
      labels: {'': 'Original title', 'en': 'Accounts'},
      memberships: [
        SagaMembership(work: work, role: 'chapter', order: BigInt.zero),
        SagaMembership(
          work: work,
          role: 'appendix',
          order: BigInt.parse('9007199254740997'),
        ),
        SagaMembership(
          work: ref(),
          role: 'reference',
          order: (BigInt.one << 64) - BigInt.one,
        ),
        SagaMembership(work: ref(), role: 'related'),
      ],
    );
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [CreateSagaOperation(clientRef: 'saga', record: record)],
        rationale: 'Retain draft rationale.',
      ),
    );
    final form = UnfinishedSagaForm.fromWire(
      sagaFormFromDraft(draft, 0).toWire(),
    );
    expect(
      sagaOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = form.copyWith(
      title: 'Revised collection',
      memberships: form.memberships.reversed.toList(),
    );
    final request = sagaDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as CreateSagaOperation).record;
    expect(next.title, 'Revised collection');
    expect(next.labels, record.labels);
    expect(
      next.memberships.map((m) => m.toWire().toText()),
      record.memberships.reversed.map((m) => m.toWire().toText()),
    );
    expect(request.content.rationale, draft.content.rationale);
    final dormant = form.memberships[1].copyWith(orderEnabled: false);
    expect(dormant.order, '9007199254740997');
    expect(
      sagaOperation(form.copyWith(memberships: [dormant]))
          .record
          .memberships
          .single
          .order,
      isNull,
    );
    expect(
      () => sagaOperation(
        form.copyWith(
          memberships: [
            form.memberships[0].copyWith(order: '18446744073709551616'),
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => sagaOperation(
        form.copyWith(
          labels: [
            const PropertyLabelInput(language: 'en', text: 'First'),
            const PropertyLabelInput(language: 'en', text: 'Second'),
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => sagaDraftRequest(
        draft: SavedDraft(version: BigInt.from(7), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished saga memberships recover without inventing a work, role or order', () {
    final root = Directory('/tmp').createTempSync('ub-saga-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedSagaForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      title: 'unfinished 記憶 😀',
      memberships: [
        const SagaMembershipInput(order: 'unfinished 9007199254740997'),
      ],
    );
    var store = SagaFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = SagaFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.memberships.single.work.record, isEmpty);
      expect(recovered.memberships.single.role, isEmpty);
      expect(recovered.memberships.single.orderEnabled, isFalse);
      expect(() => sagaOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(title: 'changed'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
