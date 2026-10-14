import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/attitude_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('published attitude correction preserves stance, evidence and acquisition and restricts knowledge', () {
    final root = Directory('/tmp').createTempSync('ub-attitude-correction-'),
        universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    var store = AttitudeFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      for (final kind in EpistemicAttitudeKind.values) {
        final payload = EpistemicAttitudeRecord(
          holder: ref(),
          proposition: ref(),
          attitude: kind,
          certainty: 'Authored certainty',
          validity: const UnspecifiedValidity(),
          basis: const AuthorDecisionBasis('Original basis'),
          acquisition: KnowledgeAcquisition(
            truthContext: ref(),
            time: ExactTime(calendar, '9007199254740997'),
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
        final form =
            attitudeCorrectionFormFromRecord(
              record: source,
              baseRevision: RevisionId.generate(),
              representedContext: context,
            ).copyWith(
              validity: const TemporalValidityInput(
                kind: 'condition_dependent',
              ),
              rationale: 'Correct the recorded duration.',
            );
        store.save(scope, form, BigInt.zero);
        store.close();
        store = AttitudeFormRecoveryStore.open('${root.path}/forms.sqlite');
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
        final add = attitudeDraftRequest(
          draft: empty,
          form: recovered,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        );
        final saved = SavedDraft(version: BigInt.two, content: add.content);
        final pending = UnfinishedAttitudeForm.fromWire(
          attitudeFormFromDraft(saved, 0).toWire(),
        );
        expect(
          attitudeCorrectionOperation(pending).toWire().toText(),
          attitudeCorrectionOperation(form).toWire().toText(),
        );
        final edited = attitudeDraftRequest(
          draft: saved,
          form: pending.copyWith(rationale: 'Explain the duration correction.'),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        );
        final op = edited.content.operations.single as ReviseAttitudeOperation;
        expect(op.record.record, source.identity.recordId);
        expect(op.expectedVersion, source.recordVersionId);
        expect(op.rationale, 'Explain the duration correction.');
        expect(op.replacement.holder, payload.holder);
        expect(op.replacement.attitude, kind);
        expect(op.replacement.basis, payload.basis);
        expect(
          op.replacement.acquisition!.toWire().toText(),
          payload.acquisition!.toWire().toText(),
        );
        expect(
          () => attitudeCorrectionOperation(
            form.copyWith(
              holder: ExpressionReferenceInput(
                record: RecordId.generate().value,
              ),
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => attitudeCorrectionOperation(
            form.copyWith(
              acquisition: form.acquisition.copyWith(enabled: false),
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => attitudeCorrectionOperation(
            form.copyWith(
              basis: const EvidenceBasisInput(
                kind: 'author_decision',
                note: 'Other',
              ),
            ),
          ),
          throwsFormatException,
        );
        if (kind == EpistemicAttitudeKind.knows) {
          expect(
            () =>
                attitudeCorrectionOperation(form.copyWith(certainty: 'Other')),
            throwsFormatException,
          );
          expect(
            () => attitudeCorrectionOperation(
              form.copyWith(
                proposition: ExpressionReferenceInput(
                  record: RecordId.generate().value,
                ),
              ),
            ),
            throwsFormatException,
          );
        } else {
          expect(
            attitudeCorrectionOperation(form.copyWith(certainty: 'Other'))
                .replacement
                .certainty,
            'Other',
          );
        }
        expect(
          () => attitudeDraftRequest(
            draft: SavedDraft(version: BigInt.from(3), content: saved.content),
            form: pending,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        final changedPin = UnfinishedAttitudeForm.fromWire(
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
          () => attitudeDraftRequest(
            draft: saved,
            form: changedPin,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('attitude editing retains exact acquisition links world time and certainty absence', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final record = EpistemicAttitudeRecord(
      holder: ref(),
      proposition: ref(),
      attitude: EpistemicAttitudeKind.knows,
      certainty: '',
      validity: const ConditionalValidity(),
      basis: const AuthorDecisionBasis('Recorded 記憶 😀'),
      acquisition: KnowledgeAcquisition(
        truthContext: ref(),
        time: ExactTime(calendar, '9007199254740997'),
        world: ref(),
        basis: CommunicationKnowledge(
          communication: ref(),
          interpretation: ref(),
        ),
      ),
    );
    final draft = SavedDraft(
      version: BigInt.from(8),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [AddBeliefOperation(clientRef: 'attitude', record: record)],
        rationale: 'Keep the acquisition and the authored stance.',
      ),
    );
    final form = UnfinishedAttitudeForm.fromWire(
      attitudeFormFromDraft(draft, 0).toWire(),
    );
    expect(
      attitudeOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    final changed = form.copyWith(
      attitude: 'suspects',
      certaintyEnabled: false,
      acquisition: form.acquisition.copyWith(enabled: false),
    );
    final request = attitudeDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as AddBeliefOperation).record;
    expect(next.attitude, EpistemicAttitudeKind.suspects);
    expect(next.acquisition, isNull);
    expect(next.certainty, isNull);
    expect(next.basis.toWire().toText(), record.basis.toWire().toText());
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => attitudeDraftRequest(
        draft: SavedDraft(version: BigInt.from(9), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    final universeWide = form.copyWith(
      acquisition: form.acquisition.copyWith(
        worldEnabled: false,
        basis: 'author_established',
        interpretationEnabled: false,
      ),
    );
    final acquisition = attitudeOperation(universeWide).record.acquisition!;
    expect(acquisition.world, isNull);
    expect(acquisition.basis, isA<AuthorEstablishedKnowledge>());
    expect(
      acquisition.time.encode(canonical: false).toText(),
      record.acquisition!.time.encode(canonical: false).toText(),
    );
  });
  test('unfinished attitudes recover without inferring stance or acquisition basis', () {
    final root = Directory('/tmp').createTempSync('ub-attitude-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedAttitudeForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      certaintyEnabled: true,
      certainty: 'uncertain 記憶 😀',
      acquisition: const KnowledgeAcquisitionInput(
        enabled: true,
        communication: ExpressionReferenceInput(record: 'unfinished'),
      ),
    );
    var store = AttitudeFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = AttitudeFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.attitude, isEmpty);
      expect(recovered.acquisition.basis, isEmpty);
      expect(() => attitudeOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(
          scope,
          form.copyWith(certainty: 'another edit'),
          BigInt.zero,
        ),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
