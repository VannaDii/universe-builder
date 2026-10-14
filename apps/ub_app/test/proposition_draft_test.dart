import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/proposition_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('proposition edits preserve context quantification exact value and repeated role order', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final participant = ref();
    final record = PropositionRecord(
      predicate: ref(),
      subject: ref(),
      context: ref(),
      roles: [
        PropositionRole('listener', participant),
        PropositionRole('listener', participant),
      ],
      quantification: Quantification.exists,
      value: IntegerValue('9007199254740997'),
    );
    final draft = SavedDraft(
      version: BigInt.from(5),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          DefinePropositionOperation(clientRef: 'claim', record: record),
        ],
        rationale: 'Define a claim without asserting it.',
      ),
    );
    final form = UnfinishedPropositionForm.fromWire(
      propositionFormFromDraft(draft, 0).toWire(),
    );
    expect(
      propositionOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = UnfinishedPropositionForm(
      baseRevision: form.baseRevision,
      representedContext: context,
      clientRef: form.clientRef,
      subject: form.subject,
      predicate: form.predicate,
      context: form.context,
      roles: form.roles,
      quantification: 'universal',
      hasValue: false,
      value: form.value,
      original: form.original,
      draftVersion: form.draftVersion,
    );
    final request = propositionDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as DefinePropositionOperation)
            .record;
    expect(next.value, isNull);
    expect(next.quantification, Quantification.universal);
    expect(next.roles, record.roles);
    expect(next.context, record.context);
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => propositionDraftRequest(
        draft: SavedDraft(version: BigInt.from(6), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished proposition fields recover exactly without inferring a quantification', () {
    final root = Directory('/tmp').createTempSync('ub-proposition-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedPropositionForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      subject: const ExpressionReferenceInput(record: 'unfinished'),
      roles: [const PropositionRoleInput(role: 'listener 記憶 😀')],
      hasValue: true,
      value: const QualifierInput(
        kind: 'rational',
        value: '7',
        denominator: '',
      ),
    );
    var store = PropositionFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = PropositionFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.quantification, isEmpty);
      expect(() => propositionOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(
          scope,
          UnfinishedPropositionForm(
            baseRevision: form.baseRevision,
            representedContext: form.representedContext,
            clientRef: form.clientRef,
            rationale: 'Competing edit',
          ),
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
