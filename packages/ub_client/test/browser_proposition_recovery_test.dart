@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_proposition_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser propositions retain context, quantification, repeated role order and exact nested values', () async {
    final name = 'ub-proposition-test-${OperationId.generate().value}';
    var store = await BrowserPropositionFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final participant = ref();
    final original = PropositionRecord(
      predicate: ref(),
      subject: ref(),
      context: ref(),
      roles: [
        PropositionRole('listener', participant),
        PropositionRole('listener', participant),
      ],
      quantification: Quantification.exists,
      value: IntegerValue('9007199254740993123456789'),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: 'claim',
    );
    final input = UnfinishedPropositionForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'claim',
      subject: ExpressionReferenceInput(
        record: original.subject.record.value,
        universe: universe.value,
      ),
      predicate: ExpressionReferenceInput(record: 'unresolved predicate'),
      context: ExpressionReferenceInput(record: 'unresolved context'),
      quantification: 'exists',
      hasValue: true,
      value: QualifierInput(
        kind: 'object',
        children: [
          QualifierInput(
            key: 'values',
            kind: 'sequence',
            children: [
              QualifierInput(
                kind: 'integer',
                value: '9007199254740993123456789',
              ),
              QualifierInput(kind: 'rational', value: '003', denominator: '02'),
              QualifierInput(kind: 'text', value: '記憶 😀\r\n'),
            ],
          ),
        ],
      ),
      roles: [
        PropositionRoleInput(role: 'same', record: 'participant'),
        PropositionRoleInput(role: 'same', record: ''),
        PropositionRoleInput(role: 'same', record: 'participant'),
        PropositionRoleInput(role: 'other', record: 'other participant'),
      ],
      original: original,
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedPropositionForm changed(Map<String, CanonicalValue> values) =>
        UnfinishedPropositionForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(field.key, values[field.key] ?? field.value),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserPropositionFormRecoveryStore.open(
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
        'roles': CanonicalArray(input.roles.reversed.map((r) => r.toWire())),
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
      final disabled = changed({
        'roles': CanonicalArray([]),
        'has_value': CanonicalBool(false),
        'quantification': CanonicalString(''),
      });
      await store.save(scope, disabled, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      final invalid = UnfinishedPropositionForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: 'claim',
        value: QualifierInput(children: [QualifierInput(value: '\uD800')]),
      );
      await expectLater(
        store.save(scope, invalid, BigInt.from(3)),
        throwsFormatException,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
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
