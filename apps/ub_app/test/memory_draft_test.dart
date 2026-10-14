import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/memory_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('memory edits preserve remembered and alleged links exact validity and authored accessibility', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final record = MemoryRecord(
      holder: ref(),
      content: ref(),
      alleged: ref(),
      accessibility: 'Fragmented 記憶 😀',
      altered: true,
      validity: InstantValidity(
        ExactTime(CalendarId.generate(), '9007199254740997'),
      ),
    );
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          RecordMemoryOperation(clientRef: 'recollection', record: record),
        ],
        rationale: 'Retain a recollection without promoting it to truth.',
      ),
    );
    final form = UnfinishedMemoryForm.fromWire(
      memoryFormFromDraft(draft, 0).toWire(),
    );
    expect(
      memoryOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = form.copyWith(
      allegedEnabled: false,
      altered: false,
      accessibility: 'Accessible with prompting',
    );
    final request = memoryDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as RecordMemoryOperation).record;
    expect(next.alleged, isNull);
    expect(next.altered, isFalse);
    expect(next.accessibility, 'Accessible with prompting');
    expect(next.holder, record.holder);
    expect(next.content, record.content);
    expect(next.validity.toWire().toText(), record.validity.toWire().toText());
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => memoryDraftRequest(
        draft: SavedDraft(version: BigInt.from(7), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished memories recover without assuming unaltered content or an alleged event', () {
    final root = Directory('/tmp').createTempSync('ub-memory-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedMemoryForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      accessibility: 'unfinished 記憶 😀',
      content: const ExpressionReferenceInput(record: 'unfinished claim'),
    );
    var store = MemoryFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = MemoryFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.altered, isNull);
      expect(recovered.allegedEnabled, isFalse);
      expect(() => memoryOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(altered: false), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
