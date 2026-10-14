import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/scene_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
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
