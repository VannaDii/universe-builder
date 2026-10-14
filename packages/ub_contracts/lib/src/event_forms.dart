import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'event_effect_forms.dart';
import 'expression_forms.dart';
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
    this.revisionTarget,
    this.expectedRecordVersion,
    Iterable<String>? worlds,
    String? regionRecord,
    String? regionUniverse,
    String? sequence,
    String? occurrenceId,
    BigInt? draftVersion,
    Iterable<EventEffectInput>? effects,
    Iterable<ExpressionInput>? preconditions,
  }) : participants = List.unmodifiable(participants),
       effects = effects == null ? null : List.unmodifiable(effects),
       preconditions = preconditions == null
           ? null
           : List.unmodifiable(preconditions),
       worlds = List.unmodifiable(
         worlds ?? original?.worlds.map((w) => w.value) ?? const [],
       ),
       regionRecord = regionRecord ?? original?.region?.record.value ?? '',
       regionUniverse =
           regionUniverse ?? original?.region?.universe?.value ?? '',
       sequence = sequence ?? original?.sequence ?? '',
       occurrenceId = occurrenceId ?? original?.occurrenceId ?? '',
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
  final List<String> worlds;
  final String regionRecord, regionUniverse, sequence, occurrenceId;
  final TemporalValidityInput time;
  final List<EventParticipantInput> participants;
  final List<EventEffectInput>? effects;
  final List<ExpressionInput>? preconditions;
  final EventRecord? original;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
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
    if (effects != null)
      MapEntry('effects', CanonicalArray(effects!.map((e) => e.toWire()))),
    if (preconditions != null)
      MapEntry(
        'preconditions',
        CanonicalArray(preconditions!.map((e) => e.toWire())),
      ),
    MapEntry('worlds', CanonicalArray(worlds.map(CanonicalString.new))),
    MapEntry('region_record', CanonicalString(regionRecord)),
    MapEntry('region_universe', CanonicalString(regionUniverse)),
    MapEntry('sequence', CanonicalString(sequence)),
    MapEntry('occurrence_id', CanonicalString(occurrenceId)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (revisionTarget != null)
      MapEntry('revision_target', revisionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
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
      'effects',
      'preconditions',
      'draft_version',
      'revision_target',
      'expected_record_version',
      'worlds',
      'region_record',
      'region_universe',
      'sequence',
      'occurrence_id',
    });
    return UnfinishedEventForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      label: f.string('label'),
      preconditions: f.optional(
        'preconditions',
        (v) =>
            (v as CanonicalArray).items.map((e) => ExpressionInput.fromWire(e)),
      ),
      effects: f.optional(
        'effects',
        (v) => (v as CanonicalArray).items.map(EventEffectInput.fromWire),
      ),
      worlds: f.optional(
        'worlds',
        (v) => (v as CanonicalArray).items.map(wireString),
      ),
      regionRecord: f.optional('region_record', wireString),
      regionUniverse: f.optional('region_universe', wireString),
      sequence: f.optional('sequence', wireString),
      occurrenceId: f.optional('occurrence_id', wireString),
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
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => [
    for (final condition in preconditions ?? <ExpressionInput>[])
      ...condition.exactTexts,
    for (final effect in effects ?? <EventEffectInput>[]) ...effect.exactTexts,
    ...worlds,
    regionRecord,
    regionUniverse,
    sequence,
    occurrenceId,
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
