import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/scene_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('published scene correction retains identity, edition and worlds through pending edits', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        base = RevisionId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final disclosure = ref(), event = ref();
    final payload = SceneRecord(
      workVersion: VersionRef(
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
      ),
      sceneId: 'Opening',
      viewpoint: ref(),
      narrationFrame: ref(),
      narrativePosition: BigInt.zero,
      disclosedRecords: [disclosure, disclosure],
      depictedEvents: [event, event],
      worldAssociations: [
        WorldAssociation(
          world: WorldId.generate(),
          role: 'Setting',
          validity: const UnspecifiedValidity(),
          qualifiers: {
            'amount': IntegerValue('9007199254740997'),
            'range': RangeValue(
              lower: const RationalValue('1', '3'),
              upper: const RationalValue('2', '3'),
              lowerInclusive: true,
              upperInclusive: false,
            ),
          },
        ),
      ],
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.sceneRef,
      ),
      payload: payload,
    );
    final form =
        sceneCorrectionFormFromRecord(
          record: source,
          baseRevision: base,
          representedContext: context,
        ).copyWith(
          narrationEnabled: false,
          position: '9007199254740997',
          rationale: 'Correct the reader order.',
        );
    final empty = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: base,
        representedContext: context,
        operations: [],
        rationale: '',
      ),
    );
    final add = sceneDraftRequest(
      draft: empty,
      form: form,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
    );
    final saved = SavedDraft(version: BigInt.two, content: add.content);
    final recovered = UnfinishedSceneForm.fromWire(
      sceneFormFromDraft(saved, 0).toWire(),
    );
    expect(
      sceneCorrectionOperation(recovered).toWire().toText(),
      sceneCorrectionOperation(form).toWire().toText(),
    );
    final changed = recovered.copyWith(
      viewpointEnabled: false,
      depicted: recovered.depicted.reversed.toList(),
      position: '9007199254740999',
    );
    final edited = sceneDraftRequest(
      draft: saved,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final operation = edited.content.operations.single as ReviseSceneOperation;
    expect(operation.record.record, source.identity.recordId);
    expect(operation.expectedVersion, source.recordVersionId);
    expect(operation.replacement.workVersion, payload.workVersion);
    expect(operation.replacement.sceneId, payload.sceneId);
    expect(
      operation.replacement.worldAssociations.map((a) => a.toWire().toText()),
      payload.worldAssociations.map((a) => a.toWire().toText()),
    );
    expect(operation.replacement.viewpoint, isNull);
    expect(operation.replacement.narrationFrame, isNull);
    expect(
      operation.replacement.narrativePosition,
      BigInt.parse('9007199254740999'),
    );
    expect(operation.replacement.disclosedRecords, payload.disclosedRecords);
    expect(
      () => sceneCorrectionOperation(form.copyWith(sceneId: 'Different')),
      throwsFormatException,
    );
    expect(
      () => sceneCorrectionOperation(
        form.copyWith(editionVersion: RecordVersionId.generate().value),
      ),
      throwsFormatException,
    );
    expect(
      () => sceneCorrectionOperation(form.copyWith(associations: [])),
      throwsFormatException,
    );
    expect(
      () => sceneDraftRequest(
        draft: SavedDraft(version: BigInt.from(3), content: saved.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    expect(
      sceneDraftRequest(
        draft: saved,
        form: form,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      ).content.operations.length,
      1,
    );
    expect(
      () => sceneDraftRequest(
        draft: saved,
        form: form.copyWith(position: '3'),
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      ),
      throwsFormatException,
    );
    final alteredPin = UnfinishedSceneForm.fromWire(
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
      () => sceneDraftRequest(
        draft: saved,
        form: alteredPin,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('published scene correction recovers under its exact target and expected version', () {
    final root = Directory('/tmp').createTempSync('ub-scene-correction-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.sceneRef,
      ),
      payload: SceneRecord(
        workVersion: VersionRef(
          record: RecordId.generate(),
          version: RecordVersionId.generate(),
        ),
        sceneId: 'Opening',
        depictedEvents: [],
        worldAssociations: [],
      ),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    final form =
        sceneCorrectionFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        ).copyWith(
          positionEnabled: true,
          position: 'unfinished 9007199254740997',
          rationale: 'unfinished 記憶 😀',
        );
    var store = SceneFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = SceneFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.expectedRecordVersion, source.recordVersionId);
      expect(
        recovered.correctionTarget!.record,
        source.identity.recordId.value,
      );
      expect(() => sceneCorrectionOperation(recovered), throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('scene edits preserve edition pin, optional values and ordered associations', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final disclosure = ref(), event = ref(), calendar = CalendarId.generate();
    for (final position in [
      null,
      BigInt.zero,
      BigInt.parse('9007199254740997'),
      (BigInt.one << 64) - BigInt.one,
    ]) {
      final record = SceneRecord(
        workVersion: VersionRef(
          record: RecordId.generate(),
          version: RecordVersionId.generate(),
        ),
        sceneId: 'Opening 記憶 😀',
        viewpoint: ref(),
        narrationFrame: ref(),
        narrativePosition: position,
        disclosedRecords: [
          disclosure,
          disclosure,
          RecordRef(record: RecordId.generate()),
        ],
        depictedEvents: [event, event, ref()],
        worldAssociations: [
          WorldAssociation(
            world: WorldId.generate(),
            role: 'Setting',
            validity: InstantValidity(ExactTime(calendar, '9007199254740997')),
            qualifiers: {
              'count': IntegerValue('9007199254740997'),
              'detail': const TextValue('記憶 😀'),
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
          operations: [
            RecordNarrativeReferenceOperation(
              clientRef: 'scene',
              record: RecordKind.sceneRef,
              payload: record,
            ),
          ],
          rationale: 'Retain rationale.',
        ),
      );
      final form = UnfinishedSceneForm.fromWire(
        sceneFormFromDraft(draft, 0).toWire(),
      );
      expect(
        sceneOperation(form).payload.toWire().toText(),
        record.toWire().toText(),
      );
      final changed = form.copyWith(
        sceneId: 'Revised',
        viewpointEnabled: false,
        narrationEnabled: false,
        positionEnabled: false,
        disclosed: form.disclosed.reversed.toList(),
        depicted: form.depicted.reversed.toList(),
        associations: form.associations.reversed.toList(),
      );
      final request = sceneDraftRequest(
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
              as SceneRecord;
      expect(
        next.workVersion.toCanonical().toText(),
        record.workVersion.toCanonical().toText(),
      );
      expect(next.viewpoint, isNull);
      expect(next.narrationFrame, isNull);
      expect(next.narrativePosition, isNull);
      expect(next.disclosedRecords, record.disclosedRecords.reversed);
      expect(next.depictedEvents, record.depictedEvents.reversed);
      expect(
        next.worldAssociations.map((a) => a.toWire().toText()),
        record.worldAssociations.reversed.map((a) => a.toWire().toText()),
      );
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => sceneDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: changed,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => sceneOperation(
          form.copyWith(
            positionEnabled: true,
            position: '18446744073709551616',
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'unfinished scene recovers exact input without inferring optional fields',
    () {
      final root = Directory('/tmp').createTempSync('ub-scene-form-');
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        representedContext: RecordId.generate(),
      );
      final form = UnfinishedSceneForm(
        baseRevision: RevisionId.generate(),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        sceneId: 'unfinished 記憶 😀',
        edition: const ExpressionReferenceInput(record: 'unfinished edition'),
        editionVersion: 'unfinished version',
        position: 'unfinished 9007199254740997',
        disclosed: [
          const ExpressionReferenceInput(record: 'unfinished disclosure'),
        ],
        associations: [
          WorkAssociationInput(
            role: 'Setting',
            qualifiers: [
              const QualifierInput(
                key: 'count',
                kind: 'integer',
                value: 'unfinished',
              ),
            ],
          ),
        ],
      );
      var store = SceneFormRecoveryStore.open('${root.path}/forms.sqlite');
      try {
        store.save(scope, form, BigInt.zero);
        store.close();
        store = SceneFormRecoveryStore.open('${root.path}/forms.sqlite');
        final recovered = store.load(scope)!.form;
        expect(recovered.toWire().toText(), form.toWire().toText());
        expect(recovered.viewpointEnabled, isFalse);
        expect(recovered.narrationEnabled, isFalse);
        expect(recovered.positionEnabled, isFalse);
        expect(() => sceneOperation(recovered), throwsFormatException);
        expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
        expect(
          () => store.save(scope, form.copyWith(sceneId: 'Other'), BigInt.zero),
          throwsA(isA<EditorRecoveryException>()),
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
