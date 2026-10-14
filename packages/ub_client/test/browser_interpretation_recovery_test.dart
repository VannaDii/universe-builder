@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_interpretation_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser interpretation corrections retain selected source, version, optional interpretation and reasons', () async {
    final name = 'ub-interpretation-test-${OperationId.generate().value}';
    var store = await BrowserInterpretationFormRecoveryStore.open(
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
    final input = UnfinishedInterpretationForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      target: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      interpretationEnabled: true,
      interpretation: ExpressionReferenceInput(
        record: 'unresolved interpretation',
        universe: '',
      ),
      rationale: 'Mémoire 😀\r\n',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserInterpretationFormRecoveryStore.open(
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
      final disabled = input.copyWith(
        interpretationEnabled: false,
        rationale: '',
      );
      await expectLater(
        store.save(scope, disabled, BigInt.zero),
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
      await store.save(scope, disabled, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      final cleared = input.copyWith(
        interpretation: ExpressionReferenceInput(),
        rationale: '',
      );
      await store.save(scope, cleared, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          cleared.copyWith(
            interpretation: ExpressionReferenceInput(record: '\uD800'),
          ),
          BigInt.from(3),
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
        cleared.toWire().toText(),
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
