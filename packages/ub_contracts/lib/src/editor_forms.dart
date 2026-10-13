import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

enum EditorRecoveryFailure {
  unavailable,
  incompatibleSchema,
  conflict,
  generationExhausted,
  invalidText,
}

final class EditorRecoveryException implements Exception {
  const EditorRecoveryException(this.failure);
  final EditorRecoveryFailure failure;
  @override
  String toString() => 'EditorRecoveryException(${failure.name})';
}

/// Client recovery belongs to this exact authenticated workspace. It grants no
/// authority to read canon, submit a proposal, approve or publish.
final class EditorFormScope {
  const EditorFormScope({
    required this.instance,
    required this.profile,
    required this.universe,
    required this.continuity,
    this.worldClientRef,
    this.representedContext,
    this.worldRecord,
    this.typeClientRef,
  });
  final OperationId instance;
  final ProfileId profile;
  final UniverseId universe;
  final ContinuityId continuity;

  /// Null is the new-world form. An edit has its own recovery slot, preserving
  /// other pending worlds and references supplied by external writers.
  final String? worldClientRef;
  final RecordId? representedContext;
  final RecordId? worldRecord;

  /// Null is creation; a draft definition reference identifies its edit slot.
  final String? typeClientRef;
}

/// Entered fields can be incomplete or invalid. Completing an editor must build
/// and validate a domain operation separately; loading this never creates one.
final class UnfinishedWorldForm {
  UnfinishedWorldForm({
    required this.baseRevision,
    required this.representedContext,
    required this.record,
    required this.selector,
    required this.settingType,
    required this.rationale,
    Iterable<String> aliases = const [],
    Map<String, String> labels = const {},
    BigInt? draftVersion,
    this.expectedRecordVersion,
  }) : aliases = List.unmodifiable(aliases),
       labels = Map.unmodifiable(labels),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext, record;
  final String selector, settingType, rationale;
  final List<String> aliases;
  final Map<String, String> labels;
  final BigInt? draftVersion;
  final RecordVersionId? expectedRecordVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('record', CanonicalString(record.value)),
    MapEntry('selector', CanonicalString(selector)),
    MapEntry('setting_type', CanonicalString(settingType)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    MapEntry('aliases', CanonicalArray(aliases.map(CanonicalString.new))),
    MapEntry(
      'labels',
      CanonicalObject(
        labels.entries.map(
          (entry) => MapEntry(entry.key, CanonicalString(entry.value)),
        ),
      ),
    ),
  ]);
}

final class SavedWorldForm {
  SavedWorldForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedWorldForm form;
}

/// Pending type input retains unresolved choices until the author completes
/// them. It is not a definition, proposal, or grant of authority.
final class UnfinishedTypeForm {
  UnfinishedTypeForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.namespace,
    required this.key,
    required this.name,
    required this.parentChoice,
    required this.applicabilityChoice,
    required this.rationale,
    this.classificationExecutable,
    Iterable<WorldId> worlds = const [],
    BigInt? draftVersion,
  }) : worlds = List.unmodifiable(worlds),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      namespace,
      key,
      name,
      parentChoice,
      applicabilityChoice,
      rationale;
  final bool? classificationExecutable;
  final List<WorldId> worlds;
  final BigInt? draftVersion;

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('parent_choice', CanonicalString(parentChoice)),
    MapEntry('applicability_choice', CanonicalString(applicabilityChoice)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry(
      'classification_executable',
      classificationExecutable == null
          ? const CanonicalNull()
          : CanonicalBool(classificationExecutable!),
    ),
    MapEntry(
      'worlds',
      CanonicalArray(worlds.map((world) => CanonicalString(world.value))),
    ),
  ]);
}

final class SavedTypeForm {
  SavedTypeForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedTypeForm form;
}
