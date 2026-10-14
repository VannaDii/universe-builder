import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/event_withdrawal_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'occurrence withdrawal recovers reason with unchanged event version',
    () {
      final root = Directory('/tmp').createTempSync('ub-eventWithdrawal-form-'),
          universe = UniverseId.generate(),
          context = RecordId.generate();
      final payload = EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        time: ExactTime(CalendarId.generate(), '9007199254740997'),
        participants: [],
        labels: {'en': 'Arrival 記憶 😀'},
      );
      final source = RecordVersion.build(
        recordVersionId: RecordVersionId.generate(),
        identity: RecordIdentity(
          universeId: universe,
          recordId: RecordId.generate(),
          recordKind: RecordKind.event,
        ),
        payload: payload,
      );
      expect(isWithdrawableEvent(payload), isTrue);
      for (final occurrence in [
        OccurrenceKind.planned,
        OccurrenceKind.reported,
      ]) {
        final notOccurred = RecordVersion.build(
          recordVersionId: source.recordVersionId,
          identity: source.identity,
          payload: EventRecord(
            occurrence: SimpleOccurrence(occurrence),
            time: payload.time,
            participants: [],
            labels: {},
          ),
        );
        expect(isWithdrawableEvent(notOccurred.payload), isFalse);
        expect(
          () => eventWithdrawalFormFromRecord(
            record: notOccurred,
            baseRevision: RevisionId.generate(),
            representedContext: context,
          ),
          throwsFormatException,
        );
      }
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: universe,
        continuity: ContinuityId.generate(),
        representedContext: context,
        typeClientRef: source.identity.recordId.value,
      );
      final form = eventWithdrawalFormFromRecord(
        record: source,
        baseRevision: RevisionId.generate(),
        representedContext: context,
      ).copyWith(rationale: 'Correct the recorded eventWithdrawal.');
      var store = EventWithdrawalFormRecoveryStore.open(
        '${root.path}/forms.sqlite',
      );
      try {
        store.save(scope, form, BigInt.zero);
        store.close();
        store = EventWithdrawalFormRecoveryStore.open(
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
        final add = eventWithdrawalDraftRequest(
          draft: empty,
          form: recovered,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        );
        final saved = SavedDraft(version: BigInt.two, content: add.content),
            pending = eventWithdrawalFormFromDraft(
              SavedDraft(version: BigInt.two, content: add.content),
              0,
            );
        expect(
          eventWithdrawalOperation(pending).toWire().toText(),
          eventWithdrawalOperation(form).toWire().toText(),
        );
        final edited = eventWithdrawalDraftRequest(
          draft: saved,
          form: pending.copyWith(
            rationale: 'Remove unresolved eventWithdrawal.',
          ),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        );
        final op = edited.content.operations.single as WithdrawEventOperation;
        expect(op.record.record, source.identity.recordId);
        expect(op.expectedVersion, source.recordVersionId);
        expect(op.rationale, 'Remove unresolved eventWithdrawal.');
        expect(
          () => eventWithdrawalDraftRequest(
            draft: SavedDraft(version: BigInt.from(3), content: saved.content),
            form: pending,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        final changedPin = UnfinishedEventWithdrawalForm.fromWire(
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
          () => eventWithdrawalDraftRequest(
            draft: saved,
            form: changedPin,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        expect(
          eventWithdrawalDraftRequest(
            draft: saved,
            form: form,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
          ).content.operations.length,
          1,
        );
        expect(
          () => eventWithdrawalDraftRequest(
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
          () => eventWithdrawalOperation(incomplete),
          throwsFormatException,
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
