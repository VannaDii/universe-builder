import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'wire.dart';

final class EventParticipantInput {
  const EventParticipantInput({
    this.record = '',
    this.universe = '',
    this.role = '',
  });
  final String record, universe, role;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record', CanonicalString(record)),
    MapEntry('universe', CanonicalString(universe)),
    MapEntry('role', CanonicalString(role)),
  ]);
  factory EventParticipantInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record', 'universe', 'role'});
    return EventParticipantInput(
      record: f.string('record'),
      universe: f.string('universe'),
      role: f.string('role'),
    );
  }
}

/// Incomplete text remains editable; constructing an event happens separately.
final class UnfinishedEventForm {
  UnfinishedEventForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.label = '',
    this.occurrence = '',
    this.description = '',
    this.actionRecord = '',
    this.actionUniverse = '',
    this.time = const TemporalValidityInput(kind: 'instant_unspecified'),
    Iterable<EventParticipantInput> participants = const [],
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : participants = List.unmodifiable(participants),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      label,
      occurrence,
      description,
      actionRecord,
      actionUniverse,
      rationale;
  final TemporalValidityInput time;
  final List<EventParticipantInput> participants;
  final EventRecord? original;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('label', CanonicalString(label)),
    MapEntry('occurrence', CanonicalString(occurrence)),
    MapEntry('description', CanonicalString(description)),
    MapEntry('action_record', CanonicalString(actionRecord)),
    MapEntry('action_universe', CanonicalString(actionUniverse)),
    MapEntry('time', time.toWire()),
    MapEntry(
      'participants',
      CanonicalArray(participants.map((p) => p.toWire())),
    ),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedEventForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'label',
      'occurrence',
      'description',
      'action_record',
      'action_universe',
      'time',
      'participants',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedEventForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      label: f.string('label'),
      occurrence: f.string('occurrence'),
      description: f.string('description'),
      actionRecord: f.string('action_record'),
      actionUniverse: f.string('action_universe'),
      time: TemporalValidityInput.fromWire(f.require('time')),
      participants: f.array('participants').map(EventParticipantInput.fromWire),
      rationale: f.string('rationale'),
      original: f.optional(
        'original',
        (v) => RecordPayload.fromWire(v) as EventRecord,
      ),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => [
    clientRef,
    label,
    occurrence,
    description,
    actionRecord,
    actionUniverse,
    rationale,
    time.kind,
    time.calendar,
    time.relation,
    time.targetUniverse,
    time.targetRecord,
    for (final bound in [time.start, time.end])
      for (final field in bound.toWire().fields)
        if (field.value is CanonicalString)
          (field.value as CanonicalString).value,
    for (final p in participants) ...[p.record, p.universe, p.role],
    if (original != null) original!.toWire().toText(),
  ];
}

final class SavedEventForm {
  SavedEventForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedEventForm form;
}
