import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedObservationForm {
  UnfinishedObservationForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.observer = const ExpressionReferenceInput(),
    this.observed = const ExpressionReferenceInput(),
    this.sensoryAccess,
    this.time = const TemporalValidityInput(kind: 'instant_unspecified'),
    this.interpretationEnabled = false,
    this.interpretation = const ExpressionReferenceInput(),
    this.basis = const EvidenceBasisInput(kind: 'author_decision'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, rationale;
  final ExpressionReferenceInput observer, observed, interpretation;
  final bool? sensoryAccess;
  final bool interpretationEnabled;
  final TemporalValidityInput time;
  final EvidenceBasisInput basis;
  final ObservationRecord? original;
  final BigInt? draftVersion;
  UnfinishedObservationForm copyWith({
    ExpressionReferenceInput? observer,
    ExpressionReferenceInput? observed,
    bool? sensoryAccess,
    TemporalValidityInput? time,
    bool? interpretationEnabled,
    ExpressionReferenceInput? interpretation,
    EvidenceBasisInput? basis,
    String? rationale,
  }) => UnfinishedObservationForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    observer: observer ?? this.observer,
    observed: observed ?? this.observed,
    sensoryAccess: sensoryAccess ?? this.sensoryAccess,
    time: time ?? this.time,
    interpretationEnabled: interpretationEnabled ?? this.interpretationEnabled,
    interpretation: interpretation ?? this.interpretation,
    basis: basis ?? this.basis,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('observer', observer.toWire()),
    MapEntry('observed', observed.toWire()),
    MapEntry(
      'sensory_access',
      sensoryAccess == null
          ? const CanonicalNull()
          : CanonicalBool(sensoryAccess!),
    ),
    MapEntry('time', time.toWire()),
    MapEntry('interpretation_enabled', CanonicalBool(interpretationEnabled)),
    MapEntry('interpretation', interpretation.toWire()),
    MapEntry('basis', basis.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedObservationForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'observer',
      'observed',
      'sensory_access',
      'time',
      'interpretation_enabled',
      'interpretation',
      'basis',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedObservationForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      observer: ExpressionReferenceInput.fromWire(f.require('observer')),
      observed: ExpressionReferenceInput.fromWire(f.require('observed')),
      sensoryAccess: f.optional(
        'sensory_access',
        (v) => switch (v) {
          CanonicalBool(:final value) => value,
          _ => throw const FormatException('Expected sensory-access choice'),
        },
      ),
      time: TemporalValidityInput.fromWire(f.require('time')),
      interpretationEnabled: f.boolean('interpretation_enabled'),
      interpretation: ExpressionReferenceInput.fromWire(
        f.require('interpretation'),
      ),
      basis: EvidenceBasisInput.fromWire(f.require('basis')),
      rationale: f.string('rationale'),
      original: f.optional('original', ObservationRecord.fromWire),
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

final class SavedObservationForm {
  SavedObservationForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedObservationForm form;
}
