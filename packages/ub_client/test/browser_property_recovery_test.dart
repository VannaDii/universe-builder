@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_property_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser property revisions retain shapes, relation flags, original definitions and incomplete choices', () async {
    final name = 'ub-property-test-${OperationId.generate().value}';
    var store = await BrowserPropertyFormRecoveryStore.open(databaseName: name);
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
    final original = PropertyRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'ja': '記憶 😀', '': ''},
      subjectTypes: [RecordId.generate()],
      value: SequenceShape(StructuredShape(ValueDefinitionId.generate())),
      multiplicity: Multiplicity.multiple,
      persistence: PersistenceSemantics.conditionDependent,
      unitDimension: '',
      inverse: 'inverse 😀',
      exclusive: true,
      symmetric: true,
      transitive: true,
    );
    final input = UnfinishedPropertyForm(
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
      subjectTypes: ['unresolved type', '', 'unresolved type'],
      shape: ValueShapeInput(
        kind: 'sequence',
        item: ValueShapeInput(
          kind: 'sequence',
          item: ValueShapeInput(
            kind: 'quantity',
            unit: 'unresolved unit',
            definition: 'unresolved definition',
            subjectTypes: ['', 'type', 'type'],
          ),
        ),
      ),
      multiplicity: 'multiple',
      persistence: '',
      hasUnitDimension: true,
      unitDimension: '',
      hasInverse: true,
      inverse: 'pending inverse',
      exclusive: true,
      symmetric: false,
      transitive: true,
      rationale: '',
      revisionTarget: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: original,
      draftVersion: BigInt.parse('9007199254740993'),
    );
    UnfinishedPropertyForm changed(Map<String, CanonicalValue> updates) =>
        UnfinishedPropertyForm.fromWire(
          CanonicalObject(
            input.toWire().fields.map(
              (field) => MapEntry(field.key, updates[field.key] ?? field.value),
            ),
          ),
        );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserPropertyFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final cleared = changed({
        'labels': CanonicalArray([]),
        'subject_types': CanonicalArray([]),
        'has_inverse': CanonicalBool(false),
        'has_unit_dimension': CanonicalBool(false),
        'exclusive': CanonicalBool(false),
        'symmetric': CanonicalBool(true),
        'transitive': CanonicalBool(false),
      });
      await expectLater(
        store.save(scope, cleared, BigInt.zero),
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
      expect(
        (await store.save(scope, cleared, BigInt.one)).generation,
        BigInt.two,
      );
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      final invalid = UnfinishedPropertyForm(
        baseRevision: input.baseRevision,
        representedContext: context,
        clientRef: record.value,
        shape: ValueShapeInput(
          kind: 'sequence',
          item: ValueShapeInput(unit: '\uD800'),
        ),
      );
      await expectLater(
        store.save(scope, invalid, BigInt.two),
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
