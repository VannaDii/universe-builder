@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_initialization_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('initialization recovery retains pinned sources, exact text, scope and conflicting saves', () async {
    final name = 'ub-initialization-test-${OperationId.generate().value}';
    var store = await BrowserInitializationFormRecoveryStore.open(
      databaseName: name,
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
      typeClientRef: 'initialize',
    );
    final form = UnfinishedInitializationForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'initialize',
      instance: const ExpressionReferenceInput(record: 'unfinished instance'),
      start: const ExpressionReferenceInput(record: 'unfinished event'),
      definition: VersionRef(
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
        universe: scope.universe,
      ),
      scope: ScopeInput(
        applicability: 'worlds',
        worlds: ['\ufeff記憶', '', 'First', 'First'],
        contextRecord: scope.representedContext!.value,
        contextUniverse: scope.universe.value,
        hasRealm: true,
        realmRecord: 'unfinished realm',
      ),
      endKind: 'exact',
      endCoordinate: 'unfinished end',
      rationale: '\ufeff記憶 😀\r\n',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    try {
      await store.save(scope, form, BigInt.zero);
      store.close();
      store = await BrowserInitializationFormRecoveryStore.open(
        databaseName: name,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      await expectLater(
        store.save(
          scope,
          form.copyWith(rationale: 'other window'),
          BigInt.zero,
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      await expectLater(
        store.save(scope, form.copyWith(rationale: '\ud800'), BigInt.one),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect((await store.load(scope))!.generation, BigInt.one);
      final cleared = form.copyWith(
        clearDefinition: true,
        endKind: 'unbounded',
      );
      await store.save(scope, cleared, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      expect(
        await store.load(
          EditorFormScope(
            instance: scope.instance,
            profile: ProfileId.generate(),
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: scope.representedContext,
            typeClientRef: 'initialize',
          ),
        ),
        isNull,
      );
    } finally {
      store.close();
      final done = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Test cleanup failed'),
      )).toJS;
      await done.future;
    }
  });
}
