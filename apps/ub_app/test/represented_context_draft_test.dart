import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/represented_context_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('context edits preserve every kind parent labels and exact authored chronology', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    final ref = RecordRef(universe: universe, record: RecordId.generate());
    for (final kind in <RepresentedContextKind>[
      const ObjectiveContext(),
      CharacterContext(ref),
      SourceContext(ref),
      NarratorContext(ref),
      const AuthoredContext('Dream 記憶 😀'),
    ]) {
      final record = RepresentedContextRecord(
        universe: universe,
        kind: kind,
        parent: ref,
        labels: {'en': 'Context', '': '記憶 😀'},
        chronology: Chronology(
          calendar: calendar,
          system: FictionalClock('ticks', 4294967295),
          firstInteraction: '0',
          current: '9007199254740997',
        ),
      );
      final draft = SavedDraft(
        version: BigInt.from(6),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          operations: [
            RecordNarrativeReferenceOperation(
              clientRef: 'context',
              record: RecordKind.representedContext,
              payload: record,
            ),
          ],
          rationale: 'Retain the represented account.',
        ),
      );
      final form = UnfinishedRepresentedContextForm.fromWire(
        representedContextFormFromDraft(draft, 0).toWire(),
      );
      expect(
        representedContextOperation(form).payload.toWire().toText(),
        record.toWire().toText(),
      );
      final request = representedContextDraftRequest(
        draft: draft,
        form: form.copyWith(
          parentEnabled: false,
          chronology: form.chronology.copyWith(enabled: false),
        ),
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final next =
          (request.content.operations.single
                      as RecordNarrativeReferenceOperation)
                  .payload
              as RepresentedContextRecord;
      expect(next.parent, isNull);
      expect(next.chronology, isNull);
      expect(next.kind.toWire().toText(), kind.toWire().toText());
      expect(next.labels, record.labels);
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => representedContextDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    }
    final record = RepresentedContextRecord(
      universe: universe,
      kind: const ObjectiveContext(),
      labels: {},
      chronology: Chronology(
        calendar: calendar,
        system: GregorianClock(59),
        firstInteraction: '2208988800',
        current: '2208988890',
      ),
    );
    final draft = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          RecordNarrativeReferenceOperation(
            clientRef: 'clock',
            record: RecordKind.representedContext,
            payload: record,
          ),
        ],
        rationale: '',
      ),
    );
    final form = representedContextFormFromDraft(draft, 0);
    expect(
      representedContextOperation(form).payload.toWire().toText(),
      record.toWire().toText(),
    );
    final edited = representedContextOperation(
      form.copyWith(
        chronology: form.chronology.copyWith(current: '2040-01-01T00:10:00Z'),
      ),
    );
    final after = (edited.payload as RepresentedContextRecord).chronology!;
    expect(after.firstInteraction, record.chronology!.firstInteraction);
    expect(after.current, '2208989400');
    expect((after.system as GregorianClock).offsetSeconds, 59);
  });
  test('unfinished context kind labels and clocks recover without fabricating parent or time', () {
    final root = Directory('/tmp').createTempSync('ub-context-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedRepresentedContextForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      universe: scope.universe,
      clientRef: RecordId.generate().value,
      labels: [
        const PropertyLabelInput(language: '', text: 'unfinished 記憶 😀'),
      ],
      chronology: const ChronologyInput(
        enabled: true,
        system: 'fictional',
        current: 'unfinished tick',
      ),
    );
    var store = RepresentedContextFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = RepresentedContextFormRecoveryStore.open(
        '${root.path}/forms.sqlite',
      );
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.kind, isEmpty);
      expect(recovered.parentEnabled, isFalse);
      expect(recovered.chronology.firstInteraction, isEmpty);
      expect(
        () => representedContextOperation(recovered),
        throwsFormatException,
      );
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(kind: 'authored'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
