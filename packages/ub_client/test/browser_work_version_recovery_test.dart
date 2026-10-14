@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_work_version_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser editions retain continuity pins, ordered segments and incomplete binding fields', () async {
    final name = 'ub-edition-test-${OperationId.generate().value}';
    var store = await BrowserWorkVersionFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final input = UnfinishedWorkVersionForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      work: ExpressionReferenceInput(
        record: RecordId.generate().value,
        universe: universe.value,
      ),
      versionLabel: 'Edition 記憶 😀\r\n',
      bindingKind: 'segments',
      continuity: ContinuityId.generate().value,
      revision: RevisionId.generate().value,
      segments: [
        WorkSegmentInput(
          segment: 'same',
          continuity: ContinuityId.generate().value,
          revision: RevisionId.generate().value,
        ),
        WorkSegmentInput(
          segment: 'same',
          continuity: '',
          revision: 'unfinished revision',
        ),
      ],
      bindingTarget: ExpressionReferenceInput(
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
      store = await BrowserWorkVersionFormRecoveryStore.open(
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
      final reversed = input.copyWith(
        segments: input.segments.reversed.toList(),
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
      final bound = input.copyWith(bindingKind: 'bound', segments: []);
      await store.save(scope, bound, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        bound.toWire().toText(),
      );
      final incomplete = input.copyWith(
        bindingKind: '',
        continuity: '',
        revision: '',
        work: ExpressionReferenceInput(),
      );
      await store.save(scope, incomplete, BigInt.from(3));
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          incomplete.copyWith(segments: [WorkSegmentInput(segment: '\uD800')]),
          BigInt.from(4),
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
