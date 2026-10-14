@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_memory_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser memories retain remembered/alleged links, alteration choices and exact validity', () async {
    final name = 'ub-memory-test-${OperationId.generate().value}';
    var store = await BrowserMemoryFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final original = MemoryRecord(
      holder: ref(),
      content: ref(),
      alleged: ref(),
      altered: true,
      accessibility: 'Fragmented 記憶 😀',
      validity: InstantValidity(
        ExactTime(calendar, '9007199254740993123456789'),
      ),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: 'recollection',
    );
    final input = UnfinishedMemoryForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'recollection',
      holder: ExpressionReferenceInput(
        record: original.holder.record.value,
        universe: universe.value,
      ),
      content: ExpressionReferenceInput(
        record: 'unresolved remembered content',
      ),
      altered: false,
      validity: TemporalValidityInput(
        calendar: calendar.value,
        start: TemporalBoundInput(value: '9007199254740993123456789'),
        end: TemporalBoundInput(
          kind: 'approximate',
          value: 'unfinished-',
          uncertainty: '±?',
        ),
      ),
      allegedEnabled: true,
      alleged: ExpressionReferenceInput(record: 'unresolved alleged content'),
      accessibility: 'Mémoire 😀\r\n',
      original: original,
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedMemoryForm alteration(CanonicalValue value) =>
        UnfinishedMemoryForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(
                field.key,
                field.key == 'altered' ? value : field.value,
              ),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserMemoryFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      await expectLater(
        store.save(scope, alteration(CanonicalNull()), BigInt.zero),
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
        final changed = alteration(choice);
        await store.save(scope, changed, generation);
        generation += BigInt.one;
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          changed.toWire().toText(),
        );
      }
      final disabled = input.copyWith(
        allegedEnabled: false,
        accessibility: '',
        validity: TemporalValidityInput(),
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
          disabled.copyWith(accessibility: '\uD800'),
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
