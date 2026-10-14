@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_communication_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser communications retain intended/actual recipients, distortion and exact times through refresh', () async {
    final name = 'ub-communication-test-${OperationId.generate().value}';
    var store = await BrowserCommunicationFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final original = CommunicationRecord(
      sender: ref(),
      intendedRecipients: [ref(), ref()],
      actualRecipients: [ref()],
      content: [ref(), ref()],
      channel: 'mail',
      distorted: false,
      sentAt: ExactTime(calendar, '9007199254740993123456789'),
      receivedAt: ExactTime(calendar, '9007199254740993123456793'),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final input = UnfinishedCommunicationForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      sender: ExpressionReferenceInput(
        record: original.sender.record.value,
        universe: universe.value,
      ),
      intendedRecipients: [
        ExpressionReferenceInput(record: 'recipient'),
        ExpressionReferenceInput(),
        ExpressionReferenceInput(record: 'recipient'),
        ExpressionReferenceInput(record: 'other'),
      ],
      actualRecipients: [
        ExpressionReferenceInput(record: 'actual recipient'),
        ExpressionReferenceInput(record: 'other actual recipient'),
      ],
      content: [
        ExpressionReferenceInput(record: 'claim'),
        ExpressionReferenceInput(record: 'other claim'),
      ],
      channelEnabled: true,
      channel: 'Mémoire 😀\r\n',
      distorted: false,
      sentAt: TemporalValidityInput(
        kind: 'instant_exact',
        calendar: calendar.value,
        start: TemporalBoundInput(value: '9007199254740993123456789'),
      ),
      receivedEnabled: true,
      receivedAt: TemporalValidityInput(
        kind: 'instant_exact',
        calendar: calendar.value,
        start: TemporalBoundInput(value: 'unfinished-'),
      ),
      original: original,
      correctionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedCommunicationForm distortion(CanonicalValue value) =>
        UnfinishedCommunicationForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(
                field.key,
                field.key == 'distorted' ? value : field.value,
              ),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserCommunicationFormRecoveryStore.open(
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
      final reversed = input.copyWith(
        intendedRecipients: input.intendedRecipients.reversed.toList(),
        actualRecipients: input.actualRecipients.reversed.toList(),
        content: input.content.reversed.toList(),
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
      var generation = BigInt.two;
      for (final choice in [
        CanonicalNull(),
        CanonicalBool(true),
        CanonicalBool(false),
      ]) {
        final changed = distortion(choice);
        await store.save(scope, changed, generation);
        generation += BigInt.one;
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          changed.toWire().toText(),
        );
      }
      final disabled = input.copyWith(
        channelEnabled: false,
        receivedEnabled: false,
        intendedRecipients: [],
        actualRecipients: [],
        content: [],
      );
      await store.save(scope, disabled, generation);
      generation += BigInt.one;
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      await expectLater(
        store.save(scope, disabled.copyWith(channel: '\uD800'), generation),
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
