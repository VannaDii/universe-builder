import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/assertion_end_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('assertion ending recovers exact coordinate and basis with unchanged calendar and version', () {
    final root = Directory('/tmp').createTempSync('ub-assertionEnd-form-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final calendar = CalendarId.generate();
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
    final form =
        assertionEndFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        ).copyWith(
          coordinate: '9007199254740997',
          rationale: 'End the declared interval.',
        );
    var store = AssertionEndFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = AssertionEndFormRecoveryStore.open('${root.path}/forms.sqlite');
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
      final add = assertionEndDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = assertionEndFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      expect(
        assertionEndOperation(pending).toWire().toText(),
        assertionEndOperation(form).toWire().toText(),
      );
      final edited = assertionEndDraftRequest(
        draft: saved,
        form: pending.copyWith(
          coordinate: '9007199254740999',
          basis: const EvidenceBasisInput(
            kind: 'author_decision',
            note: 'Authored ending 記憶 😀',
          ),
        ),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edited.content.operations.single as EndAssertionAtOperation;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect((op.at as ExactTime).calendar, calendar);
      expect((op.at as ExactTime).value, '9007199254740999');
      expect(op.basis, const AuthorDecisionBasis('Authored ending 記憶 😀'));
      expect(
        () => assertionEndDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final changedPin = UnfinishedAssertionEndForm.fromWire(
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
        () => assertionEndDraftRequest(
          draft: saved,
          form: changedPin,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        assertionEndDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ).content.operations.length,
        1,
      );
      expect(
        () => assertionEndDraftRequest(
          draft: saved,
          form: form.copyWith(coordinate: '9007199254740999'),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      final incomplete = form.copyWith(coordinate: '');
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(() => assertionEndOperation(incomplete), throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
