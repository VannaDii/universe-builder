import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/communication_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
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
