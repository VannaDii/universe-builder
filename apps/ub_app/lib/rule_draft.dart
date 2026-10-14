import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'expression_draft.dart';
import 'scope_draft.dart';
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
      knowledgeBoundary: form.knowledge == null
          ? original?.knowledgeBoundary
          : buildRuleKnowledgeBoundary(form.knowledge!),
      relationCardinality: form.constraints == null
          ? original?.relationCardinality
          : buildRuleCardinality(
              form.constraints!,
              original?.relationCardinality,
            ),
      knowledgePolicy: form.knowledge == null
          ? original?.knowledgePolicy
          : buildRuleKnowledgePolicy(form.knowledge!),
      channelChronology: form.constraints == null
          ? original?.channelChronology
          : buildRuleChronology(form.constraints!),
    ),
  );
}

ReviseDefinitionOperation ruleRevisionOperation(UnfinishedRuleForm form) {
  if (form.revisionTarget == null ||
      form.expectedRecordVersion == null ||
      form.original == null) {
    throw const FormatException(
      'Open a published rule definition to revise it.',
    );
  }
  final next = ruleOperation(form).record;
  if (next.namespace != form.original!.namespace ||
      next.key != form.original!.key) {
    throw const FormatException('Rule revisions retain namespace and key.');
  }
  final target = form.revisionTarget!;
  return ReviseDefinitionOperation(
    record: RecordRef(
      record: RecordId.parse(target.record),
      universe: target.universe.isEmpty
          ? null
          : UniverseId.parse(target.universe),
    ),
    expectedVersion: form.expectedRecordVersion!,
    replacement: next,
  );
}

UnfinishedRuleForm ruleRevisionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! RuleRecord) {
    throw const FormatException('Choose a published rule definition.');
  }
  return _ruleForm(
    record: record.payload as RuleRecord,
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: record.identity.recordId.value,
    revisionTarget: ExpressionReferenceInput(
      record: record.identity.recordId.value,
      universe: record.identity.universeId.value,
    ),
    expectedRecordVersion: record.recordVersionId,
  );
}

UnfinishedRuleForm ruleFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is RuleRecord) {
    return _ruleForm(
      record: operation.replacement as RuleRecord,
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      clientRef: operation.record.record.value,
      revisionTarget: ExpressionReferenceInput(
        record: operation.record.record.value,
        universe: operation.record.universe?.value ?? '',
      ),
      expectedRecordVersion: operation.expectedVersion,
      draftVersion: draft.version,
    );
  }
  if (operation is! DefineRuleOperation) {
    throw const FormatException('Choose a rule definition from Changes.');
  }
  return _ruleForm(
    record: operation.record,
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    draftVersion: draft.version,
  );
}

UnfinishedRuleForm _ruleForm({
  required RuleRecord record,
  required RevisionId baseRevision,
  required RecordId representedContext,
  required String clientRef,
  ExpressionReferenceInput? revisionTarget,
  RecordVersionId? expectedRecordVersion,
  BigInt? draftVersion,
}) => UnfinishedRuleForm(
  baseRevision: baseRevision,
  representedContext: representedContext,
  clientRef: clientRef,
  revisionTarget: revisionTarget,
  expectedRecordVersion: expectedRecordVersion,
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
    contextRecord: representedContext.value,
  ),
  subjectTypes: record.subjectTypes.map((v) => v.value),
  targetPredicates: record.targetPredicates,
  capabilities: record.capabilities,
  expression: expressionInput(record.expression),
  executable: record.executable,
  validity: actionValidityInput(record.validity),
  original: record,
  knowledge: ruleKnowledgeInput(record),
  constraints: ruleConstraintInput(record),
  draftVersion: draftVersion,
);

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
  final operation = form.revisionTarget == null
      ? ruleOperation(form)
      : ruleRevisionOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = ruleFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef ||
        form.revisionTarget?.toWire().toText() !=
            before.revisionTarget?.toWire().toText() ||
        form.expectedRecordVersion != before.expectedRecordVersion) {
      throw const FormatException(
        'The draft changed. Reopen its current rule-definition fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      if (operation is ReviseDefinitionOperation &&
          existing is ReviseDefinitionOperation &&
          existing.record == operation.record) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This rule already has a revision. Edit it in Changes.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }

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

