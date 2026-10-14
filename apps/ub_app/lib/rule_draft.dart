import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'expression_draft.dart';
import 'action_draft.dart' show actionValidityInput, buildActionValidity;

DefineRuleOperation ruleOperation(UnfinishedRuleForm form) {
  if ([form.namespace, form.key, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException('Enter a rule namespace and key.');
  }
  if (form.executable == null) {
    throw const FormatException('Choose whether this rule is executable.');
  }
  final labels = <String, String>{};
  for (final l in form.labels) {
    if (labels.containsKey(l.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[l.language] = l.text;
  }
  final original = form.original;
  return DefineRuleOperation(
    clientRef: form.clientRef,
    record: RuleRecord(
      namespace: form.namespace,
      key: form.key,
      labels: labels,
      kind: RuleKind.fromName(form.kind),
      commitPolicy: CommitPolicy.fromName(form.commitPolicy),
      applicability: switch (form.scope.applicability) {
        'universe_wide' => const UniverseApplicability(),
        'worlds' => WorldsApplicability(form.scope.worlds.map(WorldId.parse)),
        'conditional' => const ConditionalApplicability(),
        'unspecified' => const UnspecifiedApplicability(),
        _ => throw const FormatException('Choose rule applicability.'),
      },
      subjectTypes: form.subjectTypes.map(RecordId.parse),
      targetPredicates: form.targetPredicates,
      expression: buildExpression(form.expression),
      capabilities: form.capabilities,
      executable: form.executable!,
      validity: buildActionValidity(form.validity, original?.validity),
      knowledgeBoundary: original?.knowledgeBoundary,
      relationCardinality: original?.relationCardinality,
      knowledgePolicy: original?.knowledgePolicy,
      channelChronology: original?.channelChronology,
    ),
  );
}

UnfinishedRuleForm ruleFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is! DefineRuleOperation) {
    throw const FormatException('Choose a rule definition from Changes.');
  }
  final record = operation.record;
  return UnfinishedRuleForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    namespace: record.namespace,
    key: record.key,
    labels: record.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    kind: record.kind.wireName,
    commitPolicy: record.commitPolicy.wireName,
    scope: ScopeInput(
      applicability: switch (record.applicability) {
        UniverseApplicability() => 'universe_wide',
        WorldsApplicability() => 'worlds',
        ConditionalApplicability() => 'conditional',
        UnspecifiedApplicability() => 'unspecified',
      },
      worlds: record.applicability is WorldsApplicability
          ? (record.applicability as WorldsApplicability).worldIds
                .map((v) => v.value)
                .toList()
          : [],
      contextRecord: draft.content.representedContext.value,
    ),
    subjectTypes: record.subjectTypes.map((v) => v.value),
    targetPredicates: record.targetPredicates,
    capabilities: record.capabilities,
    expression: expressionInput(record.expression),
    executable: record.executable,
    validity: actionValidityInput(record.validity),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest ruleDraftRequest({
  required SavedDraft draft,
  required UnfinishedRuleForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this rule definition.',
    );
  }
  final operation = ruleOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = ruleFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current rule-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This rule definition is already in Changes. Edit it there.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }
    }
    operations.add(operation);
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: DraftContent(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      operations: operations,
      rationale: index == null
          ? [
              if (draft.content.rationale.isNotEmpty) draft.content.rationale,
              if (form.rationale.isNotEmpty) form.rationale,
            ].join('\n\n')
          : draft.content.rationale,
    ),
  );
}
