import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

const universePolicyEditorKey = 'universe-policy';

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
    this.realWorldPolicy,
    this.activatePolicy = true,
    this.expectedRootVersion,
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
  final bool? realWorldPolicy;
  final bool activatePolicy;
  final RecordVersionId? expectedRootVersion;
  UnfinishedPackForm copyWith({
    String? key,
    String? version,
    List<PackDependencyInput>? dependencies,
    List<String>? capabilities,
    List<String>? records,
    String? rationale,
    bool? realWorldPolicy,
    bool? activatePolicy,
    RecordVersionId? expectedRootVersion,
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
    realWorldPolicy: realWorldPolicy ?? this.realWorldPolicy,
    activatePolicy: activatePolicy ?? this.activatePolicy,
    expectedRootVersion: expectedRootVersion ?? this.expectedRootVersion,
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
    if (realWorldPolicy != null) ...[
      MapEntry('real_world_policy', CanonicalBool(realWorldPolicy!)),
      MapEntry('activate_policy', CanonicalBool(activatePolicy)),
      if (expectedRootVersion != null)
        MapEntry('expected_root_version', CanonicalString(expectedRootVersion!.value)),
    ],
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
      'real_world_policy', 'activate_policy', 'expected_root_version',
    });
    return UnfinishedPackForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      key: f.string('key'),
      version: f.string('version'),
      rationale: f.string('rationale'),
      realWorldPolicy: f.optional('real_world_policy', (_) => f.boolean('real_world_policy')),
      activatePolicy: f.optional('activate_policy', (_) => f.boolean('activate_policy')) ?? true,
      expectedRootVersion: f.optional('expected_root_version',
          (v) => RecordVersionId.parse(wireString(v))),
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
