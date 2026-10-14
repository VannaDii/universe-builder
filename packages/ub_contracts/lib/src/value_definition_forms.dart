import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'expression_forms.dart';
import 'property_forms.dart';

final class ValueDefinitionFieldInput {
  const ValueDefinitionFieldInput({
    this.name = '',
    required this.shape,
    this.required = false,
    this.allowsUnknown = false,
  });
  final String name;
  final ValueShapeInput shape;
  final bool required, allowsUnknown;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('shape', shape.toWire()),
    MapEntry('required', CanonicalBool(required)),
    MapEntry('allows_unknown', CanonicalBool(allowsUnknown)),
  ]);
  factory ValueDefinitionFieldInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'shape',
      'required',
      'allows_unknown',
    });
    return ValueDefinitionFieldInput(
      name: f.string('name'),
      shape: ValueShapeInput.fromWire(f.require('shape')),
      required: f.boolean('required'),
      allowsUnknown: f.boolean('allows_unknown'),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield name;
    yield* shape.exactTexts;
  }
}

final class UnfinishedValueDefinitionForm {
  UnfinishedValueDefinitionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    Iterable<PropertyLabelInput> labels = const [],
    Iterable<ValueDefinitionFieldInput> fields = const [],
    this.rationale = '',
    this.revisionTarget,
    this.expectedRecordVersion,
    this.original,
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       fields = List.unmodifiable(fields),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, namespace, key, rationale;
  final List<PropertyLabelInput> labels;
  final List<ValueDefinitionFieldInput> fields;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final ValueDefinitionRecord? original;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
    MapEntry('fields', CanonicalArray(fields.map((f) => f.toWire()))),
    MapEntry('rationale', CanonicalString(rationale)),
    if (revisionTarget != null)
      MapEntry('revision_target', revisionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedValueDefinitionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'labels',
      'fields',
      'rationale',
      'draft_version',
      'revision_target',
      'expected_record_version',
      'original',
    });
    return UnfinishedValueDefinitionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      fields: f.array('fields').map(ValueDefinitionFieldInput.fromWire),
      rationale: f.string('rationale'),
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      original: f.optional('original', ValueDefinitionRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield* [clientRef, namespace, key, rationale];
    for (final l in labels) {
      yield l.language;
      yield l.text;
    }
    for (final f in fields) {
      yield* f.exactTexts;
    }
  }
}

final class SavedValueDefinitionForm {
  SavedValueDefinitionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedValueDefinitionForm form;
}
