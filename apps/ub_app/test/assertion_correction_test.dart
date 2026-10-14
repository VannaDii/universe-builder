import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/assertion_correction_draft.dart';
import 'package:ub_app/qualifier_draft.dart';
import 'package:ub_app/scope_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('assertion correction preserves provenance and exact fields through recovery and pending edits', () {
    final root = Directory('/tmp')
            .createTempSync('ub-assertionCorrection-form-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final calendar = CalendarId.generate();
    final event = EventEffectRef(ref(), 'effect 記憶 😀');
    final payload = AssertionRecord(
      attributeMode: AttributeMode.instance,
      precision: Precision.exact,
      persistence: PersistenceSemantics.unspecified,
      proposition: ref(),
      polarity: Polarity.support,
      scope: Scope(
        context: ref(),
        applicability: const UniverseApplicability(),
      ),
      validity: CalendarIntervalValidity(
        calendar,
        const ExactBound('0'),
        const UnboundedBound(),
      ),
      alternatives: [
        SequenceValue([
          IntegerValue('9007199254740997'),
          const TextValue('記憶 😀'),
        ]),
        const RationalValue('3', '2'),
      ],
      establishedBy: event,
      basis: EventEffectBasis(event.event, event.slot),
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.assertion,
      ),
      payload: payload,
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    final form = assertionCorrectionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    ).copyWith(rationale: 'Correct the recorded assertionCorrection.');
    var store = AssertionCorrectionFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = AssertionCorrectionFormRecoveryStore.open(
        '${root.path}/forms.sqlite',
      );
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final empty = SavedDraft(
        version: BigInt.one,
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: context,
          operations: [],
          rationale: '',
        ),
      );
      final add = assertionCorrectionDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = assertionCorrectionFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      expect(
        assertionCorrectionOperation(pending).toWire().toText(),
        assertionCorrectionOperation(form).toWire().toText(),
      );
      final edited = assertionCorrectionDraftRequest(
        draft: saved,
        form: pending.copyWith(
          rationale: 'Correct the attributed scope and evidence.',
          proposition: ExpressionReferenceInput(record: ref().record.value),
          evidence: AttributeEvidenceInput(
            attributeMode: AttributeMode.shared,
            polarity: Polarity.refutation,
            precision: Precision.oneOf,
            persistence: PersistenceSemantics.explicitInterval,
            scope: scopeInput(
              Scope(
                context: ref(),
                applicability: const ConditionalApplicability(),
                realm: ref(),
              ),
            ),
            validity: CalendarIntervalValidity(
              calendar,
              const ExactBound('0'),
              const ExactBound('9007199254740999'),
            ),
            alternatives: [
              for (var i = payload.alternatives.length - 1; i >= 0; i--)
                qualifierInput(i.toString(), payload.alternatives[i]),
            ],
            basis: const EvidenceBasisInput(
              kind: 'author_decision',
              note: 'Corrected attributed account 記憶 😀',
            ),
          ),
        ),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op =
          edited.content.operations.single as SupersedeAssertionOperation;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(op.rationale, 'Correct the attributed scope and evidence.');
      final replacement = op.replacement;
      expect(replacement.establishedBy, event);
      expect(replacement.proposition.universe, isNull);
      expect(replacement.attributeMode, AttributeMode.shared);
      expect(replacement.polarity, Polarity.refutation);
      expect(replacement.precision, Precision.oneOf);
      expect(replacement.persistence, PersistenceSemantics.explicitInterval);
      expect(replacement.scope.applicability, isA<ConditionalApplicability>());
      expect(replacement.scope.realm, isNotNull);
      expect(
        replacement.validity.toWire().toText(),
        CalendarIntervalValidity(
          calendar,
          const ExactBound('0'),
          const ExactBound('9007199254740999'),
        ).toWire().toText(),
      );
      expect(
        replacement.alternatives.map((v) => v.toWire().toText()),
        payload.alternatives.reversed.map((v) => v.toWire().toText()),
      );
      expect(
        replacement.basis,
        const AuthorDecisionBasis('Corrected attributed account 記憶 😀'),
      );
      expect(
        assertionCorrectionOperation(form).replacement.toWire().toText(),
        payload.toWire().toText(),
      );
      expect(
        () => assertionCorrectionDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final changedPin = UnfinishedAssertionCorrectionForm.fromWire(
        CanonicalObject(
          pending.toWire().fields.map(
            (e) => e.key == 'expected_record_version'
                ? MapEntry(
                    e.key,
                    CanonicalString(RecordVersionId.generate().value),
                  )
                : e,
          ),
        ),
      );
      expect(
        () => assertionCorrectionDraftRequest(
          draft: saved,
          form: changedPin,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        assertionCorrectionDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ).content.operations.length,
        1,
      );
      expect(
        () => assertionCorrectionDraftRequest(
          draft: saved,
          form: form.copyWith(rationale: 'Different reason'),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      final incomplete = form.copyWith(
        proposition: const ExpressionReferenceInput(record: 'unfinished 記憶 😀'),
        evidence: const AttributeEvidenceInput(
          alternatives: [
            QualifierInput(
              kind: 'rational',
              value: 'unfinished',
              denominator: '',
            ),
          ],
        ),
      );
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => assertionCorrectionOperation(incomplete),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