ExpressionReferenceInput _knowledgeRef(RecordRef? reference) =>
    reference == null
    ? const ExpressionReferenceInput()
    : ExpressionReferenceInput(
        record: reference.record.value,
        universe: reference.universe?.value ?? '',
      );
RecordRef _buildKnowledgeRef(ExpressionReferenceInput reference) => RecordRef(
  record: RecordId.parse(reference.record),
  universe: reference.universe.isEmpty
      ? null
      : UniverseId.parse(reference.universe),
);
RuleKnowledgeInput ruleKnowledgeInput(RuleRecord rule) => RuleKnowledgeInput(
  policyEnabled: rule.knowledgePolicy != null,
  boundaryEnabled: rule.knowledgeBoundary != null,
  mode: rule.knowledgePolicy?.mode.wireName ?? '',
  policyContext: _knowledgeRef(rule.knowledgePolicy?.context),
  holder: _knowledgeRef(rule.knowledgeBoundary?.holder),
  proposition: _knowledgeRef(rule.knowledgeBoundary?.proposition),
  boundaryContext: _knowledgeRef(rule.knowledgeBoundary?.context),
);
KnowledgePolicy? buildRuleKnowledgePolicy(RuleKnowledgeInput input) =>
    input.policyEnabled
    ? KnowledgePolicy(
        context: _buildKnowledgeRef(input.policyContext),
        mode: KnowledgeMode.fromName(input.mode),
      )
    : null;
KnowledgeBoundary? buildRuleKnowledgeBoundary(RuleKnowledgeInput input) =>
    input.boundaryEnabled
    ? KnowledgeBoundary(
        holder: _buildKnowledgeRef(input.holder),
        proposition: _buildKnowledgeRef(input.proposition),
        context: _buildKnowledgeRef(input.boundaryContext),
      )
    : null;

RuleConstraintInput ruleConstraintInput(RuleRecord rule) {
  final cardinality = rule.relationCardinality,
      chronology = rule.channelChronology;
  return RuleConstraintInput(
    cardinalityEnabled: cardinality != null,
    chronologyEnabled: chronology != null,
    relation: _knowledgeRef(cardinality?.relation),
    grouping: cardinality?.grouping is SubjectCardinalityKey
        ? 'subject'
        : cardinality?.grouping is RoleCardinalityKey
        ? 'role'
        : '',
    groupingRole: cardinality?.grouping is RoleCardinalityKey
        ? (cardinality!.grouping as RoleCardinalityKey).role
        : '',
    countedRole: cardinality?.countedRole ?? '',
    maximum: cardinality?.maximum.toString() ?? '',
    scope: cardinality == null
        ? const ScopeInput()
        : scopeInput(cardinality.scope),
    validity: cardinality == null
        ? const TemporalValidityInput(kind: 'unspecified')
        : actionValidityInput(cardinality.validity),
    channel: chronology?.channel ?? '',
    forwardOnly: chronology?.forwardOnly,
    minimumEnabled: chronology?.minimumDelay != null,
    maximumEnabled: chronology?.maximumDelay != null,
    minimumDelay: chronology?.minimumDelay ?? '',
    maximumDelay: chronology?.maximumDelay ?? '',
  );
}

RelationCardinality? buildRuleCardinality(
  RuleConstraintInput input,
  RelationCardinality? original,
) => !input.cardinalityEnabled
    ? null
    : RelationCardinality(
        relation: _buildKnowledgeRef(input.relation),
        grouping: switch (input.grouping) {
          'subject' => const SubjectCardinalityKey(),
          'role' => RoleCardinalityKey(input.groupingRole),
          _ => throw const FormatException('Choose cardinality grouping.'),
        },
        countedRole: input.countedRole,
        maximum: int.parse(input.maximum),
        scope: buildScope(input.scope),
        validity: buildActionValidity(input.validity, original?.validity),
      );
ChannelChronology? buildRuleChronology(RuleConstraintInput input) =>
    !input.chronologyEnabled
    ? null
    : ChannelChronology(
        channel: input.channel,
        forwardOnly:
            input.forwardOnly ??
            (throw const FormatException(
              'Choose whether the channel is forward-only.',
            )),
        minimumDelay: input.minimumEnabled ? input.minimumDelay : null,
        maximumDelay: input.maximumEnabled ? input.maximumDelay : null,
      );
