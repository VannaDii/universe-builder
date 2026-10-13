import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

final class ValueShapeInput {
  ValueShapeInput({
    this.kind = '',
    this.unit = '',
    this.definition = '',
    Iterable<String> subjectTypes = const [],
    this.item,
  }) : subjectTypes = List.unmodifiable(subjectTypes);
  final String kind, unit, definition;
  final List<String> subjectTypes;
  final ValueShapeInput? item;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('unit', CanonicalString(unit)),
    MapEntry('definition', CanonicalString(definition)),
    MapEntry(
      'subject_types',
      CanonicalArray(subjectTypes.map(CanonicalString.new)),
    ),
    if (item != null) MapEntry('item', item!.toWire()),
  ]);
  factory ValueShapeInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'unit',
      'definition',
      'subject_types',
      'item',
    });
    return ValueShapeInput(
      kind: f.string('kind'),
      unit: f.string('unit'),
      definition: f.string('definition'),
      subjectTypes: f.array('subject_types').map(wireString),
      item: f.optional('item', ValueShapeInput.fromWire),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield kind;
    yield unit;
    yield definition;
    yield* subjectTypes;
    if (item != null) yield* item!.exactTexts;
  }
}

final class PropertyLabelInput {
  const PropertyLabelInput({this.language = '', this.text = ''});
  final String language, text;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('language', CanonicalString(language)),
    MapEntry('text', CanonicalString(text)),
  ]);
  factory PropertyLabelInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'language', 'text'});
    return PropertyLabelInput(
      language: f.string('language'),
      text: f.string('text'),
    );
  }
}

final class UnfinishedPropertyForm {
  UnfinishedPropertyForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    Iterable<PropertyLabelInput> labels = const [],
    Iterable<String> subjectTypes = const [],
    required this.shape,
    this.multiplicity = '',
    this.persistence = '',
    this.hasUnitDimension = false,
    this.unitDimension = '',
    this.hasInverse = false,
    this.inverse = '',
    this.exclusive = false,
    this.symmetric = false,
    this.transitive = false,
    this.rationale = '',
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       subjectTypes = List.unmodifiable(subjectTypes),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      namespace,
      key,
      multiplicity,
      persistence,
      unitDimension,
      inverse,
      rationale;
  final List<PropertyLabelInput> labels;
  final List<String> subjectTypes;
  final ValueShapeInput shape;
  final bool hasUnitDimension, hasInverse, exclusive, symmetric, transitive;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', CanonicalArray(labels.map((label) => label.toWire()))),
    MapEntry(
      'subject_types',
      CanonicalArray(subjectTypes.map(CanonicalString.new)),
    ),
    MapEntry('shape', shape.toWire()),
    MapEntry('multiplicity', CanonicalString(multiplicity)),
    MapEntry('persistence', CanonicalString(persistence)),
    MapEntry('has_unit_dimension', CanonicalBool(hasUnitDimension)),
    MapEntry('unit_dimension', CanonicalString(unitDimension)),
    MapEntry('has_inverse', CanonicalBool(hasInverse)),
    MapEntry('inverse', CanonicalString(inverse)),
    MapEntry('exclusive', CanonicalBool(exclusive)),
    MapEntry('symmetric', CanonicalBool(symmetric)),
    MapEntry('transitive', CanonicalBool(transitive)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedPropertyForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'labels',
      'subject_types',
      'shape',
      'multiplicity',
      'persistence',
      'has_unit_dimension',
      'unit_dimension',
      'has_inverse',
      'inverse',
      'exclusive',
      'symmetric',
      'transitive',
      'rationale',
      'draft_version',
    });
    return UnfinishedPropertyForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      subjectTypes: f.array('subject_types').map(wireString),
      shape: ValueShapeInput.fromWire(f.require('shape')),
      multiplicity: f.string('multiplicity'),
      persistence: f.string('persistence'),
      hasUnitDimension: f.boolean('has_unit_dimension'),
      unitDimension: f.string('unit_dimension'),
      hasInverse: f.boolean('has_inverse'),
      inverse: f.string('inverse'),
      exclusive: f.boolean('exclusive'),
      symmetric: f.boolean('symmetric'),
      transitive: f.boolean('transitive'),
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
      multiplicity,
      persistence,
      unitDimension,
      inverse,
      rationale,
    ];
    for (final e in labels) {
      yield e.language;
      yield e.text;
    }
    yield* subjectTypes;
    yield* shape.exactTexts;
  }
}

final class SavedPropertyForm {
  SavedPropertyForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedPropertyForm form;
}
