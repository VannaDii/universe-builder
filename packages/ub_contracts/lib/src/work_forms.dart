import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'property_forms.dart';
import 'wire.dart';

final class WorkAssociationInput {
  WorkAssociationInput({
    this.world = '',
    this.role = '',
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    Iterable<QualifierInput> qualifiers = const [],
    this.originalOrdinal,
  }) : qualifiers = List.unmodifiable(qualifiers);
  final String world, role;
  final TemporalValidityInput validity;
  final List<QualifierInput> qualifiers;
  final int? originalOrdinal;
  WorkAssociationInput copyWith({
    String? world,
    String? role,
    TemporalValidityInput? validity,
    List<QualifierInput>? qualifiers,
  }) => WorkAssociationInput(
    world: world ?? this.world,
    role: role ?? this.role,
    validity: validity ?? this.validity,
    qualifiers: qualifiers ?? this.qualifiers,
    originalOrdinal: originalOrdinal,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('world', CanonicalString(world)),
    MapEntry('role', CanonicalString(role)),
    MapEntry('validity', validity.toWire()),
    MapEntry('qualifiers', CanonicalArray(qualifiers.map((q) => q.toWire()))),
    if (originalOrdinal != null)
      MapEntry('original_ordinal', CanonicalString(originalOrdinal.toString())),
  ]);
  factory WorkAssociationInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'world',
      'role',
      'validity',
      'qualifiers',
      'original_ordinal',
    });
    return WorkAssociationInput(
      world: f.string('world'),
      role: f.string('role'),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      qualifiers: f.array('qualifiers').map(QualifierInput.fromWire),
      originalOrdinal: f.optional(
        'original_ordinal',
        (v) => int.parse(wireString(v)),
      ),
    );
  }
}

final class UnfinishedWorkForm {
  UnfinishedWorkForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.kind = '',
    this.title = '',
    Iterable<PropertyLabelInput> labels = const [],
    Iterable<ExpressionReferenceInput> sources = const [],
    Iterable<String> versions = const [],
    Iterable<WorkAssociationInput> associations = const [],
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       sources = List.unmodifiable(sources),
       versions = List.unmodifiable(versions),
       associations = List.unmodifiable(associations),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, kind, title, rationale;
  final List<PropertyLabelInput> labels;
  final List<ExpressionReferenceInput> sources;
  final List<String> versions;
  final List<WorkAssociationInput> associations;
  final WorkRecord? original;
  final BigInt? draftVersion;
  UnfinishedWorkForm copyWith({
    String? kind,
    String? title,
    List<PropertyLabelInput>? labels,
    List<ExpressionReferenceInput>? sources,
    List<String>? versions,
    List<WorkAssociationInput>? associations,
    String? rationale,
  }) => UnfinishedWorkForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    labels: labels ?? this.labels,
    sources: sources ?? this.sources,
    versions: versions ?? this.versions,
    associations: associations ?? this.associations,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('title', CanonicalString(title)),
    MapEntry('labels', CanonicalArray(labels.map((e) => e.toWire()))),
    MapEntry('sources', CanonicalArray(sources.map((e) => e.toWire()))),
    MapEntry('versions', CanonicalArray(versions.map(CanonicalString.new))),
    MapEntry(
      'associations',
      CanonicalArray(associations.map((e) => e.toWire())),
    ),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedWorkForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'kind',
      'title',
      'labels',
      'sources',
      'versions',
      'associations',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedWorkForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      kind: f.string('kind'),
      title: f.string('title'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      sources: f.array('sources').map(ExpressionReferenceInput.fromWire),
      versions: f.array('versions').map(wireString),
      associations: f.array('associations').map(WorkAssociationInput.fromWire),
      rationale: f.string('rationale'),
      original: f.optional('original', WorkRecord.fromWire),
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

final class SavedWorkForm {
  SavedWorkForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedWorkForm form;
}
