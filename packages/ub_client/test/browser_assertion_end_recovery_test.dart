@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_assertion_end_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser assertion endings preserve exact coordinates, original basis and entered evidence choices', () async {
    final name = 'ub-assertion-end-test-${OperationId.generate().value}';
    var store = await BrowserAssertionEndFormRecoveryStore.open(
      databaseName: name,
    );
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
    final input = UnfinishedAssertionEndForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      target: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      calendar: CalendarId.generate(),
      coordinate: '9007199254740993123456789',
      originalBasis: AuthorDecisionBasis('Original account 記憶 😀'),
      basis: EvidenceBasisInput(
        kind: 'source',
        note: 'Mémoire 😀\r\n',
        anchorRecord: 'unresolved anchor',
        anchorUniverse: universe.value,
        verified: false,
      ),
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserAssertionEndFormRecoveryStore.open(
        databaseName: name,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final changed = input.copyWith(
        coordinate: 'unfinished-',
        basis: EvidenceBasisInput(
          kind: 'author',
          note: '',
          anchorRecord: '',
          anchorUniverse: '',
          verified: true,
        ),
        rationale: 'Entered reason',
      );
      await expectLater(
        store.save(scope, changed, BigInt.zero),
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
      await store.save(scope, changed, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          changed.copyWith(basis: EvidenceBasisInput(note: '\uD800')),
          BigInt.two,
        ),
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
