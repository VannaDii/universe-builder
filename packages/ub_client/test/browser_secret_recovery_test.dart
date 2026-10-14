@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_secret_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser secrets recover named fields and ordered references with generation conflicts', () async {
    final name = 'ub-secret-test-${OperationId.generate().value}';
    var store = await BrowserSecretFormRecoveryStore.open(databaseName: name);
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedSecretForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'heir',
      scope: [
        const ExpressionReferenceInput(record: ''),
        const ExpressionReferenceInput(record: 'pending-name 記憶'),
      ],
      fictionalKnowers: [
        const ExpressionReferenceInput(record: 'character'),
        const ExpressionReferenceInput(record: 'character'),
      ],
      hasConcealment: true,
      concealment: 'Mémoire 😀\r\n',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    try {
      await store.save(scope, form, BigInt.zero);
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      store.close();
      store = await BrowserSecretFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      final changed = form.copyWith(readerDisclosed: false, concealment: '');
      await store.save(scope, changed, BigInt.one);
      expect((await store.load(scope))!.form.readerDisclosed, isFalse);
      expect((await store.load(scope))!.form.hasConcealment, isTrue);
      await expectLater(
        store.save(scope, form, BigInt.one),
        throwsA(isA<EditorRecoveryException>()),
      );
      final revision = UnfinishedSecretForm.fromWire(
        CanonicalObject([
          ...changed.toWire().fields,
          MapEntry(
            'revision_target',
            ExpressionReferenceInput(record: RecordId.generate().value)
                .toWire(),
          ),
          MapEntry(
            'expected_record_version',
            CanonicalString(RecordVersionId.generate().value),
          ),
        ]),
      );
      final revisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: revision.recoveryKey,
      );
      await store.save(revisionScope, revision, BigInt.zero);
      expect(
        (await store.load(revisionScope))!.form.toWire().toText(),
        revision.toWire().toText(),
      );
      expect((await store.load(scope))!.form.revisionTarget, isNull);
    } finally {
      store.close();
      final done = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Cleanup failed'),
      )).toJS;
      await done.future;
    }
  });
}
