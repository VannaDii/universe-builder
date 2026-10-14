@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_type_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser type revisions retain original definitions, versions and ordered choices through reopen and conflict', () async {
    final name = 'ub-type-test-${OperationId.generate().value}';
    var store = await BrowserTypeFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final worlds = [WorldId.generate(), WorldId.generate()];
    final original = EntityTypeRecord(
      namespace: 'authored',
      key: 'person',
      labels: {'ja': '人物 😀', '': ''},
      name: '',
      parent: RecordId.generate(),
      parentResolution: ParentResolution.resolved,
      applicability: ConditionalApplicability(),
      classificationExecutable: false,
    );
    final revision = RevisionId.generate(),
        version = RecordVersionId.generate();
    UnfinishedTypeForm form({
      String label = 'Mémoire 😀\r\n',
      bool? executable,
      bool clearChildren = false,
    }) => UnfinishedTypeForm(
      baseRevision: revision,
      representedContext: context,
      clientRef: record.value,
      namespace: 'authored',
      key: 'person',
      name: label,
      parentChoice: 'unresolved choice',
      applicabilityChoice: 'worlds',
      rationale: '',
      classificationExecutable: executable,
      worlds: clearChildren ? [] : [worlds[0], worlds[1], worlds[0]],
      revisionTarget: RecordRef(universe: universe, record: record),
      expectedRecordVersion: version,
      original: original,
      parentResolution: 'ambiguous',
      labels: clearChildren
          ? []
          : [
              PropertyLabelInput(language: 'fr', text: 'Monde'),
              PropertyLabelInput(language: 'fr', text: 'Autre'),
              PropertyLabelInput(language: '', text: ''),
            ],
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      final input = form();
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      store.close();
      store = await BrowserTypeFormRecoveryStore.open(databaseName: name);
      final recovered = (await store.load(scope))!.form;
      expect(recovered.toWire().toText(), input.toWire().toText());
      expect(recovered.original!.toWire().toText(), original.toWire().toText());
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      await expectLater(
        store.save(scope, form(label: 'Conflicting edit'), BigInt.zero),
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
      final changed = form(executable: false, clearChildren: true);
      expect(
        (await store.save(scope, changed, BigInt.one)).generation,
        BigInt.two,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      final other = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: universe,
        continuity: scope.continuity,
        representedContext: context,
        typeClientRef: 'other-type',
      );
      expect(await store.load(other), isNull);
      await expectLater(
        store.save(other, input, BigInt.zero),
        throwsFormatException,
      );
      final otherContext = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: universe,
        continuity: scope.continuity,
        representedContext: RecordId.generate(),
        typeClientRef: record.value,
      );
      expect(await store.load(otherContext), isNull);
      await expectLater(
        store.save(otherContext, input, BigInt.zero),
        throwsFormatException,
      );
      await expectLater(
        store.save(scope, form(label: '\uD800'), BigInt.two),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        changed.toWire().toText(),
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
