import 'entity_editor_page.dart';
import 'secret_editor_page.dart';
import 'appearance_editor_page.dart';
import 'story_time_editor_page.dart';
import 'attribute_editor_page.dart';
import 'source_editor_page.dart';
import 'work_version_editor_page.dart';
import 'saga_editor_page.dart';
import 'work_editor_page.dart';
import 'scene_editor_page.dart';
import 'item_power_editor_page.dart';
import 'communication_editor_page.dart';
import 'attitude_editor_page.dart';
import 'property_editor_page.dart';
import 'relation_editor_page.dart';
import 'unit_editor_page.dart';
import 'calendar_editor_page.dart';
import 'pack_editor_page.dart';
import 'action_editor_page.dart';
import 'rule_editor_page.dart';
import 'value_definition_editor_page.dart';
import 'type_editor_page.dart';
import 'interpretation_editor_page.dart';
import 'assertion_retraction_editor_page.dart';
import 'event_withdrawal_editor_page.dart';
import 'record_removal_editor_page.dart';
import 'event_editor_page.dart';
import 'assertion_correction_editor_page.dart';
import 'assertion_end_editor_page.dart';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'saved_changes.dart';
import 'record_edit_action.dart';

/// Menu selections and authenticated browser links open the same recoverable form.
Future<Widget> recordEditorPage({
  required AppSession session,
  required LibraryEntry universe,
  required ContinuitySummary continuity,
  required RepresentedContextSummary representedContext,
  required OpenedContext opened,
  required EditorFormScope scope,
  required RecordVersion record,
  required RecordEditAction action,
}) async {
  if (!session.author || !action.supports(record.payload)) {
    throw const FormatException('This record action is unavailable.');
  }
  final revision = opened.frame.revision;
  final pinned = ContinuitySummary(
    id: continuity.id,
    revisionId: revision,
    name: continuity.name,
    representedContexts: continuity.representedContexts,
  );
  EditorFormScope editorScope({
    String? clientRef,
    bool name = false,
    bool classification = false,
  }) => EditorFormScope(
    instance: scope.instance,
    profile: scope.profile,
    universe: universe.id,
    continuity: continuity.id,
    representedContext: representedContext.id,
    typeClientRef: clientRef,
    entityNameRecord: name ? record.identity.recordId : null,
    entityClassificationRecord: classification
        ? record.identity.recordId
        : null,
  );
  final changes = SavedChanges(
    session: session,
    universe: Selector(universe.name),
    scope: editorScope(
      clientRef: action == RecordEditAction.sourceExcerpt
          ? record.recordVersionId.value
          : action == RecordEditAction.secretRevision
          ? 'secret-revision:${record.identity.recordId.value}'
          : action == RecordEditAction.appearanceRevision
          ? 'appearance-revision:${record.identity.recordId.value}'
          : action == RecordEditAction.attribute ||
                action == RecordEditAction.relationship
          ? null
          : record.identity.recordId.value,
    ),
  );
  if (action == RecordEditAction.attribute ||
      action == RecordEditAction.relationship) {
    final draft =
        await changes.load() ??
        SavedDraft(
          version: BigInt.zero,
          content: DraftContent(
            baseRevision: revision,
            representedContext: representedContext.id,
            operations: [],
            rationale: '',
          ),
        );
    return AttributeEditorPage.create(
      changes: changes,
      draft: draft,
      publishedEntity: record,
      relationship: action == RecordEditAction.relationship,
      openedRevision: revision,
    );
  }
  return switch (action) {
    RecordEditAction.storyTime => StoryTimeEditorPage(changes:changes,revision:revision,sourceRecord:record),
    RecordEditAction.workAssociation => WorkEditorPage(
      revision: revision,
      associationRecord: record,
      changes: changes,
    ),
    RecordEditAction.sagaMembership => SagaEditorPage(
      revision: revision,
      membershipRecord: record,
      changes: changes,
    ),
    RecordEditAction.canonBinding => WorkVersionEditorPage(
      revision: revision,
      bindingRecord: record,
      changes: changes,
    ),
    RecordEditAction.sceneCorrection => SceneEditorPage(
      revision: revision,
      correctionRecord: record,
      changes: changes,
    ),
    RecordEditAction.itemPowerCorrection => ItemPowerEditorPage(
      revision: revision,
      correctionRecord: record,
      changes: changes,
    ),
    RecordEditAction.communicationCorrection => CommunicationEditorPage(
      revision: revision,
      correctionRecord: record,
      changes: changes,
    ),
    RecordEditAction.attitudeCorrection => AttitudeEditorPage(
      revision: revision,
      correctionRecord: record,
      changes: changes,
    ),
    RecordEditAction.propertyRevision => PropertyEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.relationRevision => RelationEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.unitRevision => UnitEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.calendarRevision => CalendarEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.packUpgrade => PackEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.actionRevision => ActionEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.ruleRevision => RuleEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.assertionRetraction => AssertionRetractionEditorPage(
      revision: revision,
      sourceRecord: record,
      changes: changes,
    ),
    RecordEditAction.eventWithdrawal => EventWithdrawalEditorPage(
      revision: revision,
      sourceRecord: record,
      changes: changes,
    ),
    RecordEditAction.secretRevision => SecretEditorPage(
      revision: revision,
      correctionRecord: record,
      changes: changes,
    ),
    RecordEditAction.appearanceRevision => AppearanceEditorPage(
      revision: revision,
      correctionRecord: record,
      changes: changes,
    ),
    RecordEditAction.recordRemoval => RecordRemovalEditorPage(
      revision: revision,
      sourceRecord: record,
      changes: changes,
    ),
    RecordEditAction.eventRevision => EventEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.assertionCorrection => AssertionCorrectionEditorPage(
      revision: revision,
      sourceRecord: record,
      changes: changes,
    ),
    RecordEditAction.assertionEnd => AssertionEndEditorPage(
      revision: revision,
      sourceRecord: record,
      changes: changes,
    ),
    RecordEditAction.valueRevision => ValueDefinitionEditorPage(
      revision: revision,
      revisionRecord: record,
      changes: changes,
    ),
    RecordEditAction.interpretationCorrection => InterpretationEditorPage(
      revision: revision,
      sourceRecord: record,
      changes: changes,
    ),
    RecordEditAction.typeRevision => TypeEditorPage(
      session: session,
      universe: universe,
      representedContext: representedContext,
      continuity: pinned,
      revisionRecord: record,
      scope: changes.scope,
    ),
    RecordEditAction.sourceExcerpt => SourceEditorPage(
      revision: revision,
      context: opened.contextId,
      source: VersionRef(
        universe: universe.id,
        record: record.identity.recordId,
        version: record.recordVersionId,
      ),
      changes: changes,
    ),
    RecordEditAction.entityName => EntityEditorPage(
      session: session,
      universe: universe,
      continuity: pinned,
      representedContext: representedContext,
      publishedEntity: record,
      scope: editorScope(name: true),
    ),
    RecordEditAction.entityClassification => EntityEditorPage(
      session: session,
      universe: universe,
      continuity: pinned,
      representedContext: representedContext,
      publishedEntity: record,
      refineClassification: true,
      scope: editorScope(classification: true),
    ),
    RecordEditAction.attribute ||
    RecordEditAction.relationship => throw StateError('Handled above'),
  };
}
