import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';

/// Domain evidence, admitted atomically with the original instance fact.
final class InitializationReceipt {
  const InitializationReceipt({
    required this.instance,
    required this.start,
    required this.property,
    required this.definition,
    required this.assertion,
    required this.revision,
    required this.sourceRevision,
  });
  final RecordId instance, start, property;
  final RecordVersionId definition, assertion;
  final RevisionId revision, sourceRevision;
  factory InitializationReceipt.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'instance',
        'start',
        'property',
        'definition',
        'assertion',
        'revision',
        'source_revision',
      });
    return InitializationReceipt(
      instance: RecordId.parse(f.string('instance')),
      start: RecordId.parse(f.string('start')),
      property: RecordId.parse(f.string('property')),
      definition: RecordVersionId.parse(f.string('definition')),
      assertion: RecordVersionId.parse(f.string('assertion')),
      revision: RevisionId.parse(f.string('revision')),
      sourceRevision: RevisionId.parse(f.string('source_revision')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('instance', CanonicalString(instance.value)),
    MapEntry('start', CanonicalString(start.value)),
    MapEntry('property', CanonicalString(property.value)),
    MapEntry('definition', CanonicalString(definition.value)),
    MapEntry('assertion', CanonicalString(assertion.value)),
    MapEntry('revision', CanonicalString(revision.value)),
    MapEntry('source_revision', CanonicalString(sourceRevision.value)),
  ]);
  InitializationReceipt admittedAt(RevisionId revision) =>
      InitializationReceipt(
        instance: instance,
        start: start,
        property: property,
        definition: definition,
        assertion: assertion,
        revision: revision,
        sourceRevision: sourceRevision,
      );
  @override
  bool operator ==(Object other) =>
      other is InitializationReceipt &&
      instance == other.instance &&
      start == other.start &&
      property == other.property &&
      definition == other.definition &&
      assertion == other.assertion &&
      revision == other.revision &&
      sourceRevision == other.sourceRevision;
  @override
  int get hashCode => Object.hash(
    instance,
    start,
    property,
    definition,
    assertion,
    revision,
    sourceRevision,
  );
}
