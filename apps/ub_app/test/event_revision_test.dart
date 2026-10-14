import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/event_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('event revision preserves all authored fields through recovery and participant reordering', () {
    final root = Directory('/tmp').createTempSync('ub-event-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final entity = RecordId.generate();
    final effect = EntityEffect(
      slot: 'change',
      proposition: RecordRef(record: RecordId.generate()),
      polarity: Polarity.refutation,
      validity: const UnknownValidity(),
      scope: Scope(
        context: RecordRef(record: context),
        applicability: const UniverseApplicability(),
      ),
      order: BigInt.from(9007199254740993),
    );
    final payload = EventRecord(
      occurrence: const SimpleOccurrence(OccurrenceKind.reported),
      action: RecordRef(record: RecordId.generate()),
      worlds: [WorldId.generate()],
      region: RecordRef(record: RecordId.generate()),
      sequence: 'Sequence 記憶 😀',
      occurrenceId: 'authored-occurrence',
      expansionVersion: 'original expansion',
      time: ApproximateTime(
        CalendarId.generate(),
        '9007199254740993',
        const TextValue('several days'),
      ),
      participants: [
        EventParticipant(RecordRef(record: entity), 'witness'),
        EventParticipant(
          RecordRef(record: entity, universe: universe),
          'recipient',
        ),
      ],
      effects: [effect],
      labels: {'en': 'Arrival 記憶 😀', 'fr': 'Arrivée'},
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
    UnfinishedEventForm patch(
      UnfinishedEventForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedEventForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = eventRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      eventRevisionOperation(form).replacement.toWire().toText(),
      payload.toWire().toText(),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    var store = EventFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = EventFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final empty = SavedDraft(
        version: BigInt.one,
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: context,
          operations: [],
          rationale: 'Review calendar changes.',
        ),
      );
      final add = eventDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = eventFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = eventDraftRequest(
        draft: saved,
        form: patch(pending, {
          'participants': CanonicalArray(
            pending.participants.reversed.map((p) => p.toWire()),
          ),
          'label': CanonicalString('Corrected arrival 記憶 😀'),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseEventOperation,
          next = op.replacement;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      final expected = EventRecord.fromWire(
        CanonicalObject(
          payload.toWire().fields.map(
            (e) => e.key == 'participants'
                ? MapEntry(
                    'participants',
                    CanonicalArray(
                      payload.participants.reversed.map((p) => p.toWire()),
                    ),
                  )
                : e.key == 'labels'
                ? MapEntry(
                    'labels',
                    CanonicalObject([
                      MapEntry(
                        'en',
                        CanonicalString('Corrected arrival 記憶 😀'),
                      ),
                      MapEntry('fr', CanonicalString('Arrivée')),
                    ]),
                  )
                : e,
          ),
        ),
      );
      expect(next.toWire().toText(), expected.toWire().toText());
      expect(
        () => eventDraftRequest(
          draft: saved,
          form: patch(form, {'label': CanonicalString('another label')}),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      expect(
        () => eventDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => eventDraftRequest(
          draft: saved,
          form: patch(pending, {
            'expected_record_version': CanonicalString(
              RecordVersionId.generate().value,
            ),
          }),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final incomplete = patch(form, {
        'action_record': CanonicalString('unfinished action 記憶 😀'),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => eventRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
