@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_completeness_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser completeness retains observer perspective, ordered members and scoped empty declarations', () async {
    final name = 'ub-completeness-test-${OperationId.generate().value}';
    var store = await BrowserCompletenessFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        observer = RecordId.generate(),
        calendar = CalendarId.generate();
    final member = RecordRef(universe: universe, record: RecordId.generate());
    final original = CompletenessRecord(
      subject: RecordRef(universe: universe, record: RecordId.generate()),
      predicate: 'authored:members 記憶 😀',
      members: [member, member],
      completeness: ObserverCompleteness(observer),
      scope: Scope(
        context: RecordRef(universe: universe, record: context),
        applicability: UniverseApplicability(),
      ),
      validity: UnknownValidity(),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: 'members',
    );
    final input = UnfinishedCompletenessForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'members',
      subject: ExpressionReferenceInput(
        record: original.subject.record.value,
        universe: universe.value,
      ),
      predicate: 'authored:members 記憶 😀\r\n',
      members: [
        ExpressionReferenceInput(record: member.record.value),
        ExpressionReferenceInput(),
        ExpressionReferenceInput(record: member.record.value),
        ExpressionReferenceInput(record: 'unresolved member'),
      ],
      kind: 'observer_known',
      observer: observer.value,
      scope: ScopeInput(
        applicability: 'worlds',
        worlds: ['world', '', 'world'],
        contextRecord: context.value,
        contextUniverse: universe.value,
        hasRealm: true,
        realmRecord: 'unresolved realm',
        realmUniverse: '',
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
    UnfinishedCompletenessForm changed(Map<String, CanonicalValue> values) =>
        UnfinishedCompletenessForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(field.key, values[field.key] ?? field.value),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserCompletenessFormRecoveryStore.open(
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
      final reversed = changed({
        'members': CanonicalArray(
          input.members.reversed.map((member) => member.toWire()),
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
      final empty = changed({
        'members': CanonicalArray([]),
        'kind': CanonicalString('objective_reality'),
        'observer': CanonicalString(''),
      });
      await store.save(scope, empty, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        empty.toWire().toText(),
      );
      final invalid = UnfinishedCompletenessForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: 'members',
        scope: ScopeInput(worlds: ['\uD800']),
      );
      await expectLater(
        store.save(scope, invalid, BigInt.from(3)),
        throwsFormatException,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        empty.toWire().toText(),
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
