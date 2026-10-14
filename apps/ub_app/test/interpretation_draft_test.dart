import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/interpretation_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('receipt interpretation correction recovers selection and explicit clearing with unchanged target version', () {
    final root = Directory('/tmp').createTempSync('ub-interpretation-form-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final payload = EpistemicAttitudeRecord(
      holder: ref(),
      proposition: ref(),
      attitude: EpistemicAttitudeKind.knows,
      validity: const UnspecifiedValidity(),
      basis: const AuthorDecisionBasis('Receipt knowledge'),
      acquisition: KnowledgeAcquisition(
        truthContext: ref(),
        time: const UnspecifiedTime(),
        basis: CommunicationKnowledge(
          communication: ref(),
          interpretation: ref(),
        ),
      ),
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.epistemicAttitude,
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
    final form = interpretationFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    ).copyWith(rationale: 'Correct the recorded interpretation.');
    var store = InterpretationFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = InterpretationFormRecoveryStore.open('${root.path}/forms.sqlite');
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
      final add = interpretationDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = interpretationFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      expect(
        interpretationOperation(pending).toWire().toText(),
        interpretationOperation(form).toWire().toText(),
      );
      final edited = interpretationDraftRequest(
        draft: saved,
        form: pending.copyWith(
          interpretationEnabled: false,
          rationale: 'Remove unresolved interpretation.',
        ),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op =
          edited.content.operations.single as ReviseInterpretationOperation;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(op.interpretation, isNull);
      expect(op.rationale, 'Remove unresolved interpretation.');
      expect(
        () => interpretationDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final changedPin = UnfinishedInterpretationForm.fromWire(
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
        () => interpretationDraftRequest(
          draft: saved,
          form: changedPin,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        interpretationDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ).content.operations.length,
        1,
      );
      expect(
        () => interpretationDraftRequest(
          draft: saved,
          form: form.copyWith(interpretationEnabled: false),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      final incomplete = form.copyWith(
        interpretation: const ExpressionReferenceInput(
          record: 'unfinished 記憶 😀',
        ),
      );
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(() => interpretationOperation(incomplete), throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
