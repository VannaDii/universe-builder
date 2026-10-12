import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_actions.dart';
import 'writing_aliases.dart';
import 'writing_candidate.dart';
import 'writing_connected.dart';
import 'writing_contexts.dart';
import 'writing_definitions.dart';
import 'writing_event_edits.dart';
import 'writing_initializations.dart';
import 'writing_narrative.dart';
import 'writing_objects.dart';
import 'writing_policies.dart';
import 'writing_powers.dart';
import 'writing_properties.dart';
import 'writing_relations.dart';
import 'writing_units.dart';

({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
})
compileWritingWorlds({
  required List<RecordVersion> rows,
  required List<WritingWorld> declarations,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      unchanged = <String>[],
      clarifications = <String>[];
  final introduced = <String>{};
  for (final declaration in declarations) {
    final key = selectorKey(declaration.name);
    final matches = rows.where((row) {
      if (row.payload case WorldRecord(:final selector, :final aliases)) {
        return [selector, ...aliases].any((name) {
          try {
            return selectorKey(name) == key;
          } on FormatException {
            return false;
          }
        });
      }
      return false;
    }).toList();
    if (matches.length == 1) {
      unchanged.add('Existing world: ${declaration.name}');
    } else if (matches.isEmpty && declaration.introduce && worldScope == null) {
      if (!introduced.add(key)) {
        unchanged.add(
          'World already introduced in this delta: ${declaration.name}',
        );
      } else {
        operations.add(
          CreateWorldOperation(
            clientRef: RecordId.generate().value,
            record: WorldRecord(selector: declaration.name),
          ),
        );
        additions.add('New world: ${declaration.name}');
      }
    } else {
      clarifications.add(
        "Select one accessible authored world named '${declaration.name}', or explicitly introduce it with universe-wide authoring access.",
      );
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(clarifications),
  );
}

List<String> _sortedUnique(List<String> values) => [
  for (final entry in CanonicalObject(
    values.toSet().map((v) => MapEntry(v, const CanonicalNull())),
  ).fields)
    entry.key,
];

/// Compose the ordinary writer stages in canonical workflow order. Input dates
/// must already be normalized against admitted pinned rows. Full base rows are
/// used only for the world candidate, as in the existing workflow; all other
/// stages receive the admitted pinned view. This does not persist a proposal.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
  List<String> excluded,
  List<String> unknowns,
})
compileWritingChanges({
  required Frame frame,
  required List<RecordVersion> base,
  required List<RecordVersion> visibleRows,
  required CheckChangesRequest input,
  required List<RecordVersion> Function(ContinuityId, RevisionId) canonAt,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      unchanged = <String>[],
      clarifications = [...input.questions],
      excluded = <String>[],
      unknowns = <String>[];
  void add({
    required List<DomainOperation> ops,
    required List<String> added,
    required List<String> clarify,
    List<String> same = const [],
    List<String> omit = const [],
    List<String> unknown = const [],
  }) {
    operations.addAll(ops);
    additions.addAll(added);
    clarifications.addAll(clarify);
    unchanged.addAll(same);
    excluded.addAll(omit);
    unknowns.addAll(unknown);
  }

  List<RecordVersion> candidate(List<RecordVersion> pinned) =>
      compileWritingCandidate(
        universe: frame.universe,
        revision: frame.revision,
        base: pinned,
        operations: operations,
      );

  final contexts = compileWritingContexts(
    frame: frame,
    rows: visibleRows,
    declarations: input.storyContexts,
    worldScope: worldScope,
  );
  add(
    ops: contexts.operations,
    added: contexts.additions,
    clarify: contexts.clarifications,
    same: contexts.unchanged,
  );
  final narrative = compileWritingNarrative(
    frame: frame,
    rows: visibleRows,
    input: input,
    canonAt: canonAt,
    worldScope: worldScope,
  );
  add(
    ops: narrative.operations,
    added: narrative.additions,
    clarify: narrative.clarifications,
    same: narrative.unchanged,
  );
  final worlds = compileWritingWorlds(
    rows: visibleRows,
    declarations: input.worlds,
    worldScope: worldScope,
  );
  add(
    ops: worlds.operations,
    added: worlds.additions,
    clarify: worlds.clarifications,
    same: worlds.unchanged,
  );
  final worldRows = candidate(base);
  final units = compileWritingUnits(input.units, visibleRows);
  add(
    ops: units.operations,
    added: units.additions,
    clarify: units.clarifications,
    same: units.unchanged,
  );
  final propertyRows = candidate(visibleRows);
  final properties = compileWritingProperties(
    universe: frame.universe,
    rows: propertyRows,
    declarations: input.properties,
    corrections: input.propertyCorrections,
  );
  add(
    ops: properties.operations,
    added: properties.additions,
    clarify: properties.clarifications,
    same: properties.unchanged,
  );
  final definitions = compileWritingDefinitions(
    declarations: input.definitions,
    rows: visibleRows,
    worldRows: worldRows,
    worldScope: worldScope,
  );
  add(
    ops: definitions.operations,
    added: definitions.additions,
    clarify: definitions.clarifications,
    unknown: definitions.unknowns,
  );
  final objects = compileWritingObjects(
    frame: frame,
    rows: visibleRows,
    propertyRows: propertyRows,
    worldRows: worldRows,
    changes: input.changes,
    definitions: input.definitions,
    introducedDefinitions: definitions.introduced,
    ambiguousDefinitions: definitions.ambiguous,
    declaredProperties: properties.properties,
    worldScope: worldScope,
  );
  add(
    ops: objects.operations,
    added: objects.additions,
    clarify: objects.clarifications,
    same: objects.unchanged,
    omit: objects.excluded,
    unknown: objects.unknowns,
  );
  final aliases = compileWritingAliases(
    frame: frame,
    base: visibleRows,
    aliases: input.aliases,
  );
  add(
    ops: aliases.operations,
    added: aliases.additions,
    clarify: aliases.clarifications,
    same: aliases.unchanged,
  );

  if (input.actions.isNotEmpty ||
      input.constraints.isNotEmpty ||
      input.actionCorrections.isNotEmpty ||
      input.definitionCorrections.isNotEmpty ||
      input.knowledgePolicies.isNotEmpty ||
      input.knowledgeBoundaries.isNotEmpty ||
      input.exhaustiveSets.isNotEmpty ||
      input.itemPowers.isNotEmpty ||
      input.itemPowerCorrections.isNotEmpty ||
      input.policyCorrections.isNotEmpty) {
    // All contracts bind the same snapshot. Do not refresh between these groups.
    final rows = candidate(visibleRows);
    final policyEdits = compileWritingPolicies(
      universe: frame.universe,
      frame: frame,
      rows: rows,
      corrections: input.policyCorrections,
      boundaries: [],
      policies: [],
      constraints: [],
      worldScope: worldScope,
    );
    add(
      ops: policyEdits.operations,
      added: policyEdits.additions,
      clarify: policyEdits.clarifications,
    );
    final powers = compileWritingPowersAndSets(
      universe: frame.universe,
      frame: frame,
      rows: rows,
      powers: input.itemPowers,
      corrections: input.itemPowerCorrections,
      exhaustiveSets: input.exhaustiveSets,
      worldScope: worldScope,
    );
    add(
      ops: powers.operations,
      added: powers.additions,
      clarify: powers.clarifications,
    );
    final actions = compileWritingActions(
      universe: frame.universe,
      frame: frame,
      base: visibleRows,
      rows: rows,
      declarations: input.actions,
      corrections: input.actionCorrections,
      worldScope: worldScope,
    );
    add(
      ops: actions.operations,
      added: actions.additions,
      clarify: actions.clarifications,
    );
    final definitionEdits = compileWritingDefinitionCorrections(
      universe: frame.universe,
      base: visibleRows,
      rows: rows,
      corrections: input.definitionCorrections,
      worldScope: worldScope,
    );
    add(
      ops: definitionEdits.operations,
      added: definitionEdits.additions,
      clarify: definitionEdits.clarifications,
    );
    final policies = compileWritingPolicies(
      universe: frame.universe,
      frame: frame,
      rows: rows,
      corrections: [],
      boundaries: input.knowledgeBoundaries,
      policies: input.knowledgePolicies,
      constraints: input.constraints,
      worldScope: worldScope,
    );
    add(
      ops: policies.operations,
      added: policies.additions,
      clarify: policies.clarifications,
    );
  }
  final relations = compileWritingRelations(
    universe: frame.universe,
    frame: frame,
    base: visibleRows,
    input: input,
    priorOperations: operations,
    worldScope: worldScope,
  );
  add(
    ops: relations.operations,
    added: relations.additions,
    clarify: relations.clarifications,
    same: relations.unchanged,
    omit: relations.excluded,
  );
  final initializations = compileWritingInitializations(
    frame: frame,
    base: visibleRows,
    input: input,
    priorOperations: operations,
    worldScope: worldScope,
  );
  add(
    ops: initializations.operations,
    added: initializations.additions,
    clarify: initializations.clarifications,
  );
  final eventEdits = compileWritingEventEdits(
    frame: frame,
    base: visibleRows,
    corrections: input.eventCorrections,
    withdrawals: input.eventWithdrawals,
    priorOperations: operations,
    worldScope: worldScope,
  );
  add(
    ops: eventEdits.operations,
    added: eventEdits.additions,
    clarify: eventEdits.clarifications,
  );
  final connected = compileConnectedWriting(
    frame: frame,
    base: visibleRows,
    input: input,
    priorOperations: operations,
  );
  add(
    ops: connected.operations,
    added: connected.additions,
    clarify: connected.clarifications,
  );
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(_sortedUnique(clarifications)),
    excluded: List.unmodifiable(excluded),
    unknowns: List.unmodifiable(_sortedUnique(unknowns)),
  );
}
