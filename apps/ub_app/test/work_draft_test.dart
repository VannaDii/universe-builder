import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/work_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('work edits retain every kind, ordered source and edition links, and exact associations', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final source = ref(),
        edition = RecordId.generate(),
        calendar = CalendarId.generate();
    for (final kind in WorkKind.values) {
      final record = WorkRecord(
        kind: kind,
        title: 'Chronicle 記憶 😀',
        labels: {'': 'Original title', 'en': 'Chronicle'},
        sourceRefs: [source, source, ref()],
        versions: [edition, edition, RecordId.generate()],
        worldAssociations: [
          WorldAssociation(
            world: WorldId.generate(),
            role: 'Setting',
            validity: InstantValidity(ExactTime(calendar, '9007199254740997')),
            qualifiers: {
              'count': IntegerValue('9007199254740997'),
              'detail': const TextValue('Full account 記憶 😀'),
            },
          ),
          WorldAssociation(
            world: WorldId.generate(),
            role: 'Mentioned',
            validity: const UnknownValidity(),
            qualifiers: {'explicit': const BooleanValue(false)},
          ),
        ],
      );
      final draft = SavedDraft(
        version: BigInt.from(6),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          operations: [CreateWorkOperation(clientRef: 'work', record: record)],
          rationale: 'Retain draft rationale.',
        ),
      );
      final form = UnfinishedWorkForm.fromWire(
        workFormFromDraft(draft, 0).toWire(),
      );
      expect(
        workOperation(form).record.toWire().toText(),
        record.toWire().toText(),
      );
      final changed = form.copyWith(
        title: 'Revised title',
        kind: 'other',
        sources: form.sources.reversed.toList(),
        associations: form.associations.reversed.toList(),
      );
      final request = workDraftRequest(
        draft: draft,
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final next =
          (request.content.operations.single as CreateWorkOperation).record;
      expect(next.title, 'Revised title');
      expect(next.kind, WorkKind.other);
      expect(next.labels, record.labels);
      expect(next.sourceRefs, record.sourceRefs.reversed);
      expect(next.versions, record.versions);
      expect(
        next.worldAssociations.map((a) => a.toWire().toText()),
        record.worldAssociations.reversed.map((a) => a.toWire().toText()),
      );
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => workOperation(
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
        () => workDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: changed,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    }
  });
  test('unfinished work fields recover without inventing a kind or completing a world association', () {
    final root = Directory('/tmp').createTempSync('ub-work-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedWorkForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      title: 'unfinished 記憶 😀',
      associations: [
        WorkAssociationInput(
          role: 'setting',
          qualifiers: [
            const QualifierInput(
              key: 'amount',
              kind: 'integer',
              value: '900719925474099',
            ),
          ],
        ),
      ],
      sources: [const ExpressionReferenceInput(record: 'unfinished source')],
    );
    var store = WorkFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = WorkFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.kind, isEmpty);
      expect(() => workOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(kind: 'novel'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
