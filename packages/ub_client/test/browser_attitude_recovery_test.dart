@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_attitude_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser attitudes retain stance, authored certainty, acquisition references and exact temporal input', () async {
    final name = 'ub-attitude-test-${OperationId.generate().value}';
    var store = await BrowserAttitudeFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final original = EpistemicAttitudeRecord(
      holder: ref(),
      proposition: ref(),
      attitude: EpistemicAttitudeKind.values.first,
      certainty: 'Authored certainty',
      validity: UnspecifiedValidity(),
      basis: AuthorDecisionBasis('Original basis 記憶 😀'),
      acquisition: KnowledgeAcquisition(
        truthContext: ref(),
        time: ExactTime(calendar, '9007199254740993123456789'),
        basis: CommunicationKnowledge(
          communication: ref(),
          interpretation: ref(),
        ),
      ),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final input = UnfinishedAttitudeForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      holder: ExpressionReferenceInput(
        record: original.holder.record.value,
        universe: universe.value,
      ),
      proposition: ExpressionReferenceInput(record: 'unresolved proposition'),
      attitude: 'unresolved stance',
      certaintyEnabled: true,
      certainty: 'Mémoire 😀\r\n',
      validity: TemporalValidityInput(
        calendar: calendar.value,
        start: TemporalBoundInput(value: '9007199254740993123456789'),
        end: TemporalBoundInput(value: 'unfinished-'),
      ),
      basis: EvidenceBasisInput(
        kind: 'source',
        note: 'Entered note',
        anchorRecord: 'unresolved anchor',
        verified: false,
      ),
      acquisition: KnowledgeAcquisitionInput(
        enabled: true,
        truthContext: ExpressionReferenceInput(record: 'unresolved context'),
        time: TemporalValidityInput(
          kind: 'instant_exact',
          calendar: calendar.value,
          start: TemporalBoundInput(value: '9007199254740993123456789'),
        ),
        worldEnabled: true,
        world: ExpressionReferenceInput(record: 'unresolved world'),
        basis: 'communication',
        communication: ExpressionReferenceInput(record: 'unresolved message'),
        interpretationEnabled: true,
        interpretation: ExpressionReferenceInput(
          record: 'unresolved interpretation',
        ),
      ),
      original: original,
      correctionTarget: ExpressionReferenceInput(
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
      store = await BrowserAttitudeFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(scope, input, BigInt.zero)).generation,
        BigInt.one,
      );
      final disabled = input.copyWith(
        certaintyEnabled: false,
        acquisition: input.acquisition.copyWith(
          enabled: false,
          worldEnabled: false,
          interpretationEnabled: false,
        ),
      );
      await expectLater(
        store.save(scope, disabled, BigInt.zero),
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
      await store.save(scope, disabled, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        disabled.toWire().toText(),
      );
      final incomplete = input.copyWith(
        attitude: '',
        certainty: '',
        basis: EvidenceBasisInput(),
        acquisition: KnowledgeAcquisitionInput(),
        validity: TemporalValidityInput(),
      );
      await store.save(scope, incomplete, BigInt.two);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      await expectLater(
        store.save(
          scope,
          incomplete.copyWith(
            acquisition: KnowledgeAcquisitionInput(basis: '\uD800'),
          ),
          BigInt.from(3),
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
