@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_plan_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser plan recovery retains ordered participants and expressions with exact values', () async {
    final name = 'ub-plan-test-${OperationId.generate().value}';
    var store = await BrowserPlanFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    final comparison = CompareExpr(
      ValueOperand(IntegerValue('9007199254740993123456789')),
      Comparator.ltEq,
      ValueOperand(RationalValue('003', '02')),
    );
    final original = GoalRecord(
      actor: RecordRef(record: RecordId.generate()),
      desired: RecordRef(universe: universe, record: RecordId.generate()),
      prerequisites: [comparison, LiteralExpr(false)],
      steps: [
        RecordRef(record: RecordId.generate()),
        RecordRef(universe: universe, record: RecordId.generate()),
      ],
      status: PlanStatus.active,
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
      typeClientRef: 'plan',
    );
    final input = UnfinishedPlanForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'plan',
      actor: ExpressionReferenceInput(record: 'unfinished actor'),
      desiredEnabled: true,
      desired: ExpressionReferenceInput(
        record: 'unfinished desired',
        universe: universe.value,
      ),
      prerequisites: [
        ExpressionInput(kind: 'compare', original: comparison),
        ExpressionInput(kind: '', strings: {'input': 'unfinished-'}),
        ExpressionInput(kind: 'literal', flags: {'value': false}),
      ],
      steps: [
        ExpressionReferenceInput(record: 'step A'),
        ExpressionReferenceInput(),
        ExpressionReferenceInput(record: 'step A'),
        ExpressionReferenceInput(record: 'step B', universe: universe.value),
      ],
      status: 'unfinished status',
      validity: TemporalValidityInput(
        calendar: calendar.value,
        start: TemporalBoundInput(value: '9007199254740993123456789'),
        end: TemporalBoundInput(value: 'unfinished-'),
      ),
      original: original,
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserPlanFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = input.copyWith(
        steps: input.steps.reversed.toList(),
        prerequisites: input.prerequisites.reversed.toList(),
        desiredEnabled: false,
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
      final cleared = input.copyWith(
        steps: [],
        prerequisites: [],
        desiredEnabled: false,
        status: "",
        validity: TemporalValidityInput(),
      );
      await store.save(scope, cleared, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          cleared.copyWith(steps: [ExpressionReferenceInput(record: '\uD800')]),
          BigInt.from(3),
        ),
        throwsFormatException,
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
