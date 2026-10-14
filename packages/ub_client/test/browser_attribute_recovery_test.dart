@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_attribute_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser attribute recovery preserves nested values, creation references, evidence and role distinctions', () async {
    final name = 'ub-attribute-test-${OperationId.generate().value}';
    var store = await BrowserAttributeFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      attributeClientRef: 'pending attribute',
    );
    final value = QualifierInput(
      kind: 'object',
      originalKey: '',
      children: [
        QualifierInput(
          key: 'values',
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'integer', value: '9007199254740993123456789'),
            QualifierInput(kind: 'rational', value: '003', denominator: '02'),
            QualifierInput(kind: 'text', value: 'é😀\r\n'),
          ],
        ),
      ],
      lower: QualifierInput(value: 'unfinished-'),
      upperInclusive: 'false',
    );
    final evidence = AttributeEvidenceInput(
      precision: Precision.approximate,
      polarity: Polarity.support,
      basis: EvidenceBasisInput(
        kind: 'source',
        note: 'Mémoire 😀',
        anchorRecord: 'unresolved anchor',
        verified: false,
      ),
      scope: ScopeInput(
        applicability: 'worlds',
        worlds: ['world', '', 'world'],
        hasRealm: true,
        realmRecord: 'unresolved realm',
      ),
      validity: InstantValidity(
        DurationTime(
          calendar,
          RationalValue('9007199254740993123456789', '003'),
        ),
      ),
      temporalValidity: TemporalValidityInput(
        calendar: calendar.value,
        start: TemporalBoundInput(value: 'unfinished-'),
      ),
      alternatives: [
        QualifierInput(kind: 'integer', value: '9007199254740993123456789'),
      ],
    );
    final creation = AttributeCreationInput(
      subject: VersionRef(
        universe: universe,
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
      ),
      operationRef: 'new fact',
      propertyRecord: 'unresolved property',
      propertyUniverse: '',
      relationship: true,
    );
    final roles = [
      PropositionRoleInput(
        role: 'same',
        record: 'unresolved participant',
        universe: '',
      ),
      PropositionRoleInput(role: 'same', record: '', universe: universe.value),
    ];
    final revision = RevisionId.generate(),
        draftVersion = BigInt.parse('9007199254740993');
    UnfinishedAttributeForm form({
      QualifierInput? enteredValue,
      AttributeEvidenceInput? enteredEvidence,
      AttributeCreationInput? enteredCreation,
      List<PropositionRoleInput>? enteredRoles,
    }) => UnfinishedAttributeForm(
      baseRevision: revision,
      representedContext: context,
      clientRef: scope.attributeClientRef!,
      draftVersion: draftVersion,
      value: enteredValue ?? value,
      evidenceInput: enteredEvidence,
      creationInput: enteredCreation,
      roles: enteredRoles,
    );
    final input = form(
      enteredEvidence: evidence,
      enteredCreation: creation,
      enteredRoles: roles,
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserAttributeFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final reversed = form(
        enteredEvidence: evidence,
        enteredCreation: creation,
        enteredRoles: roles.reversed.toList(),
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
      final omitted = form();
      await store.save(scope, omitted, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        omitted.toWire().toText(),
      );
      final cleared = form(
        enteredRoles: [],
        enteredEvidence: AttributeEvidenceInput(alternatives: []),
      );
      await store.save(scope, cleared, BigInt.from(3));
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        cleared.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          form(
            enteredValue: QualifierInput(
              children: [QualifierInput(value: '\uD800')],
            ),
          ),
          BigInt.from(4),
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
        attributeClientRef: 'different',
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
