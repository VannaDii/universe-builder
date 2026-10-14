@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_passage_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  for (final qualified in [false, true]) {
    test(
      'browser passages preserve edition pins and optional anchors with qualified=$qualified',
      () async {
        final name = 'ub-passage-test-${OperationId.generate().value}';
        var store = await BrowserPassageFormRecoveryStore.open(
          databaseName: name,
        );
        final universe = UniverseId.generate(), context = RecordId.generate();
        final scope = EditorFormScope(
          instance: OperationId.generate(),
          profile: ProfileId.generate(),
          universe: universe,
          continuity: ContinuityId.generate(),
          representedContext: context,
          typeClientRef: 'passage',
        );
        final input = UnfinishedPassageForm(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          clientRef: 'passage',
          passageId: 'Chapter 3 記憶 😀\r\n',
          edition: ExpressionReferenceInput(
            record: RecordId.generate().value,
            universe: qualified ? universe.value : '',
          ),
          editionVersion: RecordVersionId.generate().value,
          anchorEnabled: true,
          anchor: ExpressionReferenceInput(
            record: RecordId.generate().value,
            universe: qualified ? universe.value : '',
          ),
          rationale: '',
          draftVersion: BigInt.parse('9007199254740993'),
        );
        try {
          await store.save(scope, input, BigInt.zero);
          store.close();
          store = await BrowserPassageFormRecoveryStore.open(
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
            anchorEnabled: false,
            passageId: 'Entered next passage',
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
          final incomplete = input.copyWith(
            edition: ExpressionReferenceInput(record: 'unresolved edition'),
            editionVersion: '',
            anchor: ExpressionReferenceInput(),
            passageId: '',
          );
          await store.save(scope, incomplete, BigInt.two);
          expect(
            (await store.load(scope))!.form.toWire().toText(),
            incomplete.toWire().toText(),
          );
          await expectLater(
            store.save(
              scope,
              incomplete.copyWith(passageId: '\uD800'),
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
            incomplete.toWire().toText(),
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
      },
    );
  }
}
