@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_record_removal_recovery.dart';
import 'package:ub_client/browser_assertion_retraction_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  for (final kind in ['record removal', 'assertion retraction']) {
    test(
      'browser $kind retains pinned references and incomplete reasons through refresh and conflict',
      () async {
        final name = 'ub-removal-test-${OperationId.generate().value}';
        late Future<CanonicalValue?> Function(EditorFormScope) load;
        late Future<BigInt> Function(EditorFormScope, CanonicalValue, BigInt)
        save;
        late void Function() close;
        Future<void> open() async {
          if (kind == 'record removal') {
            final store = await BrowserRecordRemovalFormRecoveryStore.open(
              databaseName: name,
            );
            load = (scope) async => (await store.load(scope))?.form.toWire();
            save = (scope, form, expected) async => (await store.save(
              scope,
              UnfinishedRecordRemovalForm.fromWire(form),
              expected,
            )).generation;
            close = store.close;
          } else {
            final store =
                await BrowserAssertionRetractionFormRecoveryStore.open(
                  databaseName: name,
                );
            load = (scope) async => (await store.load(scope))?.form.toWire();
            save = (scope, form, expected) async => (await store.save(
              scope,
              UnfinishedAssertionRetractionForm.fromWire(form),
              expected,
            )).generation;
            close = store.close;
          }
        }

        await open();
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
        final input = UnfinishedRecordRemovalForm(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          clientRef: record.value,
          target: ExpressionReferenceInput(
            record: record.value,
            universe: universe.value,
          ),
          expectedRecordVersion: RecordVersionId.generate(),
          rationale: 'Mémoire 😀\r\n',
          draftVersion: BigInt.parse('9007199254740993'),
        ).toWire();
        CanonicalObject reason(String text) => CanonicalObject(
          input.fields.map(
            (field) => MapEntry(
              field.key,
              field.key == 'rationale' ? CanonicalString(text) : field.value,
            ),
          ),
        );
        try {
          expect(await load(scope), isNull);
          expect(await save(scope, input, BigInt.zero), BigInt.one);
          close();
          await open();
          expect((await load(scope))!.toText(), input.toText());
          expect(await save(scope, input, BigInt.zero), BigInt.one);
          await expectLater(
            save(scope, reason('Different reason'), BigInt.zero),
            throwsA(
              isA<EditorRecoveryException>().having(
                (error) => error.failure,
                'failure',
                EditorRecoveryFailure.conflict,
              ),
            ),
          );
          expect((await load(scope))!.toText(), input.toText());
          expect(await save(scope, reason(''), BigInt.one), BigInt.two);
          expect((await load(scope))!.toText(), reason('').toText());
          // Construct directly so the private save handles malformed entered text.
          if (kind == 'record removal') {
            final store = await BrowserRecordRemovalFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              await expectLater(
                store.save(
                  scope,
                  UnfinishedRecordRemovalForm.fromWire(input)
                      .copyWith(rationale: '\uD800'),
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
            } finally {
              store.close();
            }
          } else {
            final store =
                await BrowserAssertionRetractionFormRecoveryStore.open(
                  databaseName: name,
                );
            try {
              await expectLater(
                store.save(
                  scope,
                  UnfinishedAssertionRetractionForm.fromWire(input)
                      .copyWith(rationale: '\uD800'),
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
            } finally {
              store.close();
            }
          }
          expect((await load(scope))!.toText(), reason('').toText());
          final other = EditorFormScope(
            instance: scope.instance,
            profile: scope.profile,
            universe: universe,
            continuity: scope.continuity,
            representedContext: context,
            typeClientRef: 'different',
          );
          expect(await load(other), isNull);
          await expectLater(
            save(other, input, BigInt.zero),
            throwsFormatException,
          );
        } finally {
          close();
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
