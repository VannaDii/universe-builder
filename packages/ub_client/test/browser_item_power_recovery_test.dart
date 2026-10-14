@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_item_power_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser item powers retain frozen predicates, nested exact values, scope and original versions', () async {
    final name = 'ub-power-test-${OperationId.generate().value}';
    var store = await BrowserItemPowerFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final original = ItemPowerRecord(
      item: ref(),
      holderPredicate: ref(),
      powerPredicate: ref(),
      value: IntegerValue('9007199254740993123456789'),
      scope: Scope(
        context: RecordRef(universe: universe, record: context),
        applicability: UniverseApplicability(),
      ),
      validity: UnspecifiedValidity(),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final input = UnfinishedItemPowerForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      item: ExpressionReferenceInput(
        record: original.item.record.value,
        universe: universe.value,
      ),
      holderPredicate: ExpressionReferenceInput(
        record: original.holderPredicate.record.value,
      ),
      powerPredicate: ExpressionReferenceInput(
        record: original.powerPredicate.record.value,
      ),
      value: QualifierInput(
        kind: 'sequence',
        children: [
          QualifierInput(kind: 'integer', value: '9007199254740993123456789'),
          QualifierInput(kind: 'rational', value: '003', denominator: '02'),
          QualifierInput(kind: 'text', value: '記憶 😀\r\n'),
        ],
      ),
      scope: ScopeInput(
        applicability: 'worlds',
        worlds: ['world', '', 'world'],
        contextRecord: context.value,
        contextUniverse: universe.value,
        hasRealm: true,
        realmRecord: 'unresolved realm',
      ),
      validity: TemporalValidityInput(
        calendar: calendar.value,
        start: TemporalBoundInput(value: '9007199254740993123456789'),
        end: TemporalBoundInput(value: 'unfinished-'),
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
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserItemPowerFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final changed = input.copyWith(
        value: QualifierInput(
          kind: 'sequence',
          children: input.value.children.reversed.toList(),
        ),
      );
      await expectLater(
        store.save(scope, changed, BigInt.zero),
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
      await store.save(scope, changed, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      final incomplete = input.copyWith(
        value: QualifierInput(value: 'unfinished-'),
        scope: ScopeInput(),
        validity: TemporalValidityInput(),
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
            value: QualifierInput(children: [QualifierInput(value: '\uD800')]),
          ),
          BigInt.from(3),
        ),
        throwsFormatException,
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
  });
}
