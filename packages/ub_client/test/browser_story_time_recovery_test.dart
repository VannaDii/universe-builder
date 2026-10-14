@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_story_time_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser clock recovery preserves exact unfinished inputs, versions and conflicts', () async {
    final name = 'ub-clock-test-${OperationId.generate().value}';
    var store = await BrowserStoryTimeFormRecoveryStore.open(
      databaseName: name,
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedStoryTimeForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      target: ExpressionReferenceInput(
        record: scope.representedContext!.value,
        universe: scope.universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: FictionalUniverseStart(
        calendarName: 'Days',
        initialTick: '9007199254740993',
        tickLabel: 'days',
      ).build(CalendarId.generate()).$1,
      value: '-9007199254740993?',
      reason: '記憶 😀\r\n',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    try {
      await store.save(scope, form, BigInt.zero);
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      store.close();
      store = await BrowserStoryTimeFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      expect((await store.load(scope))!.form.mode, isEmpty);
      await expectLater(
        store.save(scope, form.copyWith(mode: 'elapsed'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      expect(
        (await store.save(
          scope,
          form.copyWith(mode: 'time_travel'),
          BigInt.one,
        )).generation,
        BigInt.two,
      );
      expect(
        await store.load(
          EditorFormScope(
            instance: scope.instance,
            profile: ProfileId.generate(),
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: scope.representedContext,
          ),
        ),
        isNull,
      );
    } finally {
      store.close();
      final done = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Could not remove test database'),
      )).toJS;
      await done.future;
    }
  });
}
