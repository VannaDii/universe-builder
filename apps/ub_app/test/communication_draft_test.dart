import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/communication_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('published message correction retains target version and exact times through recovery and edits', () {
    final root = Directory('/tmp').createTempSync('ub-message-correction-'),
        universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final intended = ref(), actual = ref(), claim = ref();
    final payload = CommunicationRecord(
      sender: ref(),
      intendedRecipients: [intended, intended],
      actualRecipients: [actual],
      content: [claim, claim],
      channel: 'mail',
      distorted: false,
      sentAt: ExactTime(calendar, '9007199254740993'),
      receivedAt: ExactTime(calendar, '9007199254740997'),
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.communication,
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
        communicationCorrectionFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        ).copyWith(
          receivedAt: TemporalValidityInput(
            kind: 'instant',
            calendar: calendar.value,
            start: const TemporalBoundInput(value: '9007199254740999'),
          ),
          rationale: 'Correct the receipt time.',
        );
    var store = CommunicationFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = CommunicationFormRecoveryStore.open('${root.path}/forms.sqlite');
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
      final add = communicationDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content);
      final pending = UnfinishedCommunicationForm.fromWire(
        communicationFormFromDraft(saved, 0).toWire(),
      );
      expect(
        communicationCorrectionOperation(pending).toWire().toText(),
        communicationCorrectionOperation(form).toWire().toText(),
      );
      final edit = communicationDraftRequest(
        draft: saved,
        form: pending.copyWith(
          actualRecipients: [],
          receivedEnabled: false,
          channelEnabled: false,
          rationale: 'Correct the recorded delivery.',
        ),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseCommunicationOperation;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(op.rationale, 'Correct the recorded delivery.');
      expect(op.replacement.sender, payload.sender);
      expect(op.replacement.intendedRecipients, payload.intendedRecipients);
      expect(op.replacement.content, payload.content);
      expect(op.replacement.receivedAt, isNull);
      expect(op.replacement.actualRecipients, isEmpty);
      expect(op.replacement.channel, isNull);
      expect(
        op.replacement.sentAt.encode(canonical: true).toText(),
        payload.sentAt.encode(canonical: true).toText(),
      );
      expect(
        () => communicationDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        communicationDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ).content.operations.length,
        1,
      );
      expect(
        () => communicationDraftRequest(
          draft: saved,
          form: form.copyWith(channel: 'changed'),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      final changedPin = UnfinishedCommunicationForm.fromWire(
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
        () => communicationDraftRequest(
          draft: saved,
          form: changedPin,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('communication edits keep repeated intended recipients distinct from actual receipt', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        calendar = CalendarId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final intended = ref(), actual = ref(), claim = ref();
    final record = CommunicationRecord(
      sender: ref(),
      intendedRecipients: [intended, intended],
      actualRecipients: [actual],
      content: [claim, claim],
      channel: '',
      distorted: false,
      sentAt: ExactTime(calendar, '9007199254740993'),
      receivedAt: ExactTime(calendar, '9007199254740997'),
    );
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [
          RecordCommunicationOperation(clientRef: 'message', record: record),
        ],
        rationale: 'Keep intended delivery separate from actual receipt.',
      ),
    );
    final form = UnfinishedCommunicationForm.fromWire(
      communicationFormFromDraft(draft, 0).toWire(),
    );
    expect(
      communicationOperation(form).record.toWire().toText(),
      record.toWire().toText(),
    );
    expect(
      () => communicationOperation(form.copyWith(receivedEnabled: false)),
      throwsFormatException,
    );
    final changed = form.copyWith(
      actualRecipients: [],
      receivedEnabled: false,
      channelEnabled: false,
      distorted: true,
    );
    final request = communicationDraftRequest(
      draft: draft,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next =
        (request.content.operations.single as RecordCommunicationOperation)
            .record;
    expect(next.actualRecipients, isEmpty);
    expect(next.receivedAt, isNull);
    expect(next.channel, isNull);
    expect(next.distorted, isTrue);
    expect(next.intendedRecipients, record.intendedRecipients);
    expect(next.content, record.content);
    expect(
      next.sentAt.encode(canonical: false).toText(),
      record.sentAt.encode(canonical: false).toText(),
    );
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => communicationDraftRequest(
        draft: SavedDraft(version: BigInt.from(7), content: draft.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('unfinished messages recover without inferring distortion receipt or recipients', () {
    final root = Directory('/tmp').createTempSync('ub-communication-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedCommunicationForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      channelEnabled: true,
      channel: 'unfinished 記憶 😀',
      intendedRecipients: [
        const ExpressionReferenceInput(record: 'unfinished'),
      ],
      content: [const ExpressionReferenceInput(record: 'unfinished claim')],
    );
    var store = CommunicationFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = CommunicationFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.distorted, isNull);
      expect(recovered.actualRecipients, isEmpty);
      expect(recovered.receivedEnabled, isFalse);
      expect(() => communicationOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(distorted: false), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
