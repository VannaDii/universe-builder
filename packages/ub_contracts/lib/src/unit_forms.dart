import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'editor_forms.dart';
import 'property_forms.dart';

final class UnfinishedUnitForm {
  UnfinishedUnitForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    this.dimension = '',
    this.symbol = '',
    Iterable<PropertyLabelInput> labels = const [],
    this.hasBase = false,
    this.base = '',
    this.hasScale = false,
    this.scale = const QualifierInput(
      kind: 'rational',
      value: '1',
      denominator: '1',
    ),
    this.validityChoice = '',
    this.temporalValidity,
    this.rationale = '',
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      namespace,
      key,
      dimension,
      symbol,
      base,
      validityChoice,
      rationale;
  final List<PropertyLabelInput> labels;
  final bool hasBase, hasScale;
  final QualifierInput scale;
  final TemporalValidityInput? temporalValidity;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('dimension', CanonicalString(dimension)),
    MapEntry('symbol', CanonicalString(symbol)),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
    MapEntry('has_base', CanonicalBool(hasBase)),
    MapEntry('base', CanonicalString(base)),
    MapEntry('has_scale', CanonicalBool(hasScale)),
    MapEntry('scale', scale.toWire()),
    MapEntry('validity_choice', CanonicalString(validityChoice)),
    if (temporalValidity != null)
      MapEntry('temporal_validity', temporalValidity!.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedUnitForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'dimension',
      'symbol',
      'labels',
      'has_base',
      'base',
      'has_scale',
      'scale',
      'validity_choice',
      'temporal_validity',
      'rationale',
      'draft_version',
    });
    return UnfinishedUnitForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      dimension: f.string('dimension'),
      symbol: f.string('symbol'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      hasBase: f.boolean('has_base'),
      base: f.string('base'),
      hasScale: f.boolean('has_scale'),
      scale: QualifierInput.fromWire(f.require('scale')),
      validityChoice: f.string('validity_choice'),
      temporalValidity: f.optional(
        'temporal_validity',
        TemporalValidityInput.fromWire,
      ),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield* [
      clientRef,
      namespace,
      key,
      dimension,
      symbol,
      base,
      validityChoice,
      rationale,
    ];
    for (final l in labels) {
      yield l.language;
      yield l.text;
    }
    yield* scale.exactTexts;
    if (temporalValidity != null) {
      yield* AttributeEvidenceInput(temporalValidity: temporalValidity)
          .exactTexts;
    }
  }
}

final class SavedUnitForm {
  SavedUnitForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedUnitForm form;
}
