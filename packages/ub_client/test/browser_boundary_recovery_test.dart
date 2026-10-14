@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_boundary_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser boundaries retain area, mode, nested original expressions and ordered constraints', () async {
    final name = 'ub-boundary-test-${OperationId.generate().value}';
    var store = await BrowserBoundaryFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    final comparison = CompareExpr(
      ValueOperand(IntegerValue('9007199254740993123456789')),
      Comparator.ltEq,
      ValueOperand(RationalValue('003', '02')),
    );
    final original = BoundaryRecord(
      key: 'Origin 記憶 😀',
      area: PredicateBoundaryArea(
        'authored:account',
        RecordRef(record: RecordId.generate()),
      ),
      mode: BoundaryMode.values.first,
      constraints: [
        AllExpr([LiteralExpr(true), LiteralExpr(false)]),
        comparison,
      ],
      scope: Scope(
        context: RecordRef(universe: universe, record: context),
        applicability: UniverseApplicability(),
      ),
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
      typeClientRef: 'boundary',
    );
    final input = UnfinishedBoundaryForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'boundary',
      key: 'Origin 記憶 😀\r\n',
      areaKind: 'predicate',
      record: ExpressionReferenceInput(record: 'unresolved record'),
      predicate: 'authored:account',
      subjectEnabled: true,
      subject: ExpressionReferenceInput(record: 'unresolved subject'),
      category: 'unresolved category',
      mode: 'unresolved mode',
      constraints: [
        ExpressionInput(
          kind: 'all',
          items: [
            ExpressionInput(kind: 'literal', flags: {'value': true}),
            ExpressionInput(kind: '', flags: {'value': null}),
          ],
        ),
        ExpressionInput(kind: 'compare', original: comparison),
        ExpressionInput(kind: 'literal', flags: {'value': false}),
      ],
      scope: ScopeInput(
        applicability: 'worlds',
        worlds: ['world', '', 'world'],
        contextRecord: context.value,
        hasRealm: true,
        realmRecord: 'unresolved realm',
      ),
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
      store = await BrowserBoundaryFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = input.copyWith(
        constraints: input.constraints.reversed.toList(),
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
        subjectEnabled: false,
        constraints: [],
        scope: ScopeInput(),
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
          cleared.copyWith(
            constraints: [
              ExpressionInput(strings: {'entered': '\uD800'}),
            ],
          ),
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
