import 'package:test/test.dart';
import 'package:ub_app/event_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('event forms retain occurrence, participant order, uncertainty and effect declarations', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        entity = RecordId.generate();
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
    final event = EventRecord(
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
    final draft = SavedDraft(
      version: BigInt.from(6),
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [RecordEventOperation(clientRef: 'arrival', record: event)],
        rationale: 'An attributed report.',
      ),
    );
    final form = UnfinishedEventForm.fromWire(
      eventFormFromDraft(draft, 0).toWire(),
    );
    expect(
      eventOperation(form).record.toWire().toText(),
      event.toWire().toText(),
    );
    final edited = UnfinishedEventForm(
      baseRevision: form.baseRevision,
      representedContext: context,
      clientRef: form.clientRef,
      label: 'Planned arrival',
      occurrence: 'planned',
      actionRecord: form.actionRecord,
      actionUniverse: form.actionUniverse,
      time: form.time,
      participants: form.participants.reversed,
      original: form.original,
      draftVersion: form.draftVersion,
    );
    final request = eventDraftRequest(
      draft: draft,
      form: edited,
      universe: const Selector('World'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final updated =
        (request.content.operations.single as RecordEventOperation).record;
    expect(
      (updated.occurrence as SimpleOccurrence).kind,
      OccurrenceKind.planned,
    );
    expect(updated.participants.first.role, 'recipient');
    expect(updated.effects.single.toWire().toText(), effect.toWire().toText());
    expect(updated.labels['fr'], 'Arrivée');
    expect(request.content.rationale, draft.content.rationale);
    expect(
      () => eventDraftRequest(
        draft: SavedDraft(version: BigInt.from(7), content: draft.content),
        form: edited,
        universe: const Selector('World'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('incomplete event input recovers without inventing an occurrence or reference', () {
    final form = UnfinishedEventForm(
      baseRevision: RevisionId.generate(),
      representedContext: RecordId.generate(),
      clientRef: 'draft-event',
      label: 'Memory 記憶 😀',
      actionRecord: 'unfinished',
      participants: [const EventParticipantInput(role: 'witness')],
    );
    final restored = UnfinishedEventForm.fromWire(form.toWire());
    expect(restored.toWire().toText(), form.toWire().toText());
    expect(restored.occurrence, '');
    expect(() => eventOperation(restored), throwsFormatException);
  });
}
