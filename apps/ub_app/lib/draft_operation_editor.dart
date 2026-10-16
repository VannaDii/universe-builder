import 'event_editor_page.dart';
import 'secret_editor_page.dart';
import 'appearance_editor_page.dart';
import 'story_time_editor_page.dart';
import 'action_editor_page.dart';
import 'rule_editor_page.dart';
import 'completeness_editor_page.dart';
import 'proposition_editor_page.dart';
import 'attitude_editor_page.dart';
import 'interpretation_editor_page.dart';
import 'assertion_retraction_editor_page.dart';
import 'event_withdrawal_editor_page.dart';
import 'record_removal_editor_page.dart';
import 'assertion_correction_editor_page.dart';
import 'assertion_end_editor_page.dart';
import 'observation_editor_page.dart';
import 'memory_editor_page.dart';
import 'work_editor_page.dart';
import 'saga_editor_page.dart';
import 'work_version_editor_page.dart';
import 'scene_editor_page.dart';
import 'passage_editor_page.dart';
import 'boundary_editor_page.dart';
import 'exception_editor_page.dart';
import 'issue_decision_editor_page.dart';
import 'initialization_editor_page.dart';
import 'represented_context_editor_page.dart';
import 'item_power_editor_page.dart';
import 'plan_editor_page.dart';
import 'commitment_editor_page.dart';
import 'communication_editor_page.dart';
import 'type_editor_page.dart';
import 'property_editor_page.dart';
import 'unit_editor_page.dart';
import 'value_definition_editor_page.dart';
import 'relation_editor_page.dart';
import 'source_editor_page.dart';
import 'calendar_editor_page.dart';
import 'pack_editor_page.dart';
import 'universe_policies.dart';
import 'entity_editor_page.dart';
import 'attribute_editor_page.dart';
import 'world_editor_page.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'saved_changes.dart';
import 'source_draft.dart';
import 'draft_record_choices.dart';
import 'attribute_draft.dart';

