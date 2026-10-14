import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

/// Incomplete authored acquisition fields, not a claim of successful knowledge.
final class KnowledgeAcquisitionInput {
  const KnowledgeAcquisitionInput({
    this.enabled = false,
    this.truthContext = const ExpressionReferenceInput(),
    this.time = const TemporalValidityInput(kind: 'instant_unspecified'),
    this.worldEnabled = false,
    this.world = const ExpressionReferenceInput(),
    this.basis = '',
    this.communication = const ExpressionReferenceInput(),
    this.interpretationEnabled = false,
    this.interpretation = const ExpressionReferenceInput(),
  });
  final bool enabled, worldEnabled, interpretationEnabled;
  final ExpressionReferenceInput truthContext,
      world,
      communication,
      interpretation;
  final TemporalValidityInput time;
  final String basis;
  KnowledgeAcquisitionInput copyWith({
    bool? enabled,
    bool? worldEnabled,
    bool? interpretationEnabled,
    ExpressionReferenceInput? truthContext,
    ExpressionReferenceInput? world,
    ExpressionReferenceInput? communication,
    ExpressionReferenceInput? interpretation,
    TemporalValidityInput? time,
    String? basis,
  }) => KnowledgeAcquisitionInput(
    enabled: enabled ?? this.enabled,
    truthContext: truthContext ?? this.truthContext,
    time: time ?? this.time,
    worldEnabled: worldEnabled ?? this.worldEnabled,
    world: world ?? this.world,
    basis: basis ?? this.basis,
    communication: communication ?? this.communication,
    interpretationEnabled: interpretationEnabled ?? this.interpretationEnabled,
    interpretation: interpretation ?? this.interpretation,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('enabled', CanonicalBool(enabled)),
    MapEntry('truth_context', truthContext.toWire()),
    MapEntry('time', time.toWire()),
    MapEntry('world_enabled', CanonicalBool(worldEnabled)),
    MapEntry('world', world.toWire()),
    MapEntry('basis', CanonicalString(basis)),
    MapEntry('communication', communication.toWire()),
    MapEntry('interpretation_enabled', CanonicalBool(interpretationEnabled)),
    MapEntry('interpretation', interpretation.toWire()),
  ]);
  factory KnowledgeAcquisitionInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'enabled',
      'truth_context',
      'time',
      'world_enabled',
      'world',
      'basis',
      'communication',
      'interpretation_enabled',
      'interpretation',
    });
    return KnowledgeAcquisitionInput(
      enabled: f.boolean('enabled'),
      truthContext: ExpressionReferenceInput.fromWire(
        f.require('truth_context'),
      ),
      time: TemporalValidityInput.fromWire(f.require('time')),
      worldEnabled: f.boolean('world_enabled'),
      world: ExpressionReferenceInput.fromWire(f.require('world')),
      basis: f.string('basis'),
      communication: ExpressionReferenceInput.fromWire(
        f.require('communication'),
      ),
      interpretationEnabled: f.boolean('interpretation_enabled'),
      interpretation: ExpressionReferenceInput.fromWire(
        f.require('interpretation'),
      ),
    );
  }
}

final class UnfinishedAttitudeForm {
  UnfinishedAttitudeForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.holder = const ExpressionReferenceInput(),
    this.proposition = const ExpressionReferenceInput(),
    this.attitude = '',
    this.certaintyEnabled = false,
    this.certainty = '',
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.basis = const EvidenceBasisInput(kind: 'author_decision'),
    this.acquisition = const KnowledgeAcquisitionInput(),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, attitude, certainty, rationale;
  final ExpressionReferenceInput holder, proposition;
  final bool certaintyEnabled;
  final TemporalValidityInput validity;
  final EvidenceBasisInput basis;
  final KnowledgeAcquisitionInput acquisition;
  final EpistemicAttitudeRecord? original;
  final BigInt? draftVersion;
  UnfinishedAttitudeForm copyWith({
    ExpressionReferenceInput? holder,
    ExpressionReferenceInput? proposition,
    String? attitude,
    bool? certaintyEnabled,
    String? certainty,
    TemporalValidityInput? validity,
    EvidenceBasisInput? basis,
    KnowledgeAcquisitionInput? acquisition,
    String? rationale,
  }) => UnfinishedAttitudeForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    holder: holder ?? this.holder,
    proposition: proposition ?? this.proposition,
    attitude: attitude ?? this.attitude,
    certaintyEnabled: certaintyEnabled ?? this.certaintyEnabled,
    certainty: certainty ?? this.certainty,
    validity: validity ?? this.validity,
    basis: basis ?? this.basis,
    acquisition: acquisition ?? this.acquisition,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('holder', holder.toWire()),
    MapEntry('proposition', proposition.toWire()),
    MapEntry('attitude', CanonicalString(attitude)),
    MapEntry('certainty_enabled', CanonicalBool(certaintyEnabled)),
    MapEntry('certainty', CanonicalString(certainty)),
    MapEntry('validity', validity.toWire()),
    MapEntry('basis', basis.toWire()),
    MapEntry('acquisition', acquisition.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedAttitudeForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'holder',
      'proposition',
      'attitude',
      'certainty_enabled',
      'certainty',
      'validity',
      'basis',
      'acquisition',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedAttitudeForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      holder: ExpressionReferenceInput.fromWire(f.require('holder')),
      proposition: ExpressionReferenceInput.fromWire(f.require('proposition')),
      attitude: f.string('attitude'),
      certaintyEnabled: f.boolean('certainty_enabled'),
      certainty: f.string('certainty'),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      basis: EvidenceBasisInput.fromWire(f.require('basis')),
      acquisition: KnowledgeAcquisitionInput.fromWire(f.require('acquisition')),
      rationale: f.string('rationale'),
      original: f.optional('original', EpistemicAttitudeRecord.fromWire),
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

final class SavedAttitudeForm {
  SavedAttitudeForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedAttitudeForm form;
}
