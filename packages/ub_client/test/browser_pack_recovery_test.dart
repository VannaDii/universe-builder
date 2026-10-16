@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_pack_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser packs retain exact dependencies, ordered members and upgrade references through refresh', () async {
    final name = 'ub-pack-test-${OperationId.generate().value}';
    var store = await BrowserPackFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        member = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final original = DomainPackRecord(
      key: 'authored-kit',
      version: '1 記憶 😀',
      dependencies: {'foundation': 'exact 記憶 😀'},
      capabilities: ['assertion.qualified.v1', 'assertion.qualified.v1'],
      records: [member, context, member],
    );
    final input = UnfinishedPackForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      key: 'authored-kit',
      version: '2 記憶 😀',
      dependencies: [
        PackDependencyInput(key: 'foundation', version: 'exact 記憶 😀'),
        PackDependencyInput(key: 'foundation', version: ''),
        PackDependencyInput(key: '', version: 'unfinished-'),
      ],
      capabilities: [
        'assertion.qualified.v1',
        'pending capability',
        'pending capability',
      ],
      records: [member.value, context.value, member.value, 'unresolved record'],
      rationale: 'Mémoire 😀\r\n',
      revisionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: original,
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserPackFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = input.copyWith(
        dependencies: input.dependencies.reversed.toList(),
        capabilities: input.capabilities.reversed.toList(),
        records: input.records.reversed.toList(),
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
        dependencies: [],
        capabilities: [],
        records: [],
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
            dependencies: [PackDependencyInput(version: '\uD800')],
          ),
          BigInt.from(3),
        ),
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
        typeClientRef: 'new-pack',
      );
      expect(await store.load(other), isNull);
      await expectLater(
        store.save(other, input, BigInt.zero),
        throwsFormatException,
      );
      final declaration = UnfinishedPackForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: 'new-pack',
      );
      await store.save(other, declaration, BigInt.zero);
      expect(
        (await store.load(other))!.form.toWire().toText(),
        declaration.toWire().toText(),
      );
      final policyScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: universe,
        continuity: scope.continuity,
        representedContext: context,
        typeClientRef: universePolicyEditorKey,
      );
      final policy = UnfinishedPackForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: RecordId.generate().value,
        key: '',
        realWorldPolicy: true,
        activatePolicy: false,
        expectedRootVersion: RecordVersionId.generate(),
        rationale: 'Still choosing 記憶.',
      );
      await store.save(policyScope, policy, BigInt.zero);
      store.close();
      store = await BrowserPackFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(policyScope))!.form.toWire().toText(),
        policy.toWire().toText(),
      );
      final scratch = policy.copyWith(
        realWorldPolicy: false,
        activatePolicy: true,
      );
      await store.save(policyScope, scratch, BigInt.one);
      expect(
        (await store.load(policyScope))!.form.toWire().toText(),
        scratch.toWire().toText(),
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