Future<Widget> draftOperationEditor(
  SavedChanges changes,
  SavedDraft draft,
  int index,
) async {
  if (!changes.session.author ||
      draft.content.proposal != null ||
      index < 0 ||
      index >= draft.content.operations.length) {
    throw const FormatException('This draft operation is not editable.');
  }
  final operation = draft.content.operations[index];
  SavedChanges scopedChanges(String clientRef) => SavedChanges(
    session: changes.session,
    universe: changes.universe,
    scope: EditorFormScope(
      instance: changes.scope.instance,
      profile: changes.scope.profile,
      universe: changes.scope.universe,
      continuity: changes.scope.continuity,
      representedContext: draft.content.representedContext,
      typeClientRef: clientRef,
    ),
  );
  if (operation is IntroduceDefinitionOperation ||
      (operation is ReviseDefinitionOperation &&
          operation.replacement is EntityTypeRecord) ||
      operation is IntroduceInstanceOperation ||
      operation is AddNameOperation ||
      operation is RefineClassificationOperation) {
    final summary = Envelope<Description>.fromWire(
      await changes.session.call(
        ToolEngineRequest(
          request: DescribeSummaryRequest(
            universe: changes.universe,
            universeId: changes.scope.universe,
          ),
        ),
      ),
      Description.fromWire,
    ).result;
    final continuity = summary.continuities.singleWhere(
      (item) => item.id == changes.scope.continuity,
    );
    final representedContext = continuity.representedContexts.singleWhere(
      (item) => item.id == draft.content.representedContext,
    );
    if (operation is IntroduceDefinitionOperation ||
        operation is ReviseDefinitionOperation) {
      return TypeEditorPage(
        session: changes.session,
        universe: LibraryEntry(changes.scope.universe, changes.universe.value),
        continuity: continuity,
        representedContext: representedContext,
        scope: EditorFormScope(
          instance: changes.scope.instance,
          profile: changes.scope.profile,
          universe: changes.scope.universe,
          continuity: changes.scope.continuity,
          representedContext: draft.content.representedContext,
          typeClientRef: switch (draft.content.operations[index]) {
            IntroduceDefinitionOperation(:final clientRef) => clientRef,
            ReviseDefinitionOperation(:final record) => record.record.value,
            _ => throw const FormatException('Choose a type definition.'),
          },
        ),
        editingDraft: draft,
        operationIndex: index,
      );
    }
    final name = operation is AddNameOperation ? operation : null;
    final classification = operation is RefineClassificationOperation
        ? operation
        : null;
    return EntityEditorPage(
      session: changes.session,
      universe: LibraryEntry(changes.scope.universe, changes.universe.value),
      continuity: continuity,
      representedContext: representedContext,
      scope: EditorFormScope(
        instance: changes.scope.instance,
        profile: changes.scope.profile,
        universe: changes.scope.universe,
        continuity: changes.scope.continuity,
        representedContext: draft.content.representedContext,
        entityClientRef: name == null && classification == null
            ? (operation as IntroduceInstanceOperation).clientRef
            : null,
        entityNameRecord: name?.record.record,
        entityClassificationRecord: classification?.record.record,
        entityOperationIndex: name == null && classification == null
            ? null
            : index,
      ),
      editingDraft: draft,
      operationIndex: index,
    );
  }
  if(operation is SetStoryTimeOperation) {
    return StoryTimeEditorPage(changes:scopedChanges(operation.record.record.value),
      revision:draft.content.baseRevision,editingDraft:draft,index:index);
  }
  if (operation is CreateSecretOperation || operation is ReviseSecretOperation) {
    final clientRef = switch (operation) {
      CreateSecretOperation(:final clientRef) => clientRef,
      ReviseSecretOperation(:final record) => 'secret-revision:${record.record.value}',
      _ => throw StateError('Checked secret operation'),
    };
    return SecretEditorPage(
      changes: scopedChanges(clientRef),
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
    );
  }
  if (operation is CreateAppearanceOperation || operation is ReviseAppearanceOperation) {
    final clientRef = switch (operation) {
      CreateAppearanceOperation(:final clientRef) => clientRef,
      ReviseAppearanceOperation(:final record) => 'appearance-revision:${record.record.value}',
      _ => throw StateError('Checked appearance operation'),
    };
    return AppearanceEditorPage(
      changes: scopedChanges(clientRef),
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
    );
  }
  if (operation is DefinePropertyOperation) {
    return PropertyEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineUnitOperation) {
    return UnitEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineValueOperation) {
    return ValueDefinitionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is AddSourceAnchorOperation) {
    final form = sourceAnchorFormFromDraft(draft, index);
    final opened = await openDraftChoiceContext(changes, draft);
    return SourceEditorPage(
      revision: draft.content.baseRevision,
      source: form.anchorSource,
      context: opened.contextId,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(form.clientRef),
    );
  }
  if (operation is DefineRelationOperation) {
    return RelationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordEventOperation) {
    return EventEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineActionOperation) {
    return ActionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineRuleOperation) {
    return RuleEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordCommunicationOperation) {
    return CommunicationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordCommitmentOperation) {
    return CommitmentEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordPlanOperation) {
    return PlanEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineItemPowerOperation) {
    return ItemPowerEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordNarrativeReferenceOperation &&
      operation.record == RecordKind.representedContext) {
    return RepresentedContextEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is InitializeInstanceOperation) {
    return InitializationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordIssueDecisionOperation) {
    return IssueDecisionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is AddExceptionOperation) {
    return ExceptionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is SetCreativeBoundaryOperation) {
    return BoundaryEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is CreateWorkOperation) {
    return WorkEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is AssociateWorkWorldOperation) {
    return WorkEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is RecordNarrativeReferenceOperation &&
      operation.record == RecordKind.workVersion) {
    return WorkVersionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordNarrativeReferenceOperation &&
      operation.record == RecordKind.sceneRef) {
    return SceneEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordNarrativeReferenceOperation &&
      operation.record == RecordKind.passageRef) {
    return PassageEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is ReviseSceneOperation) {
    return SceneEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseItemPowerOperation) {
    return ItemPowerEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseCommunicationOperation) {
    return CommunicationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseAttitudeOperation) {
    return AttitudeEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is PropertyRecord) {
    return PropertyEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is RelationRecord) {
    return RelationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is UnitRecord) {
    return UnitEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is CalendarRecord) {
    return CalendarEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is UpgradePackOperation) {
    return PackEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is ActionDefinitionRecord) {
    return ActionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is ValueDefinitionRecord) {
    return ValueDefinitionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is RuleRecord) {
    return RuleEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseInterpretationOperation) {
    return InterpretationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is RetractAssertionOperation) {
    return AssertionRetractionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is WithdrawEventOperation) {
    return EventWithdrawalEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is TombstoneRecordOperation) {
    return RecordRemovalEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is ReviseEventOperation) {
    return EventEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is SupersedeAssertionOperation) {
    return AssertionCorrectionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is EndAssertionAtOperation) {
    return AssertionEndEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is SetWorkBindingOperation) {
    return WorkVersionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is CreateSagaOperation) {
    return SagaEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is SetSagaMembershipOperation) {
    return SagaEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.record.record.value),
    );
  }
  if (operation is RecordMemoryOperation) {
    return MemoryEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is RecordObservationOperation) {
    return ObservationEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is AddBeliefOperation) {
    return AttitudeEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefinePropositionOperation) {
    return PropositionEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is SetCompletenessOperation) {
    return CompletenessEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineCalendarOperation) {
    return CalendarEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (operation is DefineUniversePolicyOperation) {
    final policies = await readUniversePolicyChoices(changes, draft);
    return PackEditorPage(
      revision: draft.content.baseRevision, editingDraft: draft, index: index,
      changes: scopedChanges(operation.clientRef), definePolicy: true,
      rootVersion: policies.selection?.recordVersionId,
    );
  }
  if (operation is InstallPackOperation) {
    return PackEditorPage(
      revision: draft.content.baseRevision,
      editingDraft: draft,
      index: index,
      changes: scopedChanges(operation.clientRef),
    );
  }
  if (isEditableAttribute(operation)) {
    return AttributeEditorPage(changes: changes, draft: draft, index: index);
  }
  if (operation is CreateWorldOperation) {
    return WorldEditorPage.edit(changes: changes, draft: draft, index: index);
  }
  throw const FormatException(
    'No field editor is available for this draft operation.',
  );
}
