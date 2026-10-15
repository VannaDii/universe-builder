@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_app/browser_universe_creation_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS('Reflect.deleteProperty')
external bool _deleteProperty(JSObject object, JSString key);

Future<void> legacyRow(String name, (OperationId, ProfileId) scope) {
  final done = Completer<void>();
  final request = web.window.indexedDB.open(name, 1);
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Open failed'),
  )).toJS;
  request.onsuccess = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    final tx = db.transaction('universe_creation_form'.toJS, 'readwrite');
    final table = tx.objectStore('universe_creation_form');
    final key = [scope.$1.value.toJS, scope.$2.value.toJS].toJS;
    final read = table.get(key);
    read.onsuccess = ((web.Event _) {
      final row = read.result as JSObject;
      _deleteProperty(row, 'realWorld'.toJS);
      table.put(row, key);
    }).toJS;
    tx.oncomplete = ((web.Event _) {
      db.close();
      done.complete();
    }).toJS;
    tx.onabort = ((web.Event _) {
      db.close();
      done.completeError(StateError('Legacy row update failed'));
    }).toJS;
  }).toJS;
  return done.future;
}

void main() {
  test('creation recovery preserves both calendars, unknown outcome and scope across reopen', () async {
    final name = 'ub-creation-test-${OperationId.generate().value}';
    var store = await BrowserUniverseCreationFormRecoveryStore.open(
      databaseName: name,
    );
    final scope = (OperationId.generate(), ProfileId.generate());
    const form = UniverseCreationForm(
      name: '\uFEFFHistory café 😀\r\n',
      calendar: CreationCalendar.fictional,
      date: '2040-02-',
      time: '12:',
      offset: '-03:',
      calendarName: '記憶',
      initialTick: '-123456789012345678901234567890',
      tickLabel: 'beat\u0000 retained',
      ticksPerMonth: '',
      realWorld: true,
    );
    try {
      await store.save(scope, form, BigInt.zero);
      store.close();
      store = await BrowserUniverseCreationFormRecoveryStore.open(
        databaseName: name,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      await expectLater(
        store.save(scope, form.withPending(true), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      await store.save(scope, form.withPending(true), BigInt.one);
      store.close();
      store = await BrowserUniverseCreationFormRecoveryStore.open(
        databaseName: name,
      );
      final pending = (await store.load(scope))!;
      expect(pending.form.creationPending, isTrue);
      expect(
        pending.form.withPending(false).toWire().toText(),
        form.toWire().toText(),
      );
      expect(await store.load((OperationId.generate(), scope.$2)), isNull);
      expect(await store.load((scope.$1, ProfileId.generate())), isNull);
      await expectLater(
        store.save(
          scope,
          const UniverseCreationForm(
            name: '\uD800',
            calendar: CreationCalendar.gregorian,
          ),
          pending.generation,
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      await store.save(scope, form, pending.generation);
      expect((await store.load(scope))!.form.creationPending, isFalse);
      store.close();
      await legacyRow(name, scope);
      store = await BrowserUniverseCreationFormRecoveryStore.open(
        databaseName: name,
      );
      expect((await store.load(scope))!.form.realWorld, isFalse);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        CanonicalObject(form.toWire().fields.where((e) => e.key != 'realWorld'))
            .toText(),
      );
    } finally {
      store.close();
      final done = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Cleanup failed'),
      )).toJS;
      await done.future;
    }
  });
}
