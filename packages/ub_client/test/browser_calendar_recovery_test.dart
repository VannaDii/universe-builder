@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_calendar_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser calendar revisions retain epoch distinctions, ordered units and conversion expressions', () async {
    final name = 'ub-calendar-test-${OperationId.generate().value}';
    var store = await BrowserCalendarFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        target = CalendarId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final original = CalendarRecord(
      namespace: 'authored',
      key: 'regional',
      labels: {'ja': '記憶 😀', '': ''},
      epoch: '',
      unitStructure: {'month': '30 days', 'year': '12 months 😀'},
      conversions: [
        CalendarConversion(target: target, valid: false),
        CalendarConversion(target: target, expression: '', valid: true),
        CalendarConversion(
          target: target,
          expression: 'authored mapping',
          valid: false,
        ),
      ],
    );
    final input = UnfinishedCalendarForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      namespace: 'authored',
      key: 'regional',
      labels: [
        PropertyLabelInput(language: 'fr', text: 'Mémoire 😀\r\n'),
        PropertyLabelInput(language: 'fr', text: ''),
        PropertyLabelInput(language: '', text: ''),
      ],
      hasEpoch: true,
      epoch: '',
      units: [
        CalendarUnitInput(
          name: 'same',
          structure: '9007199254740993123456789 ticks',
        ),
        CalendarUnitInput(name: 'same', structure: ''),
      ],
      conversions: [
        CalendarConversionInput(
          target: target.value,
          hasExpression: false,
          expression: 'retained input',
          valid: false,
        ),
        CalendarConversionInput(
          target: target.value,
          hasExpression: true,
          expression: '',
          valid: true,
        ),
        CalendarConversionInput(
          target: 'unresolved calendar',
          hasExpression: true,
          expression: 'incomplete(',
          valid: false,
        ),
      ],
      rationale: '',
      revisionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: original,
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedCalendarForm changed(Map<String, CanonicalValue> updates) =>
        UnfinishedCalendarForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(field.key, updates[field.key] ?? field.value),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserCalendarFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = changed({
        'units': CanonicalArray(input.units.reversed.map((u) => u.toWire())),
        'conversions': CanonicalArray(
          input.conversions.reversed.map((c) => c.toWire()),
        ),
      });
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
      final cleared = changed({
        'units': CanonicalArray([]),
        'conversions': CanonicalArray([]),
        'labels': CanonicalArray([]),
        'has_epoch': CanonicalBool(false),
        'epoch': CanonicalString('Retained epoch input'),
      });
      await store.save(scope, cleared, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      final invalid = UnfinishedCalendarForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: record.value,
        conversions: [CalendarConversionInput(expression: '\uD800')],
      );
      await expectLater(
        store.save(scope, invalid, BigInt.from(3)),
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
