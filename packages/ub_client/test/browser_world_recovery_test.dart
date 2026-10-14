@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_world_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('unfinished browser worlds survive reopening with exact fields and isolated editor scopes', () async {
    final name = 'ub-world-test-${OperationId.generate().value}';
    var store = await BrowserWorldFormRecoveryStore.open(databaseName: name);
    final instance = OperationId.generate(),
        profile = ProfileId.generate(),
        universe = UniverseId.generate(),
        continuity = ContinuityId.generate();
    final context = RecordId.generate(), record = RecordId.generate();
    EditorFormScope scope({
      OperationId? installation,
      ProfileId? account,
      UniverseId? worldSet,
      ContinuityId? branch,
      RecordId? represented,
      String? edit,
      RecordId? target,
    }) => EditorFormScope(
      instance: installation ?? instance,
      profile: account ?? profile,
      universe: worldSet ?? universe,
      continuity: branch ?? continuity,
      representedContext: represented ?? context,
      worldClientRef: edit,
      worldRecord: target,
    );
    final form = UnfinishedWorldForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      record: record,
      selector: 'Mémoire 😀\r\n',
      settingType: '',
      rationale: 'Unfinished research',
      aliases: ['echo', 'é😀', 'echo'],
      labels: {'fr': 'Monde', '': ''},
      draftVersion: BigInt.parse('9007199254740993'),
      expectedRecordVersion: RecordVersionId.generate(),
    );
    try {
      expect(await store.load(scope()), isNull);
      final saved = await store.save(scope(), form, BigInt.zero);
      expect(saved.generation, BigInt.one);
      store.close();
      store = await BrowserWorldFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope()))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      expect(
        (await store.save(scope(), form, BigInt.zero)).generation,
        BigInt.one,
      );
      var calls = 0;
      var wrongInstance = true;
      final recovery = BrowserWorldFormRecovery(
        store: store,
        principal: profile,
        call: (_) async {
          calls++;
          return CanonicalObject([
            MapEntry(
              'instance_id',
              CanonicalString(
                wrongInstance ? OperationId.generate().value : instance.value,
              ),
            ),
            MapEntry('universes', CanonicalArray([])),
          ]);
        },
      );
      await expectLater(
        recovery.load(scope(account: ProfileId.generate())),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(calls, 0);
      await expectLater(
        recovery.load(scope()),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      wrongInstance = false;
      await expectLater(
        recovery.load(scope()),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(calls, 2);
      // Retaining the already saved input does not require an online service.
      expect(
        (await recovery.save(scope(), form, BigInt.zero)).generation,
        BigInt.one,
      );
      expect(calls, 2);
      for (final other in [
        scope(installation: OperationId.generate()),
        scope(account: ProfileId.generate()),
        scope(worldSet: UniverseId.generate()),
        scope(branch: ContinuityId.generate()),
        scope(represented: RecordId.generate()),
        scope(edit: 'pending-world'),
        scope(target: record),
      ]) {
        expect(await store.load(other), isNull);
      }
      final changed = UnfinishedWorldForm(
        baseRevision: form.baseRevision,
        representedContext: context,
        record: record,
        selector: 'Next world',
        settingType: 'Other setting',
        rationale: '',
        aliases: ['new'],
        labels: {'en': 'World'},
      );
      await expectLater(
        store.save(scope(), changed, BigInt.zero),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        (await store.load(scope()))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      final next = await store.save(scope(), changed, BigInt.one);
      expect(next.generation, BigInt.two);
      expect(
        (await store.load(scope()))!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      final invalid = UnfinishedWorldForm(
        baseRevision: form.baseRevision,
        representedContext: context,
        record: record,
        selector: '\uD800',
        settingType: '',
        rationale: '',
      );
      await expectLater(
        store.save(scope(), invalid, BigInt.two),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(
        (await store.load(scope()))!.form.toWire().toText(),
        changed.toWire().toText(),
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

  test('competing browser tabs commit only one generation and retain complete child rows', () async {
    final name = 'ub-world-race-${OperationId.generate().value}';
    final first = await BrowserWorldFormRecoveryStore.open(databaseName: name),
        second = await BrowserWorldFormRecoveryStore.open(databaseName: name);
    final context = RecordId.generate(),
        record = RecordId.generate(),
        revision = RevisionId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: context,
    );
    UnfinishedWorldForm form(String label) => UnfinishedWorldForm(
      baseRevision: revision,
      representedContext: context,
      record: record,
      selector: label,
      settingType: '',
      rationale: label,
      aliases: [label, label],
      labels: {'en': label},
    );
    try {
      final outcomes = await Future.wait([
        first
            .save(scope, form('First'), BigInt.zero)
            .then<Object>((value) => value, onError: (Object error) => error),
        second
            .save(scope, form('Second'), BigInt.zero)
            .then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(outcomes.whereType<SavedWorldForm>(), hasLength(1));
      expect(
        outcomes.whereType<EditorRecoveryException>().single.failure,
        EditorRecoveryFailure.conflict,
      );
      final loaded = (await second.load(scope))!;
      expect(loaded.generation, BigInt.one);
      expect(
        loaded.form.toWire().toText(),
        outcomes.whereType<SavedWorldForm>().single.form.toWire().toText(),
      );
    } finally {
      first.close();
      second.close();
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
