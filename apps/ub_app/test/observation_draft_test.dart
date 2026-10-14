import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/observation_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('observation edits retain exact time false sensory access and separate interpretation', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final record = ObservationRecord(
      observer: ref(),
      observed: ref(),
      sensoryAccess: false,
      time: ExactTime(CalendarId.generate(), '9007199254740997'),
      interpretation: ref(),
      basis: const AuthorDecisionBasis('Reported 記憶 😀'),
    );
    final draft = SavedDraft(
      version: BigInt.from(7),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          RecordObservationOperation(clientRef: 'observation', record: record),
        ],
        rationale: 'Record access without inferring understanding.',
      ),
    );
    final form = UnfinishedObservationForm.fromWire(
      observationFormFromDraft(draft, 0).toWire(),
    );
    expect(
      observationOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = form.copyWith(
      sensoryAccess: true,
      interpretationEnabled: false,
    );
    final request = observationDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as RecordObservationOperation)
            .record;
    expect(next.sensoryAccess, isTrue);
    expect(next.interpretation, isNull);
    expect(next.observed, record.observed);
    expect(next.observer, record.observer);
    expect(
      next.time.encode(canonical: false).toText(),
      record.time.encode(canonical: false).toText(),
    );
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => observationDraftRequest(
        draft: SavedDraft(version: BigInt.from(8), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished observations recover without guessing sensory access', () {
    final root = Directory('/tmp').createTempSync('ub-observation-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedObservationForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      interpretationEnabled: true,
      interpretation: const ExpressionReferenceInput(
        record: 'unfinished 記憶 😀',
      ),
    );
    var store = ObservationFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = ObservationFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.sensoryAccess, isNull);
      expect(() => observationOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () =>
            store.save(scope, form.copyWith(sensoryAccess: false), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
