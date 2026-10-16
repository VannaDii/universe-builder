import 'ids.dart';
import 'records.dart';
import 'scope.dart';

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
  UniversePolicySelection._(this.selection, this.definition, this.rules);

  final RecordVersion selection, definition;
  final List<RecordVersion> rules;

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
    // A definition that is merely available must not keep enforcing its rules
    // after another root is selected. Shared members of the active root remain
    // active; unrelated rules outside policy definitions are untouched.
    for (final row in byId.values) {
      final payload = row.payload;
      if (payload is! DomainPackRecord ||
          !payload.key.startsWith(universePolicyDefinitionPrefix)) {
        continue;
      }
      for (final id in payload.records) {
        if (seen.contains(id)) {
          continue;
        }
        final member = byId[id]?.payload;
        if (member is! RuleRecord ||
            member.applicability is! UnspecifiedApplicability) {
          throw const FormatException(
            'Unselected policy rules must be unbound templates',
          );
        }
      }
    }
    return UniversePolicySelection._(
      selection,
      definition,
      List.unmodifiable(rules),
    );
  }
}
