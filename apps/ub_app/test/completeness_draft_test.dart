import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/completeness_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('completeness editing retains observer identity repeated members and scoped empty declarations', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        observer = RecordId.generate();
    final member = RecordRef(universe: universe, record: RecordId.generate());
    final record = CompletenessRecord(
      subject: RecordRef(universe: universe, record: RecordId.generate()),
      predicate: 'authored:members 記憶 😀',
      members: [member, member],
      completeness: ObserverCompleteness(observer),
      scope: Scope(
        context: RecordRef(universe: universe, record: context),
        applicability: const UniverseApplicability(),
      ),
      validity: const UnknownValidity(),
    );
    final draft = SavedDraft(
      version: BigInt.from(8),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          SetCompletenessOperation(clientRef: 'members', record: record),
        ],
        rationale: 'Retain the authored observer perspective.',
      ),
    );
    final form = UnfinishedCompletenessForm.fromWire(
      completenessFormFromDraft(draft, 0).toWire(),
    );
    expect(
      completenessOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final empty = UnfinishedCompletenessForm(
      baseRevision: form.baseRevision,
      representedContext: context,
      clientRef: form.clientRef,
      subject: form.subject,
      predicate: form.predicate,
      kind: 'objective_reality',
      members: [],
      scope: form.scope,
      validity: form.validity,
      original: form.original,
      draftVersion: form.draftVersion,
    );
    final request = completenessDraftRequest(
      draft: draft,
      form: empty,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final changed =
        (request.content.operations.single as SetCompletenessOperation).record;
    expect(changed.members, isEmpty);
    expect(changed.completeness, isA<ObjectiveCompleteness>());
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => completenessDraftRequest(
        draft: SavedDraft(version: BigInt.from(9), content: draft.content),
        form: empty,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished completeness input survives restart without inferring objective completeness', () {
    final root = Directory('/tmp').createTempSync('ub-completeness-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedCompletenessForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      predicate: 'unfinished 記憶 😀',
      members: [const ExpressionReferenceInput(record: 'unfinished member')],
    );
    var store = CompletenessFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = CompletenessFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.kind, isEmpty);
      expect(recovered.members.single.record, 'unfinished member');
      expect(() => completenessOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
