import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/commitment_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('commitments retain party role order nested conditions and exact optional deadline', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final first = ref(), second = ref();
    final record = CommitmentRecord(
      parties: [
        CommitmentParty(first, 'promisor'),
        CommitmentParty(second, 'witness 記憶 😀'),
        CommitmentParty(second, 'witness 記憶 😀'),
      ],
      obligated: ref(),
      conditions: [
        AllExpr([const LiteralExpr(true), const LiteralExpr(false)]),
      ],
      deadline: ExactTime(CalendarId.generate(), '9007199254740997'),
      status: CommitmentStatus.unfulfilled,
    );
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          RecordCommitmentOperation(clientRef: 'promise', record: record),
        ],
        rationale: 'Keep the promise distinct from an automatic consequence.',
      ),
    );
    final form = UnfinishedCommitmentForm.fromWire(
      commitmentFormFromDraft(draft, 0).toWire(),
    );
    expect(
      commitmentOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = form.copyWith(
      deadlineEnabled: false,
      status: 'breached',
      parties: form.parties.reversed.toList(),
    );
    final request = commitmentDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as RecordCommitmentOperation).record;
    expect(next.deadline, isNull);
    expect(next.status, CommitmentStatus.breached);
    expect(
      next.parties.map((p) => p.toWire().toText()),
      record.parties.reversed.map((p) => p.toWire().toText()),
    );
    expect(
      next.conditions.single.toWire().toText(),
      record.conditions.single.toWire().toText(),
    );
    expect(next.obligated, record.obligated);
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => commitmentDraftRequest(
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
    'unfinished commitments recover without inferred fulfillment or a deadline',
    () {
      final root = Directory('/tmp').createTempSync('ub-commitment-form-');
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        representedContext: RecordId.generate(),
      );
      final form = UnfinishedCommitmentForm(
        baseRevision: RevisionId.generate(),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        parties: [const CommitmentPartyInput(role: 'unfinished role 記憶 😀')],
        conditions: [
          ExpressionInput(kind: 'all', items: [ExpressionInput()]),
        ],
      );
      var store = CommitmentFormRecoveryStore.open('${root.path}/forms.sqlite');
      try {
        store.save(scope, form, BigInt.zero);
        store.close();
        store = CommitmentFormRecoveryStore.open('${root.path}/forms.sqlite');
        final recovered = store.load(scope)!.form;
        expect(recovered.toWire().toText(), form.toWire().toText());
        expect(recovered.status, isEmpty);
        expect(recovered.deadlineEnabled, isFalse);
        expect(() => commitmentOperation(recovered), throwsFormatException);
        expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
        expect(
          () => store.save(
            scope,
            form.copyWith(status: 'fulfilled'),
            BigInt.zero,
          ),
          throwsA(isA<EditorRecoveryException>()),
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
