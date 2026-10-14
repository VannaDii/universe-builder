@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_unit_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser unit revisions preserve exact scales, original validity, labels and unfinished temporal fields', () async {
    final name = 'ub-unit-test-${OperationId.generate().value}';
    var store = await BrowserUnitFormRecoveryStore.open(databaseName: name);
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
    final original = UnitRecord(
      namespace: 'authored',
      key: 'measure',
      dimension: 'distance',
      symbol: 'm',
      labels: {'ja': '計量 😀', '': ''},
      base: UnitId.generate(),
      scaleToBase: RationalValue('9007199254740997', '03'),
      validity: InstantValidity(
        DurationTime(calendar, SequenceValue([TextValue('one lifetime 😀')])),
      ),
    );
    final input = UnfinishedUnitForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      namespace: 'authored',
      key: 'measure',
      dimension: '',
      symbol: 'é😀\r\n',
      labels: [
        PropertyLabelInput(language: 'fr', text: 'Mesure'),
        PropertyLabelInput(language: 'fr', text: ''),
        PropertyLabelInput(language: '', text: ''),
      ],
      hasBase: true,
      base: 'unresolved base',
      hasScale: true,
      scale: QualifierInput(
        kind: 'rational',
        value: '9007199254740993123456789',
        denominator: '003',
      ),
      validityChoice: 'interval',
      temporalValidity: TemporalValidityInput(
        calendar: calendar.value,
        start: TemporalBoundInput(value: '9007199254740993123456789'),
        end: TemporalBoundInput(
          kind: 'approximate',
          value: 'unfinished-',
          uncertainty: '±?',
        ),
      ),
      rationale: '',
      revisionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: original,
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedUnitForm changed(Map<String, CanonicalValue> updates) =>
        UnfinishedUnitForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(field.key, updates[field.key] ?? field.value),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserUnitFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final cleared = changed({
        'labels': CanonicalArray([]),
        'has_base': CanonicalBool(false),
        'has_scale': CanonicalBool(false),
      });
      await expectLater(
        store.save(scope, cleared, BigInt.zero),
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
      expect(
        (await store.save(scope, cleared, BigInt.one)).generation,
        BigInt.two,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      final invalid = UnfinishedUnitForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: record.value,
        scale: QualifierInput(children: [QualifierInput(value: '\uD800')]),
      );
      await expectLater(
        store.save(scope, invalid, BigInt.two),
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
