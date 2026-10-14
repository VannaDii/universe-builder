@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_represented_context_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser represented contexts retain every kind, parent, labels and exact authored chronology', () async {
    final name = 'ub-context-test-${OperationId.generate().value}';
    var store = await BrowserRepresentedContextFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    final reference = RecordRef(
      universe: universe,
      record: RecordId.generate(),
    );
    final instance = OperationId.generate(),
        profile = ProfileId.generate(),
        continuity = ContinuityId.generate();
    for (final entry in <String, RepresentedContextKind>{
      'objective': ObjectiveContext(),
      'character': CharacterContext(reference),
      'source': SourceContext(reference),
      'narrator': NarratorContext(reference),
      'authored': AuthoredContext('Dream 記憶 😀'),
    }.entries) {
      final original = RepresentedContextRecord(
        universe: universe,
        kind: entry.value,
        parent: reference,
        labels: {'': '記憶 😀', 'en': 'Context'},
        chronology: Chronology(
          calendar: calendar,
          system: FictionalClock('ticks', 4294967295),
          firstInteraction: '0',
          current: '9007199254740993123456789',
        ),
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: profile,
        universe: universe,
        continuity: continuity,
        representedContext: context,
        typeClientRef: entry.key,
      );
      final input = UnfinishedRepresentedContextForm(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        universe: universe,
        clientRef: entry.key,
        kind: entry.key,
        authoredLabel: 'Dream 記憶 😀\r\n',
        reference: ExpressionReferenceInput(
          record: reference.record.value,
          universe: universe.value,
        ),
        parentEnabled: true,
        parent: ExpressionReferenceInput(record: 'unresolved parent'),
        labels: [
          PropertyLabelInput(language: 'fr', text: 'Contexte'),
          PropertyLabelInput(language: 'fr', text: ''),
        ],
        chronology: ChronologyInput(
          enabled: true,
          calendar: calendar.value,
          system: 'fictional',
          offsetSeconds: '-3600',
          tickLabel: 'ticks 😀',
          ticksPerMonthEnabled: true,
          ticksPerMonth: '4294967295',
          firstInteraction: '-9007199254740993123456789',
          current: '9007199254740993123456789',
        ),
        original: original,
        rationale: '',
        draftVersion: BigInt.parse('9007199254740993'),
      );
      try {
        await store.save(scope, input, BigInt.zero);
        store.close();
        store = await BrowserRepresentedContextFormRecoveryStore.open(
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
          parentEnabled: false,
          chronology: input.chronology.copyWith(
            enabled: false,
            ticksPerMonthEnabled: false,
          ),
          labels: [],
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
          kind: '',
          chronology: ChronologyInput(current: 'unfinished-'),
          parent: ExpressionReferenceInput(),
        );
        await store.save(scope, incomplete, BigInt.two);
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          incomplete.toWire().toText(),
        );
        await expectLater(
          store.save(
            scope,
            incomplete.copyWith(
              chronology: ChronologyInput(tickLabel: '\uD800'),
            ),
            BigInt.from(3),
          ),
          throwsFormatException,
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          incomplete.toWire().toText(),
        );
        final foreign = UnfinishedRepresentedContextForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(
                field.key,
                field.key == 'universe'
                    ? CanonicalString(UniverseId.generate().value)
                    : field.value,
              ),
            ),
          ),
        );
        await expectLater(
          store.save(scope, foreign, BigInt.from(3)),
          throwsFormatException,
        );
      } catch (_) {
        store.close();
        rethrow;
      }
    }
    store.close();
    final deleted = Completer<void>();
    final request = web.window.indexedDB.deleteDatabase(name);
    request.onsuccess = ((web.Event _) => deleted.complete()).toJS;
    request.onerror = ((web.Event _) => deleted.completeError(
      StateError('Test cleanup failed'),
    )).toJS;
    await deleted.future;
  });
}
