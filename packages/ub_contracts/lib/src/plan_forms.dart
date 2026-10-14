import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedPlanForm {
  UnfinishedPlanForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.actor = const ExpressionReferenceInput(),
    this.desiredEnabled = false,
    this.desired = const ExpressionReferenceInput(),
    Iterable<ExpressionInput> prerequisites = const [],
    Iterable<ExpressionReferenceInput> steps = const [],
    this.status = '',
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : prerequisites = List.unmodifiable(prerequisites),
       steps = List.unmodifiable(steps),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, status, rationale;
  final ExpressionReferenceInput actor, desired;
  final bool desiredEnabled;
  final List<ExpressionInput> prerequisites;
  final List<ExpressionReferenceInput> steps;
  final TemporalValidityInput validity;
  final GoalRecord? original;
  final BigInt? draftVersion;
  UnfinishedPlanForm copyWith({
    ExpressionReferenceInput? actor,
    bool? desiredEnabled,
    ExpressionReferenceInput? desired,
    List<ExpressionInput>? prerequisites,
    List<ExpressionReferenceInput>? steps,
    String? status,
    TemporalValidityInput? validity,
    String? rationale,
  }) => UnfinishedPlanForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    actor: actor ?? this.actor,
    desiredEnabled: desiredEnabled ?? this.desiredEnabled,
    desired: desired ?? this.desired,
    prerequisites: prerequisites ?? this.prerequisites,
    steps: steps ?? this.steps,
    status: status ?? this.status,
    validity: validity ?? this.validity,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('actor', actor.toWire()),
    MapEntry('desired_enabled', CanonicalBool(desiredEnabled)),
    MapEntry('desired', desired.toWire()),
    MapEntry(
      'prerequisites',
      CanonicalArray(prerequisites.map((p) => p.toWire())),
    ),
    MapEntry('steps', CanonicalArray(steps.map((p) => p.toWire()))),
    MapEntry('status', CanonicalString(status)),
    MapEntry('validity', validity.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedPlanForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'actor',
      'desired_enabled',
      'desired',
      'prerequisites',
      'steps',
      'status',
      'validity',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedPlanForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      actor: ExpressionReferenceInput.fromWire(f.require('actor')),
      desiredEnabled: f.boolean('desired_enabled'),
      desired: ExpressionReferenceInput.fromWire(f.require('desired')),
      prerequisites: f.array('prerequisites').map(ExpressionInput.fromWire),
      steps: f.array('steps').map(ExpressionReferenceInput.fromWire),
      status: f.string('status'),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      rationale: f.string('rationale'),
      original: f.optional('original', GoalRecord.fromWire),
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

final class SavedPlanForm {
  SavedPlanForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedPlanForm form;
}
