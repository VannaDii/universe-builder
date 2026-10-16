import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choices.dart';
import 'saved_changes.dart';

/// Visible policy metadata at the draft's exact revision. Rule bodies remain
/// available through the normal record browser; this is not an evaluation.
final class UniversePolicyChoices {
  UniversePolicyChoices(this.context, this.selection, this.definitions);
  final OpenedContext context;
  final RecordVersion? selection;
  final List<RecordVersion> definitions;
  RecordId? get selected =>
      (selection?.payload as DomainPackRecord?)?.records.single;
}

Future<UniversePolicyChoices> readUniversePolicyChoices(
  SavedChanges changes,
  SavedDraft draft,
) async {
  final context = await openDraftChoiceContext(changes, draft);
  final packs = <RecordVersion>[];
  String? cursor;
  final seen = <String>{};
  do {
    final page = await searchDraftChoices(
      changes: changes,
      context: context,
      kind: RecordKind.domainPack,
      cursor: cursor,
    );
    if (page.result.hits.isNotEmpty) {
      final result = Envelope<Records>.fromWire(
        await changes.session.call(
          ToolEngineRequest(
            request: GetRequest(
              universe: changes.universe,
              universeId: changes.scope.universe,
              contextId: context.contextId,
              recordIds: page.result.hits.map((hit) => hit.recordId).toSet(),
              fieldGroups: [FieldGroup.payload],
            ),
          ),
        ),
        Records.fromWire,
      );
      final expected = page.result.hits.map((hit) => hit.recordId).toSet();
      if (!result.delivery.complete ||
          !result.result.records
              .map((row) => row.identity.recordId)
              .toSet()
              .containsAll(expected)) {
        throw const FormatException('Policy details are incomplete.');
      }
      packs.addAll(result.result.records.where(isUniversePolicyRecord));
    }
    if (page.delivery.complete) {
      break;
    }
    cursor = page.delivery.cursor;
    if (cursor == null || !seen.add(cursor)) {
      throw const FormatException('Policy list is incomplete.');
    }
  } while (true);
  final selections = packs
      .where(
        (row) =>
            (row.payload as DomainPackRecord).key == universePolicySelectionKey,
      )
      .toList();
  final definitions = packs
      .where(
        (row) => (row.payload as DomainPackRecord).key.startsWith(
          universePolicyDefinitionPrefix,
        ),
      )
      .toList();
  if (selections.length > 1 || (selections.isEmpty && definitions.isNotEmpty)) {
    throw const FormatException('The universe root is unavailable.');
  }
  final selection = selections.singleOrNull;
  if (selection != null) {
    final root = selection.payload as DomainPackRecord;
    final selected = definitions
        .where((row) => root.records.contains(row.identity.recordId))
        .singleOrNull;
    if (root.records.length != 1 ||
        selected == null ||
        root.dependencies.length != 1 ||
        root.dependencies[(selected.payload as DomainPackRecord).key] !=
            (selected.payload as DomainPackRecord).version) {
      throw const FormatException('The selected policy is unavailable.');
    }
  }
  return UniversePolicyChoices(
    context,
    selection,
    List.unmodifiable(definitions),
  );
}

UpgradePackOperation selectUniversePolicy(
  RecordVersion selection,
  RecordVersion definition,
) {
  final policy = definition.payload as DomainPackRecord;
  if ((selection.payload as DomainPackRecord).key !=
          universePolicySelectionKey ||
      !policy.key.startsWith(universePolicyDefinitionPrefix) ||
      selection.identity.universeId != definition.identity.universeId) {
    throw const FormatException('Choose a defined policy in this universe.');
  }
  return UpgradePackOperation(
    record: RecordRef(
      universe: selection.identity.universeId,
      record: selection.identity.recordId,
    ),
    expectedVersion: selection.recordVersionId,
    replacement: DomainPackRecord(
      key: universePolicySelectionKey,
      version: RecordVersionId.generate().value,
      dependencies: {policy.key: policy.version},
      capabilities: [],
      records: [definition.identity.recordId],
    ),
  );
}

bool isUniverseRootChange(DomainOperation operation) => switch (operation) {
  DefineUniversePolicyOperation(:final activate) => activate,
  UpgradePackOperation(:final replacement) =>
    replacement.key == universePolicySelectionKey,
  _ => false,
};

SaveDraftEngineRequest universePolicySelectionDraftRequest({
  required SavedDraft draft,
  required Selector universe,
  required ContinuityId continuity,
  required RecordId representedContext,
  required RevisionId revision,
  required RecordVersion selection,
  required RecordVersion definition,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != revision ||
      draft.content.representedContext != representedContext) {
    throw const FormatException(
      'Review Changes and use the current revision before selecting a root.',
    );
  }
  if (draft.content.operations.any(isUniverseRootChange)) {
    throw const FormatException(
      'A root change is already in Changes. Review or edit it there.',
    );
  }
  final operation = selectUniversePolicy(selection, definition);
  final name = (definition.payload as DomainPackRecord).key.substring(
    universePolicyDefinitionPrefix.length,
  );
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: DraftContent(
      baseRevision: revision,
      representedContext: representedContext,
      operations: [...draft.content.operations, operation],
      rationale: [
        if (draft.content.rationale.isNotEmpty) draft.content.rationale,
        'Select universe root: $name.',
      ].join('\n\n'),
    ),
  );
}

String universePolicyChangeLabel(
  DomainOperation operation,
) => switch (operation) {
  DefineUniversePolicyOperation() => 'define universe policy',
  UpgradePackOperation(:final replacement)
      when replacement.key == universePolicySelectionKey =>
    replacement.dependencies.length == 1
        ? 'select universe root: ${replacement.dependencies.keys.single.replaceFirst(universePolicyDefinitionPrefix, '')}'
        : 'select universe root',
  _ => operation.kind.wireName.replaceAll('_', ' '),
};

Future<List<RecordVersion>> readUniversePolicyRulePage({
  required SavedChanges changes,
  required OpenedContext context,
  required RecordVersion definition,
  required int offset,
}) async {
  final pack = definition.payload as DomainPackRecord;
  if (offset < 0 ||
      definition.identity.universeId != changes.scope.universe ||
      !pack.key.startsWith(universePolicyDefinitionPrefix)) {
    throw const FormatException('Choose a policy in this universe.');
  }
  final ids = pack.records.skip(offset).take(50).toList();
  if (ids.isEmpty) {
    return const [];
  }
  final material = Envelope<Records>.fromWire(
    await changes.session.call(
      ToolEngineRequest(
        request: GetRequest(
          universe: changes.universe,
          universeId: changes.scope.universe,
          contextId: context.contextId,
          recordIds: ids.toSet(),
          fieldGroups: [FieldGroup.payload],
        ),
      ),
    ),
    Records.fromWire,
  );
  final rows = {
    for (final row in material.result.records)
      if (row.identity.universeId == changes.scope.universe &&
          row.payload is RuleRecord)
        row.identity.recordId: row,
  };
  if (!material.delivery.complete || !ids.every(rows.containsKey)) {
    throw const FormatException(
      'Some policy rules are unavailable in this context.',
    );
  }
  return [for (final id in ids) rows[id]!];
}
