@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_scene_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser scenes retain exact original positions, narration, disclosure order and pending associations', () async {
    final name = 'ub-scene-test-${OperationId.generate().value}';
    var store = await BrowserSceneFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final original = SceneRecord(
      workVersion: VersionRef(
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
      ),
      sceneId: 'Original',
      viewpoint: ref(),
      narrationFrame: ref(),
      narrativePosition: BigInt.parse('9007199254740993'),
      disclosedRecords: [ref(), ref()],
      depictedEvents: [ref(), ref()],
      worldAssociations: [
        WorldAssociation(
          world: WorldId.generate(),
          role: 'Setting',
          validity: UnspecifiedValidity(),
          qualifiers: {'count': IntegerValue('9007199254740993123456789')},
        ),
      ],
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final input = UnfinishedSceneForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      sceneId: 'Opening 記憶 😀\r\n',
      edition: ExpressionReferenceInput(
        record: original.workVersion.record.value,
        universe: '',
      ),
      editionVersion: original.workVersion.version.value,
      viewpointEnabled: true,
      viewpoint: ExpressionReferenceInput(record: 'unresolved viewpoint'),
      narrationEnabled: true,
      narration: ExpressionReferenceInput(record: 'unresolved narration'),
      positionEnabled: true,
      position: '9007199254740993123456789',
      disclosed: [
        ExpressionReferenceInput(record: 'fact'),
        ExpressionReferenceInput(),
        ExpressionReferenceInput(record: 'fact'),
        ExpressionReferenceInput(record: 'other'),
      ],
      depicted: [
        ExpressionReferenceInput(record: 'event'),
        ExpressionReferenceInput(record: 'other event'),
      ],
      associations: [
        WorkAssociationInput(
          world: 'world',
          role: 'Setting',
          originalOrdinal: 2,
          validity: TemporalValidityInput(
            start: TemporalBoundInput(value: 'unfinished-'),
          ),
          qualifiers: [
            QualifierInput(kind: 'rational', value: '003', denominator: '02'),
          ],
        ),
        WorkAssociationInput(world: '', role: ''),
      ],
      original: original,
      correctionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserSceneFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = input.copyWith(
        disclosed: input.disclosed.reversed.toList(),
        depicted: input.depicted.reversed.toList(),
        associations: input.associations.reversed.toList(),
      );
      await expectLater(
        store.save(scope, reversed, BigInt.zero),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      await store.save(scope, reversed, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        reversed.toWire().toText(),
      );
      final disabled = input.copyWith(
        viewpointEnabled: false,
        narrationEnabled: false,
        positionEnabled: false,
        disclosed: [],
        depicted: [],
        associations: [],
      );
      await store.save(scope, disabled, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      await expectLater(
        store.save(scope, disabled.copyWith(sceneId: '\uD800'), BigInt.from(3)),
        throwsFormatException,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      final other = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: universe,
        continuity: scope.continuity,
        representedContext: context,
        typeClientRef: 'different',
      );
      expect(await store.load(other), isNull);
      await expectLater(
        store.save(other, input, BigInt.zero),
        throwsFormatException,
      );
    } finally {
      store.close();
      final deleted = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => deleted.complete()).toJS;
      request.onerror = ((web.Event _) => deleted.completeError(
        StateError('Test cleanup failed'),
      )).toJS;
      await deleted.future;
    }
  });
}
