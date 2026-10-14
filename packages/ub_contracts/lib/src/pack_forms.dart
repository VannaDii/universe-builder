import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

final class PackDependencyInput {
  const PackDependencyInput({this.key = '', this.version = ''});
  final String key, version;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('key', CanonicalString(key)),
    MapEntry('version', CanonicalString(version)),
  ]);
  factory PackDependencyInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'key', 'version'});
    return PackDependencyInput(
      key: f.string('key'),
      version: f.string('version'),
    );
  }
}

final class UnfinishedPackForm {
  UnfinishedPackForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.key = '',
    this.version = '',
    Iterable<PackDependencyInput> dependencies = const [],
    Iterable<String> capabilities = const [],
    Iterable<String> records = const [],
    this.rationale = '',
    this.revisionTarget,
    this.expectedRecordVersion,
    this.original,
    BigInt? draftVersion,
  }) : dependencies = List.unmodifiable(dependencies),
       capabilities = List.unmodifiable(capabilities),
       records = List.unmodifiable(records),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, key, version, rationale;
  final List<PackDependencyInput> dependencies;
  final List<String> capabilities, records;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final DomainPackRecord? original;
  final BigInt? draftVersion;
  UnfinishedPackForm copyWith({
    String? key,
    String? version,
    List<PackDependencyInput>? dependencies,
    List<String>? capabilities,
    List<String>? records,
    String? rationale,
  }) => UnfinishedPackForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    key: key ?? this.key,
    version: version ?? this.version,
    dependencies: dependencies ?? this.dependencies,
    capabilities: capabilities ?? this.capabilities,
    records: records ?? this.records,
    rationale: rationale ?? this.rationale,
    revisionTarget: revisionTarget,
    expectedRecordVersion: expectedRecordVersion,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('version', CanonicalString(version)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry(
      'dependencies',
      CanonicalArray(dependencies.map((d) => d.toWire())),
    ),
    MapEntry(
      'capabilities',
      CanonicalArray(capabilities.map(CanonicalString.new)),
    ),
    MapEntry('records', CanonicalArray(records.map(CanonicalString.new))),
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
  factory UnfinishedPackForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'key',
      'version',
      'rationale',
      'dependencies',
      'capabilities',
      'records',
      'revision_target',
      'expected_record_version',
      'original',
      'draft_version',
    });
    return UnfinishedPackForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      key: f.string('key'),
      version: f.string('version'),
      rationale: f.string('rationale'),
      dependencies: f.array('dependencies').map(PackDependencyInput.fromWire),
      capabilities: f.array('capabilities').map(wireString),
      records: f.array('records').map(wireString),
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      original: f.optional('original', DomainPackRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield* [clientRef, key, version, rationale, ...capabilities, ...records];
    for (final d in dependencies) {
      yield d.key;
      yield d.version;
    }
  }
}

final class SavedPackForm {
  SavedPackForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedPackForm form;
}
