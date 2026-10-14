import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/assertion_retraction_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'assertion retraction recovers rationale with unchanged target version',
    () {
      final root = Directory('/tmp')
              .createTempSync('ub-assertionRetraction-form-'),
          universe = UniverseId.generate(),
          context = RecordId.generate();
      RecordRef ref() =>
          RecordRef(universe: universe, record: RecordId.generate());
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
        validity: const UnspecifiedValidity(),
        basis: const AuthorDecisionBasis('Authored account'),
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
      final form = assertionRetractionFormFromRecord(
        record: source,
        baseRevision: RevisionId.generate(),
        representedContext: context,
      ).copyWith(rationale: 'Correct the recorded assertionRetraction.');
      var store = AssertionRetractionFormRecoveryStore.open(
        '${root.path}/forms.sqlite',
      );
      try {
        store.save(scope, form, BigInt.zero);
        store.close();
        store = AssertionRetractionFormRecoveryStore.open(
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
        final add = assertionRetractionDraftRequest(
          draft: empty,
          form: recovered,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        );
        final saved = SavedDraft(version: BigInt.two, content: add.content),
            pending = assertionRetractionFormFromDraft(
              SavedDraft(version: BigInt.two, content: add.content),
              0,
            );
        expect(
          assertionRetractionOperation(pending).toWire().toText(),
          assertionRetractionOperation(form).toWire().toText(),
        );
        final edited = assertionRetractionDraftRequest(
          draft: saved,
          form: pending.copyWith(
            rationale: 'Remove unresolved assertionRetraction.',
          ),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        );
        final op =
            edited.content.operations.single as RetractAssertionOperation;
        expect(op.record.record, source.identity.recordId);
        expect(op.expectedVersion, source.recordVersionId);
        expect(op.rationale, 'Remove unresolved assertionRetraction.');
        expect(
          () => assertionRetractionDraftRequest(
            draft: SavedDraft(version: BigInt.from(3), content: saved.content),
            form: pending,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        final changedPin = UnfinishedAssertionRetractionForm.fromWire(
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
          () => assertionRetractionDraftRequest(
            draft: saved,
            form: changedPin,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        expect(
          assertionRetractionDraftRequest(
            draft: saved,
            form: form,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
          ).content.operations.length,
          1,
        );
        expect(
          () => assertionRetractionDraftRequest(
            draft: saved,
            form: form.copyWith(rationale: 'Different reason'),
            universe: const Selector('Universe'),
            continuity: scope.continuity,
          ),
          throwsFormatException,
        );
        final incomplete = form.copyWith(rationale: '');
        store.save(scope, incomplete, BigInt.one);
        expect(
          store.load(scope)!.form.toWire().toText(),
          incomplete.toWire().toText(),
        );
        expect(
          () => assertionRetractionOperation(incomplete),
          throwsFormatException,
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
