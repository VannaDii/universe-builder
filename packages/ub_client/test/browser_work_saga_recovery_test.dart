@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_work_recovery.dart';
import 'package:ub_client/browser_saga_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  for (final kind in ['work', 'saga']) {
    test(
      'browser $kind retains ordered references and unfinished input through refresh and conflict',
      () async {
        final name = 'ub-narrative-test-${OperationId.generate().value}';
        late Future<CanonicalValue?> Function(EditorFormScope) load;
        late Future<BigInt> Function(EditorFormScope, CanonicalValue, BigInt)
        save;
        late void Function() close;
        Future<void> open() async {
          if (kind == 'work') {
            final store = await BrowserWorkFormRecoveryStore.open(
              databaseName: name,
            );
            load = (scope) async => (await store.load(scope))?.form.toWire();
            save = (scope, form, generation) async => (await store.save(
              scope,
              UnfinishedWorkForm.fromWire(form),
              generation,
            )).generation;
            close = store.close;
          } else {
            final store = await BrowserSagaFormRecoveryStore.open(
              databaseName: name,
            );
            load = (scope) async => (await store.load(scope))?.form.toWire();
            save = (scope, form, generation) async => (await store.save(
              scope,
              UnfinishedSagaForm.fromWire(form),
              generation,
            )).generation;
            close = store.close;
          }
        }

        await open();
        final universe = UniverseId.generate(),
            context = RecordId.generate(),
            record = RecordId.generate(),
            calendar = CalendarId.generate();
        final scope = EditorFormScope(
          instance: OperationId.generate(),
          profile: ProfileId.generate(),
          universe: universe,
          continuity: ContinuityId.generate(),
          representedContext: context,
          typeClientRef: record.value,
        );
        final labels = [
          PropertyLabelInput(language: 'fr', text: 'Mémoire 😀\r\n'),
          PropertyLabelInput(language: 'fr', text: ''),
        ];
        late CanonicalObject input, reversed, cleared;
        if (kind == 'work') {
          final association = WorldAssociation(
            world: WorldId.generate(),
            role: 'Setting',
            validity: InstantValidity(
              ExactTime(calendar, '9007199254740993123456789'),
            ),
            qualifiers: {
              'count': IntegerValue('9007199254740993123456789'),
              'note': TextValue('記憶 😀'),
            },
          );
          final original = WorkRecord(
            kind: WorkKind.values.first,
            title: 'Original',
            labels: {'ja': '記憶 😀'},
            sourceRefs: [RecordRef(record: RecordId.generate())],
            versions: [RecordId.generate()],
            worldAssociations: [association],
          );
          final form = UnfinishedWorkForm(
            baseRevision: RevisionId.generate(),
            representedContext: context,
            clientRef: record.value,
            kind: 'unfinished kind',
            title: 'Mémoire 😀\r\n',
            labels: labels,
            sources: [
              ExpressionReferenceInput(record: 'source'),
              ExpressionReferenceInput(),
            ],
            versions: ['edition', '', 'edition', 'unresolved edition'],
            associations: [
              WorkAssociationInput(
                world: 'unresolved world',
                role: 'Setting',
                originalOrdinal: 2,
                validity: TemporalValidityInput(
                  calendar: calendar.value,
                  start: TemporalBoundInput(value: 'unfinished-'),
                ),
                qualifiers: [
                  QualifierInput(
                    kind: 'sequence',
                    children: [
                      QualifierInput(value: '9007199254740993123456789'),
                    ],
                  ),
                ],
              ),
              WorkAssociationInput(world: '', role: ''),
            ],
            original: original,
            associationTarget: ExpressionReferenceInput(
              record: record.value,
              universe: universe.value,
            ),
            associationOriginal: association,
            expectedRecordVersion: RecordVersionId.generate(),
            draftVersion: BigInt.parse('9007199254740993'),
          );
          input = form.toWire();
          reversed = form
              .copyWith(
                sources: form.sources.reversed.toList(),
                versions: form.versions.reversed.toList(),
                associations: form.associations.reversed.toList(),
              )
              .toWire();
          cleared = form
              .copyWith(labels: [], sources: [], versions: [], associations: [])
              .toWire();
        } else {
          final form = UnfinishedSagaForm(
            baseRevision: RevisionId.generate(),
            representedContext: context,
            clientRef: record.value,
            title: 'Mémoire 😀\r\n',
            labels: labels,
            memberships: [
              SagaMembershipInput(
                work: ExpressionReferenceInput(record: 'unresolved work'),
                role: 'same',
                orderEnabled: true,
                order: '9007199254740993123456789',
              ),
              SagaMembershipInput(
                work: ExpressionReferenceInput(),
                role: 'same',
                orderEnabled: false,
                order: 'unfinished-',
              ),
            ],
            membershipTarget: ExpressionReferenceInput(
              record: record.value,
              universe: universe.value,
            ),
            expectedRecordVersion: RecordVersionId.generate(),
            draftVersion: BigInt.parse('9007199254740993'),
          );
          input = form.toWire();
          reversed = form
              .copyWith(memberships: form.memberships.reversed.toList())
              .toWire();
          cleared = form.copyWith(labels: [], memberships: []).toWire();
        }
        try {
          await save(scope, input, BigInt.zero);
          close();
          await open();
          expect((await load(scope))!.toText(), input.toText());
          expect(await save(scope, input, BigInt.zero), BigInt.one);
          await expectLater(
            save(scope, reversed, BigInt.zero),
            throwsA(
              isA<EditorRecoveryException>().having(
                (error) => error.failure,
                'failure',
                EditorRecoveryFailure.conflict,
              ),
            ),
          );
          expect((await load(scope))!.toText(), input.toText());
          await save(scope, reversed, BigInt.one);
          expect((await load(scope))!.toText(), reversed.toText());
          await save(scope, cleared, BigInt.two);
          expect((await load(scope))!.toText(), cleared.toText());
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
