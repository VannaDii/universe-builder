@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_observation_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser observations retain sensory-access distinctions, interpretation and exact temporal input', () async {
    final name = 'ub-observation-test-${OperationId.generate().value}';
    var store = await BrowserObservationFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final original = ObservationRecord(
      observer: ref(),
      observed: ref(),
      sensoryAccess: false,
      time: ExactTime(calendar, '9007199254740993123456789'),
      interpretation: ref(),
      basis: AuthorDecisionBasis('Reported 記憶 😀'),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: 'observation',
    );
    final input = UnfinishedObservationForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'observation',
      observer: ExpressionReferenceInput(
        record: original.observer.record.value,
        universe: universe.value,
      ),
      observed: ExpressionReferenceInput(record: 'unresolved observed record'),
      sensoryAccess: false,
      time: TemporalValidityInput(
        kind: 'instant_exact',
        calendar: calendar.value,
        start: TemporalBoundInput(
          value: '9007199254740993123456789',
          amount: QualifierInput(
            kind: 'rational',
            value: '003',
            denominator: '02',
          ),
        ),
      ),
      interpretationEnabled: true,
      interpretation: ExpressionReferenceInput(
        record: 'unresolved interpretation',
      ),
      basis: EvidenceBasisInput(
        kind: 'source',
        note: 'Mémoire 😀\r\n',
        anchorRecord: 'unresolved anchor',
        verified: false,
      ),
      original: original,
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedObservationForm sensory(CanonicalValue value) =>
        UnfinishedObservationForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(
                field.key,
                field.key == 'sensory_access' ? value : field.value,
              ),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserObservationFormRecoveryStore.open(
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
      await expectLater(
        store.save(scope, sensory(CanonicalNull()), BigInt.zero),
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
      var generation = BigInt.one;
      for (final choice in [
        CanonicalNull(),
        CanonicalBool(true),
        CanonicalBool(false),
      ]) {
        final changed = sensory(choice);
        await store.save(scope, changed, generation);
        generation += BigInt.one;
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          changed.toWire().toText(),
        );
      }
      final disabled = input.copyWith(
        interpretationEnabled: false,
        time: TemporalValidityInput(
          start: TemporalBoundInput(value: 'unfinished-'),
        ),
      );
      await store.save(scope, disabled, generation);
      generation += BigInt.one;
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          disabled.copyWith(basis: EvidenceBasisInput(note: '\uD800')),
          generation,
        ),
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
