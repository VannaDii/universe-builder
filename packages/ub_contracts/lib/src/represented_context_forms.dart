import 'package:ub_domain/ub_domain.dart';

import 'property_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class ChronologyInput {
  const ChronologyInput({
    this.enabled = false,
    this.calendar = '',
    this.system = '',
    this.offsetSeconds = '',
    this.tickLabel = '',
    this.ticksPerMonthEnabled = false,
    this.ticksPerMonth = '',
    this.firstInteraction = '',
    this.current = '',
  });
  final bool enabled, ticksPerMonthEnabled;
  final String calendar,
      system,
      offsetSeconds,
      tickLabel,
      ticksPerMonth,
      firstInteraction,
      current;
  ChronologyInput copyWith({
    bool? enabled,
    String? calendar,
    String? system,
    String? offsetSeconds,
    String? tickLabel,
    bool? ticksPerMonthEnabled,
    String? ticksPerMonth,
    String? firstInteraction,
    String? current,
  }) => ChronologyInput(
    enabled: enabled ?? this.enabled,
    calendar: calendar ?? this.calendar,
    system: system ?? this.system,
    offsetSeconds: offsetSeconds ?? this.offsetSeconds,
    tickLabel: tickLabel ?? this.tickLabel,
    ticksPerMonthEnabled: ticksPerMonthEnabled ?? this.ticksPerMonthEnabled,
    ticksPerMonth: ticksPerMonth ?? this.ticksPerMonth,
    firstInteraction: firstInteraction ?? this.firstInteraction,
    current: current ?? this.current,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('enabled', CanonicalBool(enabled)),
    MapEntry('calendar', CanonicalString(calendar)),
    MapEntry('system', CanonicalString(system)),
    MapEntry('offset_seconds', CanonicalString(offsetSeconds)),
    MapEntry('tick_label', CanonicalString(tickLabel)),
    MapEntry('ticks_per_month_enabled', CanonicalBool(ticksPerMonthEnabled)),
    MapEntry('ticks_per_month', CanonicalString(ticksPerMonth)),
    MapEntry('first_interaction', CanonicalString(firstInteraction)),
    MapEntry('current', CanonicalString(current)),
  ]);
  factory ChronologyInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'enabled',
      'calendar',
      'system',
      'offset_seconds',
      'tick_label',
      'ticks_per_month_enabled',
      'ticks_per_month',
      'first_interaction',
      'current',
    });
    return ChronologyInput(
      enabled: f.boolean('enabled'),
      calendar: f.string('calendar'),
      system: f.string('system'),
      offsetSeconds: f.string('offset_seconds'),
      tickLabel: f.string('tick_label'),
      ticksPerMonthEnabled: f.boolean('ticks_per_month_enabled'),
      ticksPerMonth: f.string('ticks_per_month'),
      firstInteraction: f.string('first_interaction'),
      current: f.string('current'),
    );
  }
}

final class UnfinishedRepresentedContextForm {
  UnfinishedRepresentedContextForm({
    required this.baseRevision,
    required this.representedContext,
    required this.universe,
    required this.clientRef,
    this.kind = '',
    this.authoredLabel = '',
    this.reference = const ExpressionReferenceInput(),
    this.parentEnabled = false,
    this.parent = const ExpressionReferenceInput(),
    this.chronology = const ChronologyInput(),
    Iterable<PropertyLabelInput> labels = const [],
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final UniverseId universe;
  final String clientRef, kind, authoredLabel, rationale;
  final ExpressionReferenceInput reference, parent;
  final bool parentEnabled;
  final ChronologyInput chronology;
  final List<PropertyLabelInput> labels;
  final RepresentedContextRecord? original;
  final BigInt? draftVersion;
  UnfinishedRepresentedContextForm copyWith({
    String? kind,
    String? authoredLabel,
    ExpressionReferenceInput? reference,
    bool? parentEnabled,
    ExpressionReferenceInput? parent,
    ChronologyInput? chronology,
    List<PropertyLabelInput>? labels,
    String? rationale,
  }) => UnfinishedRepresentedContextForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    universe: universe,
    clientRef: clientRef,
    kind: kind ?? this.kind,
    authoredLabel: authoredLabel ?? this.authoredLabel,
    reference: reference ?? this.reference,
    parentEnabled: parentEnabled ?? this.parentEnabled,
    parent: parent ?? this.parent,
    chronology: chronology ?? this.chronology,
    labels: labels ?? this.labels,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('universe', CanonicalString(universe.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('authored_label', CanonicalString(authoredLabel)),
    MapEntry('reference', reference.toWire()),
    MapEntry('parent_enabled', CanonicalBool(parentEnabled)),
    MapEntry('parent', parent.toWire()),
    MapEntry('chronology', chronology.toWire()),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedRepresentedContextForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'universe',
      'client_ref',
      'kind',
      'authored_label',
      'reference',
      'parent_enabled',
      'parent',
      'chronology',
      'labels',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedRepresentedContextForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      universe: UniverseId.parse(f.string('universe')),
      clientRef: f.string('client_ref'),
      kind: f.string('kind'),
      authoredLabel: f.string('authored_label'),
      reference: ExpressionReferenceInput.fromWire(f.require('reference')),
      parentEnabled: f.boolean('parent_enabled'),
      parent: ExpressionReferenceInput.fromWire(f.require('parent')),
      chronology: ChronologyInput.fromWire(f.require('chronology')),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      rationale: f.string('rationale'),
      original: f.optional('original', RepresentedContextRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => _texts(toWire());
}

Iterable<String> _texts(CanonicalValue value) sync* {
  switch (value) {
    case CanonicalString(:final value):
      yield value;
    case CanonicalArray(:final items):
      for (final item in items) {
        yield* _texts(item);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        yield* _texts(field.value);
      }
    default:
      break;
  }
}

final class SavedRepresentedContextForm {
  SavedRepresentedContextForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedRepresentedContextForm form;
}
