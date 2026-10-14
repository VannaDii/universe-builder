@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_assertion_correction_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser assertion corrections retain provenance, scope and exact nested evidence through refresh', () async {
    final name = 'ub-assertion-correction-test-${OperationId.generate().value}';
    var store = await BrowserAssertionCorrectionFormRecoveryStore.open(
      databaseName: name,
    );
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final event = EventEffectRef(ref(), 'effect 記憶 😀');
    final original = AssertionRecord(
      attributeMode: AttributeMode.instance,
      precision: Precision.exact,
      persistence: PersistenceSemantics.unspecified,
      proposition: ref(),
      polarity: Polarity.support,
      scope: Scope(context: ref(), applicability: UniverseApplicability()),
      validity: CalendarIntervalValidity(
        calendar,
        ExactBound('0'),
        UnboundedBound(),
      ),
      alternatives: [
        SequenceValue([
          IntegerValue('9007199254740993123456789'),
          TextValue('記憶 😀'),
        ]),
        RationalValue('003', '02'),
      ],
      establishedBy: event,
      basis: EventEffectBasis(event.event, event.slot),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: record.value,
    );
    final input = UnfinishedAssertionCorrectionForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: record.value,
      target: ExpressionReferenceInput(
        record: record.value,
        universe: universe.value,
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      original: original,
      proposition: ExpressionReferenceInput(
        record: 'unresolved proposition',
        universe: '',
      ),
      evidence: AttributeEvidenceInput(
        attributeMode: AttributeMode.instance,
        polarity: Polarity.support,
        precision: Precision.approximate,
        persistence: PersistenceSemantics.unspecified,
        basis: EvidenceBasisInput(
          kind: 'source',
          note: 'Mémoire 😀\r\n',
          anchorRecord: 'unresolved anchor',
          verified: false,
        ),
        scope: ScopeInput(
          applicability: 'worlds',
          worlds: ['unresolved world', '', 'unresolved world'],
          contextRecord: context.value,
          contextUniverse: universe.value,
          hasRealm: true,
          realmRecord: 'unresolved realm',
          realmUniverse: '',
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
          end: TemporalBoundInput(
            kind: 'approximate',
            value: '9007199254740993123456789',
            uncertainty: '±?',
          ),
        ),
        alternatives: [
          QualifierInput(
            kind: 'sequence',
            children: [
              QualifierInput(
                kind: 'integer',
                value: '9007199254740993123456789',
              ),
              QualifierInput(kind: 'text', value: 'é😀\r\n'),
            ],
          ),
          QualifierInput(kind: 'rational', value: '003', denominator: '02'),
        ],
      ),
      rationale: '',
      draftVersion: BigInt.parse('9007199254740993'),
    );
    try {
      await store.save(scope, input, BigInt.zero);
      store.close();
      store = await BrowserAssertionCorrectionFormRecoveryStore.open(
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
      final omitted = input.copyWith(evidence: AttributeEvidenceInput());
      await expectLater(
        store.save(scope, omitted, BigInt.zero),
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
      await store.save(scope, omitted, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        omitted.toWire().toText(),
      );
      final cleared = input.copyWith(
        evidence: AttributeEvidenceInput(
          alternatives: [],
          scope: ScopeInput(worlds: [], hasRealm: false),
        ),
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
            evidence: AttributeEvidenceInput(
              alternatives: [
                QualifierInput(children: [QualifierInput(value: '\uD800')]),
              ],
            ),
          ),
          BigInt.from(3),
        ),
        throwsFormatException,
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
