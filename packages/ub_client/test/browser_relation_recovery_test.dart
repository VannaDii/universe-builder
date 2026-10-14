@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_relation_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser relation revisions retain role order, repeated participants, cardinality and original versions', () async {
    final name = 'ub-relation-test-${OperationId.generate().value}';
    var store = await BrowserRelationFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        type = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final original = RelationRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'ja': '記憶 😀', '': ''},
      roles: [
        RoleDefinition(
          name: 'speaker',
          participantTypes: [type, type],
          multiplicity: Multiplicity.single,
          ordered: false,
        ),
        RoleDefinition(
          name: 'listeners',
          participantTypes: [],
          multiplicity: Multiplicity.multiple,
          ordered: true,
        ),
      ],
    );
    final input = UnfinishedRelationForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      namespace: 'authored',
      key: 'account',
      labels: [
        PropertyLabelInput(language: 'fr', text: 'Mémoire 😀\r\n'),
        PropertyLabelInput(language: 'fr', text: ''),
        PropertyLabelInput(language: '', text: ''),
      ],
      roles: [
        RelationRoleInput(
          name: 'same',
          participantTypes: ['unresolved type', '', 'unresolved type'],
          multiplicity: 'multiple',
          ordered: true,
        ),
        RelationRoleInput(
          name: 'same',
          participantTypes: [],
          multiplicity: '',
          ordered: false,
        ),
      ],
      rationale: '',
      revisionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: original,
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedRelationForm changed(
      List<RelationRoleInput> roles, {
      bool clearLabels = false,
    }) => UnfinishedRelationForm.fromWire(
      CanonicalObject(
        input.toWire().fields.map(
          (field) => MapEntry(
            field.key,
            field.key == 'roles'
                ? CanonicalArray(roles.map((r) => r.toWire()))
                : field.key == 'labels' && clearLabels
                ? CanonicalArray([])
                : field.value,
          ),
        ),
      ),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserRelationFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = changed(input.roles.reversed.toList());
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
      final cleared = changed([], clearLabels: true);
      await store.save(scope, cleared, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      final invalid = UnfinishedRelationForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: record.value,
        roles: [
          RelationRoleInput(participantTypes: ['\uD800']),
        ],
      );
      await expectLater(
        store.save(scope, invalid, BigInt.from(3)),
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
