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
  });
  final OperationId instance;
  final ProfileId profile;
  final UniverseId universe;
  final ContinuityId continuity;
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
  }) : aliases = List.unmodifiable(aliases),
       labels = Map.unmodifiable(labels);
  final RevisionId baseRevision;
  final RecordId representedContext, record;
  final String selector, settingType, rationale;
  final List<String> aliases;
  final Map<String, String> labels;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('record', CanonicalString(record.value)),
    MapEntry('selector', CanonicalString(selector)),
    MapEntry('setting_type', CanonicalString(settingType)),
    MapEntry('rationale', CanonicalString(rationale)),
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
