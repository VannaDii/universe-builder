import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'expression_forms.dart';
import 'property_forms.dart';

final class CalendarUnitInput {
  const CalendarUnitInput({this.name = '', this.structure = ''});
  final String name, structure;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('structure', CanonicalString(structure)),
  ]);
  factory CalendarUnitInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'structure'});
    return CalendarUnitInput(
      name: f.string('name'),
      structure: f.string('structure'),
    );
  }
}

final class CalendarConversionInput {
  const CalendarConversionInput({
    this.target = '',
    this.hasExpression = false,
    this.expression = '',
    this.valid = false,
  });
  final String target, expression;
  final bool hasExpression, valid;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('target', CanonicalString(target)),
    MapEntry('has_expression', CanonicalBool(hasExpression)),
    MapEntry('expression', CanonicalString(expression)),
    MapEntry('valid', CanonicalBool(valid)),
  ]);
  factory CalendarConversionInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'target',
      'has_expression',
      'expression',
      'valid',
    });
    return CalendarConversionInput(
      target: f.string('target'),
      hasExpression: f.boolean('has_expression'),
      expression: f.string('expression'),
      valid: f.boolean('valid'),
    );
  }
}

final class UnfinishedCalendarForm {
  UnfinishedCalendarForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    Iterable<PropertyLabelInput> labels = const [],
    this.hasEpoch = false,
    this.epoch = '',
    Iterable<CalendarUnitInput> units = const [],
    Iterable<CalendarConversionInput> conversions = const [],
    this.rationale = '',
    this.revisionTarget,
    this.expectedRecordVersion,
    this.original,
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       units = List.unmodifiable(units),
       conversions = List.unmodifiable(conversions),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, namespace, key, epoch, rationale;
  final List<PropertyLabelInput> labels;
  final bool hasEpoch;
  final List<CalendarUnitInput> units;
  final List<CalendarConversionInput> conversions;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final CalendarRecord? original;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
    MapEntry('has_epoch', CanonicalBool(hasEpoch)),
    MapEntry('epoch', CanonicalString(epoch)),
    MapEntry('units', CanonicalArray(units.map((u) => u.toWire()))),
    MapEntry('conversions', CanonicalArray(conversions.map((c) => c.toWire()))),
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
  factory UnfinishedCalendarForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'labels',
      'has_epoch',
      'epoch',
      'units',
      'conversions',
      'rationale',
      'draft_version',
      'revision_target',
      'expected_record_version',
      'original',
    });
    return UnfinishedCalendarForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      hasEpoch: f.boolean('has_epoch'),
      epoch: f.string('epoch'),
      units: f.array('units').map(CalendarUnitInput.fromWire),
      conversions: f.array('conversions').map(CalendarConversionInput.fromWire),
      rationale: f.string('rationale'),
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      original: f.optional('original', CalendarRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield* [clientRef, namespace, key, epoch, rationale];
    for (final l in labels) {
      yield l.language;
      yield l.text;
    }
    for (final u in units) {
      yield u.name;
      yield u.structure;
    }
    for (final c in conversions) {
      yield c.target;
      yield c.expression;
    }
  }
}

final class SavedCalendarForm {
  SavedCalendarForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedCalendarForm form;
}
