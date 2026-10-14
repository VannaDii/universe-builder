import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/passage_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'passage edits retain the exact edition pin and explicit optional anchor',
    () {
      final universe = UniverseId.generate(), context = RecordId.generate();
      for (final qualified in [false, true]) {
        final record = PassageRecord(
          workVersion: VersionRef(
            universe: qualified ? universe : null,
            record: RecordId.generate(),
            version: RecordVersionId.generate(),
          ),
          passageId: 'Chapter 3 記憶 😀',
          anchor: RecordRef(
            universe: qualified ? universe : null,
            record: RecordId.generate(),
          ),
        );
        final op = RecordNarrativeReferenceOperation(
          clientRef: 'passage',
          record: RecordKind.passageRef,
          payload: record,
        );
        final draft = SavedDraft(
          version: BigInt.two,
          content: DraftContent(
            baseRevision: RevisionId.generate(),
            representedContext: context,
            operations: [op],
            rationale: 'Retain rationale.',
          ),
        );
        final form = UnfinishedPassageForm.fromWire(
          passageFormFromDraft(draft, 0).toWire(),
        );
        expect(passageOperation(form).toWire().toText(), op.toWire().toText());
        final changed = form.copyWith(
          passageId: 'Chapter 4',
          anchorEnabled: false,
        );
        final request = passageDraftRequest(
          draft: draft,
          form: changed,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        );
        final next =
            (request.content.operations.single
                        as RecordNarrativeReferenceOperation)
                    .payload
                as PassageRecord;
        expect(next.workVersion, record.workVersion);
        expect(next.passageId, 'Chapter 4');
        expect(next.anchor, isNull);
        expect(request.content.rationale, draft.content.rationale);
        expect(
          () => passageDraftRequest(
            draft: SavedDraft(version: BigInt.from(3), content: draft.content),
            form: changed,
            universe: const Selector('Universe'),
            continuity: ContinuityId.generate(),
            index: 0,
          ),
          throwsFormatException,
        );
        final empty = SavedDraft(
          version: BigInt.one,
          content: DraftContent(
            baseRevision: form.baseRevision,
            representedContext: context,
            operations: [],
            rationale: '',
          ),
        );
        final added = passageDraftRequest(
          draft: empty,
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
        );
        final saved = SavedDraft(version: BigInt.two, content: added.content);
        expect(
          passageDraftRequest(
            draft: saved,
            form: form,
            universe: const Selector('Universe'),
            continuity: ContinuityId.generate(),
          ).content.operations.length,
          1,
        );
        expect(
          () => passageDraftRequest(
            draft: saved,
            form: changed,
            universe: const Selector('Universe'),
            continuity: ContinuityId.generate(),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('unfinished passage recovers exact text and an unselected anchor without creating one', () {
    final root = Directory('/tmp').createTempSync('ub-passage-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedPassageForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      passageId: 'unfinished 記憶 😀',
      edition: const ExpressionReferenceInput(record: 'unfinished edition'),
      editionVersion: 'unfinished version',
      anchorEnabled: true,
      anchor: const ExpressionReferenceInput(record: 'unfinished anchor'),
    );
    var store = PassageFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = PassageFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(() => passageOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(passageId: 'Other'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
