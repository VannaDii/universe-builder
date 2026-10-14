import 'package:ub_domain/ub_domain.dart';

import 'event_withdrawal_draft.dart';

enum RecordEditAction {
  workAssociation,
  sagaMembership,
  canonBinding,
  sceneCorrection,
  itemPowerCorrection,
  communicationCorrection,
  attitudeCorrection,
  propertyRevision,
  relationRevision,
  unitRevision,
  calendarRevision,
  packUpgrade,
  actionRevision,
  ruleRevision,
  assertionRetraction,
  eventWithdrawal,
  recordRemoval,
  secretRevision,
  appearanceRevision,
  eventRevision,
  assertionCorrection,
  assertionEnd,
  valueRevision,
  typeRevision,
  interpretationCorrection,
  sourceExcerpt,
  entityName,
  entityClassification,
  attribute,
  relationship;

  /// A URL can select only an action offered for the retrieved payload.
  bool supports(RecordPayload payload) => switch (this) {
    workAssociation => payload is WorkRecord,
    sagaMembership => payload is SagaRecord,
    canonBinding => payload is WorkVersionRecord,
    sceneCorrection => payload is SceneRecord,
    itemPowerCorrection => payload is ItemPowerRecord,
    communicationCorrection => payload is CommunicationRecord,
    attitudeCorrection => payload is EpistemicAttitudeRecord,
    propertyRevision => payload is PropertyRecord,
    relationRevision => payload is RelationRecord,
    unitRevision => payload is UnitRecord,
    calendarRevision => payload is CalendarRecord,
    packUpgrade => payload is DomainPackRecord,
    actionRevision => payload is ActionDefinitionRecord,
    ruleRevision => payload is RuleRecord,
    assertionRetraction || assertionCorrection => payload is AssertionRecord,
    eventWithdrawal => isWithdrawableEvent(payload),
    recordRemoval => true,
    secretRevision => payload is SecretRecord,
    appearanceRevision => payload is AppearanceRecord,
    eventRevision => payload is EventRecord,
    assertionEnd =>
      payload is AssertionRecord &&
          payload.validity is CalendarIntervalValidity,
    valueRevision => payload is ValueDefinitionRecord,
    typeRevision => payload is EntityTypeRecord,
    interpretationCorrection =>
      payload is EpistemicAttitudeRecord &&
          payload.attitude == EpistemicAttitudeKind.knows &&
          payload.acquisition?.basis is CommunicationKnowledge,
    sourceExcerpt => payload is SourceVersionRecord,
    entityName ||
    entityClassification ||
    attribute ||
    relationship => payload is EntityRecord,
  };
}
