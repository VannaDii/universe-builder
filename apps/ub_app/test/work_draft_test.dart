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
  test('published work associations retain identity, version, validity and qualifiers through edits', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        base = RevisionId.generate();
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.work,
      ),
      payload: WorkRecord(
        kind: WorkKind.novel,
        title: 'Published work',
        labels: {},
        sourceRefs: [],
        versions: [],
        worldAssociations: [],
      ),
    );
    final world = WorldId.generate(), calendar = CalendarId.generate();
    final association = WorldAssociation(
      world: world,
      role: 'Referenced',
      validity: InstantValidity(ExactTime(calendar, '9007199254740997')),
      qualifiers: {
        'count': IntegerValue('9007199254740997'),
        'range': RangeValue(
          lower: const RationalValue('1', '3'),
          upper: const RationalValue('2', '3'),
          lowerInclusive: true,
          upperInclusive: false,
        ),
      },
    );
    final form =
        workAssociationFormFromRecord(
          record: source,
          baseRevision: base,
          representedContext: context,
        ).copyWith(
          associations: [
            WorkAssociationInput(
              world: world.value,
              role: 'Referenced',
              qualifiers: [
                const QualifierInput(
                  key: 'count',
                  kind: 'integer',
                  value: '9007199254740997',
                ),
              ],
            ),
          ],
        );
    final draft = SavedDraft(
      version: BigInt.from(2),
      content: DraftContent(
        baseRevision: base,
        representedContext: context,
        operations: [
          AssociateWorkWorldOperation(
            record: RecordRef(
              universe: universe,
              record: source.identity.recordId,
            ),
            expectedVersion: source.recordVersionId,
            association: association,
          ),
        ],
        rationale: 'Association review.',
      ),
    );
    final recovered = UnfinishedWorkForm.fromWire(
      workFormFromDraft(draft, 0).toWire(),
    );
    expect(
      workAssociationOperation(recovered).association.toWire().toText(),
      association.toWire().toText(),
    );
    final changed = recovered.copyWith(
      associations: [recovered.associations.single.copyWith(role: 'Featured')],
    );
    final request = workDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        request.content.operations.single as AssociateWorkWorldOperation;
    expect(next.record.record, source.identity.recordId);
    expect(next.record.universe, universe);
    expect(next.expectedVersion, source.recordVersionId);
    expect(next.association.role, 'Featured');
    expect(
      next.association.validity.toWire().toText(),
      association.validity.toWire().toText(),
    );
    expect(
      next.association.qualifiers.map(
        (k, v) => MapEntry(k, v.toWire().toText()),
      ),
      association.qualifiers.map((k, v) => MapEntry(k, v.toWire().toText())),
    );
    expect(() => workOperation(form), throwsFormatException);
    final empty = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: base,
        representedContext: context,
        operations: [],
        rationale: 'Add association.',
      ),
    );
    final add = workDraftRequest(
      draft: empty,
      form: form,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
    );
    final saved = SavedDraft(version: BigInt.from(2), content: add.content);
    expect(
      workDraftRequest(
        draft: saved,
        form: form,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      ).content.operations.length,
      1,
    );
    expect(
      () => workDraftRequest(
        draft: SavedDraft(version: BigInt.from(3), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    final alteredPin = UnfinishedWorkForm.fromWire(
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
      () => workDraftRequest(
        draft: draft,
        form: alteredPin,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('published work association input recovers under its target without choosing a world', () {
    final root = Directory('/tmp').createTempSync('ub-work-association-form-');
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
        recordKind: RecordKind.work,
      ),
      payload: WorkRecord(
        kind: WorkKind.story,
        title: 'Work',
        labels: {},
        sourceRefs: [],
        versions: [],
        worldAssociations: [],
      ),
    );
    final form =
        workAssociationFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        ).copyWith(
          associations: [
            WorkAssociationInput(
              role: 'unfinished 記憶 😀',
              qualifiers: [
                const QualifierInput(
                  key: 'count',
                  kind: 'integer',
                  value: 'unfinished 9007199254740997',
                ),
              ],
            ),
          ],
        );
    var store = WorkFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = WorkFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.expectedRecordVersion, source.recordVersionId);
      expect(recovered.associationTarget!.record, recordId.value);
      expect(recovered.associations.single.world, isEmpty);
      expect(() => workAssociationOperation(recovered), throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
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
