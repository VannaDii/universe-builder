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
  test(
    'published membership changes retain saga identity and expected version',
    () {
      final universe = UniverseId.generate(),
          context = RecordId.generate(),
          base = RevisionId.generate();
      final source = RecordVersion.build(
        recordVersionId: RecordVersionId.generate(),
        identity: RecordIdentity(
          universeId: universe,
          recordId: RecordId.generate(),
          recordKind: RecordKind.saga,
        ),
        payload: SagaRecord(
          title: 'Published saga',
          labels: {'en': 'Saga'},
          memberships: [],
        ),
      );
      final member = SagaMembershipInput(
        work: ExpressionReferenceInput(
          record: RecordId.generate().value,
          universe: universe.value,
        ),
        role: 'chapter',
        orderEnabled: true,
        order: '9007199254740997',
      );
      final form = UnfinishedSagaForm.fromWire(
        sagaMembershipFormFromRecord(
          record: source,
          baseRevision: base,
          representedContext: context,
        ).copyWith(memberships: [member]).toWire(),
      );
      final draft = SavedDraft(
        version: BigInt.from(2),
        content: DraftContent(
          baseRevision: base,
          representedContext: context,
          operations: [],
          rationale: 'Set membership.',
        ),
      );
      final request = sagaDraftRequest(
        draft: draft,
        form: form,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      );
      final op =
          request.content.operations.single as SetSagaMembershipOperation;
      expect(op.record.record, source.identity.recordId);
      expect(op.record.universe, universe);
      expect(op.expectedVersion, source.recordVersionId);
      expect(op.membership.order.toString(), '9007199254740997');
      expect(() => sagaOperation(form), throwsFormatException);
      final saved = SavedDraft(
        version: BigInt.from(3),
        content: request.content,
      );
      expect(
        sagaDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
        ).content.operations.length,
        1,
      );
      final editable = sagaFormFromDraft(saved, 0);
      final changed = editable.copyWith(
        memberships: [
          editable.memberships.single.copyWith(
            role: 'appendix',
            orderEnabled: false,
          ),
        ],
      );
      final edit = sagaDraftRequest(
        draft: saved,
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final next = edit.content.operations.single as SetSagaMembershipOperation;
      expect(next.record, op.record);
      expect(next.expectedVersion, op.expectedVersion);
      expect(next.membership.work, op.membership.work);
      expect(next.membership.role, 'appendix');
      expect(next.membership.order, isNull);
      expect(
        () => sagaDraftRequest(
          draft: SavedDraft(version: BigInt.from(4), content: saved.content),
          form: changed,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
      final alteredPin = UnfinishedSagaForm.fromWire(
        CanonicalObject(
          changed.toWire().fields.map(
            (e) => e.key == 'expected_record_version'
                ? MapEntry(
                    e.key,
                    CanonicalString(RecordVersionId.generate().value),
                  )
                : e,
          ),
        ),
      );
      expect(
        () => sagaDraftRequest(
          draft: saved,
          form: alteredPin,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    },
  );
  test('published saga membership input recovers under its target without inventing a pair', () {
    final root = Directory('/tmp').createTempSync('ub-saga-membership-form-');
    final universe = UniverseId.generate(),
        recordId = RecordId.generate(),
        context = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: recordId.value,
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: recordId,
        recordKind: RecordKind.saga,
      ),
      payload: SagaRecord(title: 'Saga', labels: {}, memberships: []),
    );
    final form =
        sagaMembershipFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        ).copyWith(
          memberships: [
            const SagaMembershipInput(
              orderEnabled: true,
              order: 'unfinished 9007199254740997 記憶 😀',
            ),
          ],
        );
    var store = SagaFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = SagaFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.expectedRecordVersion, source.recordVersionId);
      expect(recovered.membershipTarget!.record, recordId.value);
      expect(recovered.memberships.single.role, isEmpty);
      expect(() => sagaMembershipOperation(recovered), throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
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
