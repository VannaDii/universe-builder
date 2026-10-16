import 'ids.dart';
import 'records.dart';

const universePolicySelectionKey = 'universe.policy.root';
const universePolicyDefinitionPrefix = 'universe.policy.definition.';

bool isUniversePolicyRecord(RecordVersion record) => switch (record.payload) {
  DomainPackRecord(:final key) =>
    key == universePolicySelectionKey ||
        key.startsWith(universePolicyDefinitionPrefix),
  _ => false,
};

/// A root selection and its definition in one exact canonical snapshot.
/// Definitions use ordinary typed domain packs; selection does not copy rules.
final class UniversePolicySelection {
  UniversePolicySelection._(
    this.selection,
    this.definition,
    this.rules,
    this.inactiveRuleIds,
  );

  final RecordVersion selection, definition;
  final List<RecordVersion> rules;
  final Set<RecordId> inactiveRuleIds;

  factory UniversePolicySelection.fromRecords(
    UniverseId universe,
    Iterable<RecordVersion> records,
  ) {
    final byId = <RecordId, RecordVersion>{};
    final selections = <RecordVersion>[];
    for (final row in records) {
      if (row.identity.universeId != universe) {
        throw const FormatException('Policy snapshot crosses universes');
      }
      if (byId.containsKey(row.identity.recordId)) {
        throw const FormatException('Policy snapshot repeats a record');
      }
      byId[row.identity.recordId] = row;
      if (row.payload case DomainPackRecord(:final key)
          when key == universePolicySelectionKey) {
        selections.add(row);
      }
    }
    if (selections.length != 1) {
      throw const FormatException(
        'A universe requires exactly one root policy',
      );
    }
    final selection = selections.single;
    final binding = selection.payload as DomainPackRecord;
    if (binding.records.length != 1 || binding.dependencies.length != 1) {
      throw const FormatException(
        'Root selection must name one defined policy',
      );
    }
    final definition = byId[binding.records.single];
    if (definition == null || definition.payload is! DomainPackRecord) {
      throw const FormatException('Root policy definition is missing');
    }
    final policy = definition.payload as DomainPackRecord;
    if (!policy.key.startsWith(universePolicyDefinitionPrefix) ||
        policy.key.length == universePolicyDefinitionPrefix.length ||
        binding.dependencies[policy.key] != policy.version) {
      throw const FormatException('Root policy definition/version mismatch');
    }
    final rules = <RecordVersion>[];
    final seen = <RecordId>{};
    for (final id in policy.records) {
      final rule = byId[id];
      if (!seen.add(id) || rule == null || rule.payload is! RuleRecord) {
        throw const FormatException(
          'Policy must contain distinct visible rules',
        );
      }
      rules.add(rule);
    }
    // Only the selected definition contributes policy rules. Other facts and
    // independently authored rules retain their normal meaning and scope.
    final inactive = <RecordId>{};
    for (final row in byId.values) {
      final payload = row.payload;
      if (payload is! DomainPackRecord ||
          !payload.key.startsWith(universePolicyDefinitionPrefix)) {
        continue;
      }
      final members = <RecordId>{};
      for (final id in payload.records) {
        if (!members.add(id) || byId[id]?.payload is! RuleRecord) {
          throw const FormatException(
            'Policy must contain distinct visible rules',
          );
        }
        if (!seen.contains(id)) {
          inactive.add(id);
        }
      }
    }
    return UniversePolicySelection._(
      selection,
      definition,
      List.unmodifiable(rules),
      Set.unmodifiable(inactive),
    );
  }
}

/// Use only with a complete, admitted snapshot. Permission-filtered projections
/// must receive this set from their owning snapshot reader instead.
Set<RecordId> inactiveUniversePolicyRules(
  UniverseId universe,
  List<RecordVersion> records,
) => records.any(isUniversePolicyRecord)
    ? UniversePolicySelection.fromRecords(universe, records).inactiveRuleIds
    : const {};
