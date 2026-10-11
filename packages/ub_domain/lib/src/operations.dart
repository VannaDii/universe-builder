part of 'records.dart';

/// Coarse request classification. Actual effects and current grants still need
/// service admission; this label never grants permission.
enum OperationAuthority { ordinary, historical, definition, privileged }

enum TimeChangeKind {
  elapsed('elapsed'),
  timeTravel('time_travel');

  const TimeChangeKind(this.wireName);
  final String wireName;
  static TimeChangeKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown time change kind'),
  );
}

/// Operation records are untagged DTOs, unlike stored Payload variants.
CanonicalObject _operationRecordInput(CanonicalValue value, RecordKind kind) {
  final f = Fields(value);
  if (f.values.containsKey('record_kind')) {
    throw const FormatException('Unexpected nested record discriminator');
  }
  return _recordWire(kind, f.values.entries);
}

CanonicalObject _operationRecordOutput(RecordPayload record) => CanonicalObject(
  record.toWire().fields.where((entry) => entry.key != 'record_kind'),
);

final class AttributeEvidence {
  AttributeEvidence({
    required this.attributeMode,
    required this.polarity,
    required this.scope,
    required this.validity,
    required this.persistence,
    required this.precision,
    Iterable<DomainValue> alternatives = const [],
    required this.basis,
  }) : alternatives = List.unmodifiable(alternatives);
  final AttributeMode attributeMode;
  final Polarity polarity;
  final Scope scope;
  final Validity validity;
  final PersistenceSemantics persistence;
  final Precision precision;
  final List<DomainValue> alternatives;
  final EvidenceBasis basis;
  factory AttributeEvidence.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'attributeMode',
        'polarity',
        'scope',
        'validity',
        'persistence',
        'precision',
        'alternatives',
        'basis',
      });
    return AttributeEvidence(
      attributeMode: AttributeMode.fromWire(f.require('attributeMode')),
      polarity: Polarity.fromWire(f.require('polarity')),
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
      persistence: PersistenceSemantics.fromWire(f.require('persistence')),
      precision: Precision.fromWire(f.require('precision')),
      alternatives: _array(f, 'alternatives').map(DomainValue.fromWire),
      basis: EvidenceBasis.fromWire(f.require('basis')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('attributeMode', CanonicalString(attributeMode.wireName)),
    MapEntry('polarity', polarity.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('persistence', persistence.toWire()),
    MapEntry('precision', precision.toWire()),
    if (alternatives.isNotEmpty)
      MapEntry(
        'alternatives',
        CanonicalArray(alternatives.map((v) => v.toWire())),
      ),
    MapEntry('basis', basis.toWire()),
  ]);
}

/// Immutable version DTO. Decoding preserves declared digests without granting
/// adoption authority or silently recomputing a supplied historical digest.
final class RecordVersion {
  const RecordVersion({
    required this.recordVersionId,
    required this.identity,
    required this.payload,
    required this.payloadDigest,
  });
  final RecordVersionId recordVersionId;
  final RecordIdentity identity;
  final RecordPayload payload;
  final String payloadDigest;
  factory RecordVersion.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'record_version_id', 'identity', 'payload', 'payload_digest'});
    return RecordVersion(
      recordVersionId: RecordVersionId.parse(f.string('record_version_id')),
      identity: RecordIdentity.fromWire(f.require('identity')),
      payload: RecordPayload.fromWire(f.require('payload')),
      payloadDigest: f.string('payload_digest'),
    );
  }
  factory RecordVersion.build({
    required RecordVersionId recordVersionId,
    required RecordIdentity identity,
    required RecordPayload payload,
  }) {
    if (identity.recordKind != payload.recordKind) {
      throw const FormatException('Wrong record kind');
    }
    return RecordVersion(
      recordVersionId: recordVersionId,
      identity: identity,
      payload: payload,
      payloadDigest: payload.digest,
    );
  }
  bool get verifiesDigest =>
      payloadDigest == _versionPayloadDigest(identity.recordKind, payload);
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_version_id', CanonicalString(recordVersionId.value)),
    MapEntry('identity', identity.toCanonical()),
    MapEntry('payload', payload.toWire()),
    MapEntry('payload_digest', CanonicalString(payloadDigest)),
  ]);
}

String _versionPayloadDigest(RecordKind kind, RecordPayload payload) =>
    payloadDigest(kind.wireName, payload.toCanonical());

enum DomainOperationKind {
  createAppearance('create_appearance', OperationAuthority.ordinary),
  reviseAppearance('revise_appearance', OperationAuthority.ordinary),
  addImageAsset('add_image_asset', OperationAuthority.ordinary),
  setStoryTime('set_story_time', OperationAuthority.historical),
  createEntity('create_entity', OperationAuthority.ordinary),
  addName('add_name', OperationAuthority.ordinary),
  addTypeMembership('add_type_membership', OperationAuthority.ordinary),
  createWorld('create_world', OperationAuthority.ordinary),
  renameWorldSelector('rename_world_selector', OperationAuthority.ordinary),
  addWorldAlias('add_world_alias', OperationAuthority.ordinary),
  createWork('create_work', OperationAuthority.ordinary),
  createSaga('create_saga', OperationAuthority.ordinary),
  setWorkBinding('set_work_binding', OperationAuthority.ordinary),
  associateWorkWorld('associate_work_world', OperationAuthority.ordinary),
  setSagaMembership('set_saga_membership', OperationAuthority.ordinary),
  assertProposition('assert_proposition', OperationAuthority.ordinary),
  recordRelation('record_relation', OperationAuthority.ordinary),
  endAssertionAt('end_assertion_at', OperationAuthority.historical),
  supersedeAssertion('supersede_assertion', OperationAuthority.historical),
  retractAssertion('retract_assertion', OperationAuthority.historical),
  defineProposition('define_proposition', OperationAuthority.ordinary),
  defineItemPower('define_item_power', OperationAuthority.definition),
  defineAction('define_action', OperationAuthority.definition),
  recordEvent('record_event', OperationAuthority.ordinary),
  reviseEvent('revise_event', OperationAuthority.ordinary),
  addBelief('add_belief', OperationAuthority.ordinary),
  recordObservation('record_observation', OperationAuthority.ordinary),
  recordCommunication('record_communication', OperationAuthority.ordinary),
  recordMemory('record_memory', OperationAuthority.ordinary),
  recordPlan('record_plan', OperationAuthority.ordinary),
  recordCommitment('record_commitment', OperationAuthority.ordinary),
  defineType('define_type', OperationAuthority.definition),
  defineProperty('define_property', OperationAuthority.definition),
  defineRelation('define_relation', OperationAuthority.definition),
  defineUnit('define_unit', OperationAuthority.definition),
  defineCalendar('define_calendar', OperationAuthority.definition),
  defineValue('define_value', OperationAuthority.definition),
  defineRule('define_rule', OperationAuthority.definition),
  setCompleteness('set_completeness', OperationAuthority.definition),
  setCreativeBoundary('set_creative_boundary', OperationAuthority.definition),
  addException('add_exception', OperationAuthority.definition),
  addSourceAnchor('add_source_anchor', OperationAuthority.ordinary),
  recordNarrativeReference(
    'record_narrative_reference',
    OperationAuthority.ordinary,
  ),
  recordIssueDecision('record_issue_decision', OperationAuthority.ordinary),
  adoptRecordVersion('adopt_record_version', OperationAuthority.privileged),
  tombstoneRecord('tombstone_record', OperationAuthority.privileged),
  mergeEntities('merge_entities', OperationAuthority.privileged),
  installPack('install_pack', OperationAuthority.definition),
  withdrawEvent('withdraw_event', OperationAuthority.historical),
  reviseCommunication('revise_communication', OperationAuthority.historical),
  reviseInterpretation('revise_interpretation', OperationAuthority.historical),
  reviseScene('revise_scene', OperationAuthority.historical),
  reviseAttitude('revise_attitude', OperationAuthority.historical),
  reviseItemPower('revise_item_power', OperationAuthority.definition),
  reviseDefinition('revise_definition', OperationAuthority.definition),
  upgradePack('upgrade_pack', OperationAuthority.definition),
  introduceDefinition('introduce_definition', OperationAuthority.definition),
  introduceInstance('introduce_instance', OperationAuthority.ordinary),
  addNamedAttribute('add_named_attribute', OperationAuthority.definition),
  initializeInstance('initialize_instance', OperationAuthority.ordinary),
  refineClassification('refine_classification', OperationAuthority.ordinary);

  const DomainOperationKind(this.wireName, this.authority);
  final String wireName;
  final OperationAuthority authority;
}

sealed class DomainOperation {
  const DomainOperation();
  DomainOperationKind get kind;
  OperationAuthority get authority => kind.authority;
  CanonicalObject toWire();
  static DomainOperation fromWire(CanonicalValue value) => switch (Fields(value)
      .string('kind')) {
    'create_appearance' => CreateAppearanceOperation.fromWire(value),
    'revise_appearance' => ReviseAppearanceOperation.fromWire(value),
    'add_image_asset' => AddImageAssetOperation.fromWire(value),
    'set_story_time' => SetStoryTimeOperation.fromWire(value),
    'create_entity' => CreateEntityOperation.fromWire(value),
    'add_name' => AddNameOperation.fromWire(value),
    'add_type_membership' => AddTypeMembershipOperation.fromWire(value),
    'create_world' => CreateWorldOperation.fromWire(value),
    'rename_world_selector' => RenameWorldSelectorOperation.fromWire(value),
    'add_world_alias' => AddWorldAliasOperation.fromWire(value),
    'create_work' => CreateWorkOperation.fromWire(value),
    'create_saga' => CreateSagaOperation.fromWire(value),
    'set_work_binding' => SetWorkBindingOperation.fromWire(value),
    'associate_work_world' => AssociateWorkWorldOperation.fromWire(value),
    'set_saga_membership' => SetSagaMembershipOperation.fromWire(value),
    'assert_proposition' => AssertPropositionOperation.fromWire(value),
    'record_relation' => RecordRelationOperation.fromWire(value),
    'end_assertion_at' => EndAssertionAtOperation.fromWire(value),
    'supersede_assertion' => SupersedeAssertionOperation.fromWire(value),
    'retract_assertion' => RetractAssertionOperation.fromWire(value),
    'define_proposition' => DefinePropositionOperation.fromWire(value),
    'define_item_power' => DefineItemPowerOperation.fromWire(value),
    'define_action' => DefineActionOperation.fromWire(value),
    'record_event' => RecordEventOperation.fromWire(value),
    'revise_event' => ReviseEventOperation.fromWire(value),
    'add_belief' => AddBeliefOperation.fromWire(value),
    'record_observation' => RecordObservationOperation.fromWire(value),
    'record_communication' => RecordCommunicationOperation.fromWire(value),
    'record_memory' => RecordMemoryOperation.fromWire(value),
    'record_plan' => RecordPlanOperation.fromWire(value),
    'record_commitment' => RecordCommitmentOperation.fromWire(value),
    'define_type' => DefineTypeOperation.fromWire(value),
    'define_property' => DefinePropertyOperation.fromWire(value),
    'define_relation' => DefineRelationOperation.fromWire(value),
    'define_unit' => DefineUnitOperation.fromWire(value),
    'define_calendar' => DefineCalendarOperation.fromWire(value),
    'define_value' => DefineValueOperation.fromWire(value),
    'define_rule' => DefineRuleOperation.fromWire(value),
    'set_completeness' => SetCompletenessOperation.fromWire(value),
    'set_creative_boundary' => SetCreativeBoundaryOperation.fromWire(value),
    'add_exception' => AddExceptionOperation.fromWire(value),
    'add_source_anchor' => AddSourceAnchorOperation.fromWire(value),
    'record_narrative_reference' => RecordNarrativeReferenceOperation.fromWire(
      value,
    ),
    'record_issue_decision' => RecordIssueDecisionOperation.fromWire(value),
    'adopt_record_version' => AdoptRecordVersionOperation.fromWire(value),
    'tombstone_record' => TombstoneRecordOperation.fromWire(value),
    'merge_entities' => MergeEntitiesOperation.fromWire(value),
    'install_pack' => InstallPackOperation.fromWire(value),
    'withdraw_event' => WithdrawEventOperation.fromWire(value),
    'revise_communication' => ReviseCommunicationOperation.fromWire(value),
    'revise_interpretation' => ReviseInterpretationOperation.fromWire(value),
    'revise_scene' => ReviseSceneOperation.fromWire(value),
    'revise_attitude' => ReviseAttitudeOperation.fromWire(value),
    'revise_item_power' => ReviseItemPowerOperation.fromWire(value),
    'revise_definition' => ReviseDefinitionOperation.fromWire(value),
    'upgrade_pack' => UpgradePackOperation.fromWire(value),
    'introduce_definition' => IntroduceDefinitionOperation.fromWire(value),
    'introduce_instance' => IntroduceInstanceOperation.fromWire(value),
    'add_named_attribute' => AddNamedAttributeOperation.fromWire(value),
    'initialize_instance' => InitializeInstanceOperation.fromWire(value),
    'refine_classification' => RefineClassificationOperation.fromWire(value),
    _ => throw const FormatException('Unknown domain operation'),
  };
}

final class CreateAppearanceOperation extends DomainOperation {
  const CreateAppearanceOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final AppearanceRecord record;
  factory CreateAppearanceOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'create_appearance') {
      throw const FormatException('Wrong operation kind');
    }
    return CreateAppearanceOperation(
      clientRef: f.string('client_ref'),
      record: AppearanceRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.appearance),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.createAppearance;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class ReviseAppearanceOperation extends DomainOperation {
  const ReviseAppearanceOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final AppearanceRecord replacement;
  factory ReviseAppearanceOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'replacement'});
    if (f.string('kind') != 'revise_appearance') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseAppearanceOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: AppearanceRecord.fromWire(
        _operationRecordInput(f.require('replacement'), RecordKind.appearance),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseAppearance;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
  ]);
}

final class AddImageAssetOperation extends DomainOperation {
  const AddImageAssetOperation({required this.clientRef, required this.record});
  final String clientRef;
  final ImageAssetRecord record;
  factory AddImageAssetOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'add_image_asset') {
      throw const FormatException('Wrong operation kind');
    }
    return AddImageAssetOperation(
      clientRef: f.string('client_ref'),
      record: ImageAssetRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.imageAsset),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addImageAsset;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class SetStoryTimeOperation extends DomainOperation {
  const SetStoryTimeOperation({
    required this.record,
    required this.expectedVersion,
    required this.value,
    required this.mode,
    required this.reason,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final String value;
  final TimeChangeKind mode;
  final String reason;
  factory SetStoryTimeOperation.fromWire(CanonicalValue value) {
    final f = Fields(
      value,
    )..allow({'kind', 'record', 'expected_version', 'value', 'mode', 'reason'});
    if (f.string('kind') != 'set_story_time') {
      throw const FormatException('Wrong operation kind');
    }
    return SetStoryTimeOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      value: f.string('value'),
      mode: TimeChangeKind.fromName(_string(f.require('mode'))),
      reason: f.string('reason'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.setStoryTime;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('value', CanonicalString(value)),
    MapEntry('mode', CanonicalString(mode.wireName)),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class CreateEntityOperation extends DomainOperation {
  const CreateEntityOperation({required this.clientRef, required this.record});
  final String clientRef;
  final EntityRecord record;
  factory CreateEntityOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'create_entity') {
      throw const FormatException('Wrong operation kind');
    }
    return CreateEntityOperation(
      clientRef: f.string('client_ref'),
      record: EntityRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.entity),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.createEntity;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class AddNameOperation extends DomainOperation {
  const AddNameOperation({
    required this.record,
    required this.expectedVersion,
    required this.name,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final ContextualName name;
  factory AddNameOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'name'});
    if (f.string('kind') != 'add_name') {
      throw const FormatException('Wrong operation kind');
    }
    return AddNameOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      name: ContextualName.fromWire(f.require('name')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addName;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('name', name.toWire()),
  ]);
}

final class AddTypeMembershipOperation extends DomainOperation {
  const AddTypeMembershipOperation({
    required this.record,
    required this.expectedVersion,
    required this.entityType,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final RecordId entityType;
  factory AddTypeMembershipOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'entity_type'});
    if (f.string('kind') != 'add_type_membership') {
      throw const FormatException('Wrong operation kind');
    }
    return AddTypeMembershipOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      entityType: RecordId.parse(_string(f.require('entity_type'))),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addTypeMembership;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('entity_type', CanonicalString(entityType.value)),
  ]);
}

final class CreateWorldOperation extends DomainOperation {
  const CreateWorldOperation({required this.clientRef, required this.record});
  final String clientRef;
  final WorldRecord record;
  factory CreateWorldOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'create_world') {
      throw const FormatException('Wrong operation kind');
    }
    return CreateWorldOperation(
      clientRef: f.string('client_ref'),
      record: WorldRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.world),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.createWorld;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RenameWorldSelectorOperation extends DomainOperation {
  const RenameWorldSelectorOperation({
    required this.record,
    required this.expectedVersion,
    required this.newSelector,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final String newSelector;
  factory RenameWorldSelectorOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'new_selector'});
    if (f.string('kind') != 'rename_world_selector') {
      throw const FormatException('Wrong operation kind');
    }
    return RenameWorldSelectorOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      newSelector: f.string('new_selector'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.renameWorldSelector;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('new_selector', CanonicalString(newSelector)),
  ]);
}

final class AddWorldAliasOperation extends DomainOperation {
  const AddWorldAliasOperation({
    required this.record,
    required this.expectedVersion,
    required this.alias,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final String alias;
  factory AddWorldAliasOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'alias'});
    if (f.string('kind') != 'add_world_alias') {
      throw const FormatException('Wrong operation kind');
    }
    return AddWorldAliasOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      alias: f.string('alias'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addWorldAlias;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('alias', CanonicalString(alias)),
  ]);
}

final class CreateWorkOperation extends DomainOperation {
  const CreateWorkOperation({required this.clientRef, required this.record});
  final String clientRef;
  final WorkRecord record;
  factory CreateWorkOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'create_work') {
      throw const FormatException('Wrong operation kind');
    }
    return CreateWorkOperation(
      clientRef: f.string('client_ref'),
      record: WorkRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.work),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.createWork;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class CreateSagaOperation extends DomainOperation {
  const CreateSagaOperation({required this.clientRef, required this.record});
  final String clientRef;
  final SagaRecord record;
  factory CreateSagaOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'create_saga') {
      throw const FormatException('Wrong operation kind');
    }
    return CreateSagaOperation(
      clientRef: f.string('client_ref'),
      record: SagaRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.saga),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.createSaga;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class SetWorkBindingOperation extends DomainOperation {
  const SetWorkBindingOperation({
    required this.record,
    required this.expectedVersion,
    required this.binding,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final WorkBinding binding;
  factory SetWorkBindingOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'binding'});
    if (f.string('kind') != 'set_work_binding') {
      throw const FormatException('Wrong operation kind');
    }
    return SetWorkBindingOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      binding: WorkBinding.fromWire(f.require('binding')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.setWorkBinding;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('binding', binding.toWire()),
  ]);
}

final class AssociateWorkWorldOperation extends DomainOperation {
  const AssociateWorkWorldOperation({
    required this.record,
    required this.expectedVersion,
    required this.association,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final WorldAssociation association;
  factory AssociateWorkWorldOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'association'});
    if (f.string('kind') != 'associate_work_world') {
      throw const FormatException('Wrong operation kind');
    }
    return AssociateWorkWorldOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      association: WorldAssociation.fromWire(f.require('association')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.associateWorkWorld;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('association', association.toWire()),
  ]);
}

final class SetSagaMembershipOperation extends DomainOperation {
  const SetSagaMembershipOperation({
    required this.record,
    required this.expectedVersion,
    required this.membership,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final SagaMembership membership;
  factory SetSagaMembershipOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'membership'});
    if (f.string('kind') != 'set_saga_membership') {
      throw const FormatException('Wrong operation kind');
    }
    return SetSagaMembershipOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      membership: SagaMembership.fromWire(f.require('membership')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.setSagaMembership;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('membership', membership.toWire()),
  ]);
}

final class AssertPropositionOperation extends DomainOperation {
  const AssertPropositionOperation({
    required this.clientRef,
    required this.proposition,
    required this.assertion,
  });
  final String clientRef;
  final PropositionRecord proposition;
  final AssertionRecord assertion;
  factory AssertPropositionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'client_ref', 'proposition', 'assertion'});
    if (f.string('kind') != 'assert_proposition') {
      throw const FormatException('Wrong operation kind');
    }
    return AssertPropositionOperation(
      clientRef: f.string('client_ref'),
      proposition: PropositionRecord.fromWire(
        _operationRecordInput(f.require('proposition'), RecordKind.proposition),
      ),
      assertion: AssertionRecord.fromWire(
        _operationRecordInput(f.require('assertion'), RecordKind.assertion),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.assertProposition;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('proposition', _operationRecordOutput(proposition)),
    MapEntry('assertion', _operationRecordOutput(assertion)),
  ]);
}

final class RecordRelationOperation extends DomainOperation {
  const RecordRelationOperation({
    required this.clientRef,
    required this.proposition,
    required this.assertion,
  });
  final String clientRef;
  final PropositionRecord proposition;
  final AssertionRecord assertion;
  factory RecordRelationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'client_ref', 'proposition', 'assertion'});
    if (f.string('kind') != 'record_relation') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordRelationOperation(
      clientRef: f.string('client_ref'),
      proposition: PropositionRecord.fromWire(
        _operationRecordInput(f.require('proposition'), RecordKind.proposition),
      ),
      assertion: AssertionRecord.fromWire(
        _operationRecordInput(f.require('assertion'), RecordKind.assertion),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordRelation;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('proposition', _operationRecordOutput(proposition)),
    MapEntry('assertion', _operationRecordOutput(assertion)),
  ]);
}

final class EndAssertionAtOperation extends DomainOperation {
  const EndAssertionAtOperation({
    required this.record,
    required this.expectedVersion,
    required this.at,
    required this.basis,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final TemporalExpression at;
  final EvidenceBasis basis;
  factory EndAssertionAtOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'at', 'basis'});
    if (f.string('kind') != 'end_assertion_at') {
      throw const FormatException('Wrong operation kind');
    }
    return EndAssertionAtOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      at: TemporalExpression.fromWire(f.require('at')),
      basis: EvidenceBasis.fromWire(f.require('basis')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.endAssertionAt;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('at', at.encode(canonical: false)),
    MapEntry('basis', basis.toWire()),
  ]);
}

final class SupersedeAssertionOperation extends DomainOperation {
  const SupersedeAssertionOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final AssertionRecord replacement;
  final String rationale;
  factory SupersedeAssertionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'record',
        'expected_version',
        'replacement',
        'rationale',
      });
    if (f.string('kind') != 'supersede_assertion') {
      throw const FormatException('Wrong operation kind');
    }
    return SupersedeAssertionOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: AssertionRecord.fromWire(
        _operationRecordInput(f.require('replacement'), RecordKind.assertion),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.supersedeAssertion;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class RetractAssertionOperation extends DomainOperation {
  const RetractAssertionOperation({
    required this.record,
    required this.expectedVersion,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final String rationale;
  factory RetractAssertionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'rationale'});
    if (f.string('kind') != 'retract_assertion') {
      throw const FormatException('Wrong operation kind');
    }
    return RetractAssertionOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.retractAssertion;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class DefinePropositionOperation extends DomainOperation {
  const DefinePropositionOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final PropositionRecord record;
  factory DefinePropositionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_proposition') {
      throw const FormatException('Wrong operation kind');
    }
    return DefinePropositionOperation(
      clientRef: f.string('client_ref'),
      record: PropositionRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.proposition),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineProposition;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineItemPowerOperation extends DomainOperation {
  const DefineItemPowerOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final ItemPowerRecord record;
  factory DefineItemPowerOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_item_power') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineItemPowerOperation(
      clientRef: f.string('client_ref'),
      record: ItemPowerRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.itemPower),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineItemPower;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineActionOperation extends DomainOperation {
  const DefineActionOperation({required this.clientRef, required this.record});
  final String clientRef;
  final ActionDefinitionRecord record;
  factory DefineActionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_action') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineActionOperation(
      clientRef: f.string('client_ref'),
      record: ActionDefinitionRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.actionDefinition),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineAction;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordEventOperation extends DomainOperation {
  const RecordEventOperation({required this.clientRef, required this.record});
  final String clientRef;
  final EventRecord record;
  factory RecordEventOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_event') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordEventOperation(
      clientRef: f.string('client_ref'),
      record: EventRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.event),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordEvent;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class ReviseEventOperation extends DomainOperation {
  const ReviseEventOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final EventRecord replacement;
  factory ReviseEventOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'replacement'});
    if (f.string('kind') != 'revise_event') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseEventOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: EventRecord.fromWire(
        _operationRecordInput(f.require('replacement'), RecordKind.event),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseEvent;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
  ]);
}

final class AddBeliefOperation extends DomainOperation {
  const AddBeliefOperation({required this.clientRef, required this.record});
  final String clientRef;
  final EpistemicAttitudeRecord record;
  factory AddBeliefOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'add_belief') {
      throw const FormatException('Wrong operation kind');
    }
    return AddBeliefOperation(
      clientRef: f.string('client_ref'),
      record: EpistemicAttitudeRecord.fromWire(
        _operationRecordInput(
          f.require('record'),
          RecordKind.epistemicAttitude,
        ),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addBelief;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordObservationOperation extends DomainOperation {
  const RecordObservationOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final ObservationRecord record;
  factory RecordObservationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_observation') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordObservationOperation(
      clientRef: f.string('client_ref'),
      record: ObservationRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.observation),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordObservation;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordCommunicationOperation extends DomainOperation {
  const RecordCommunicationOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final CommunicationRecord record;
  factory RecordCommunicationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_communication') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordCommunicationOperation(
      clientRef: f.string('client_ref'),
      record: CommunicationRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.communication),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordCommunication;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordMemoryOperation extends DomainOperation {
  const RecordMemoryOperation({required this.clientRef, required this.record});
  final String clientRef;
  final MemoryRecord record;
  factory RecordMemoryOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_memory') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordMemoryOperation(
      clientRef: f.string('client_ref'),
      record: MemoryRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.memory),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordMemory;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordPlanOperation extends DomainOperation {
  const RecordPlanOperation({required this.clientRef, required this.record});
  final String clientRef;
  final GoalRecord record;
  factory RecordPlanOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_plan') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordPlanOperation(
      clientRef: f.string('client_ref'),
      record: GoalRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.goal),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordPlan;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordCommitmentOperation extends DomainOperation {
  const RecordCommitmentOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final CommitmentRecord record;
  factory RecordCommitmentOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_commitment') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordCommitmentOperation(
      clientRef: f.string('client_ref'),
      record: CommitmentRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.commitment),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordCommitment;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineTypeOperation extends DomainOperation {
  const DefineTypeOperation({required this.clientRef, required this.record});
  final String clientRef;
  final EntityTypeRecord record;
  factory DefineTypeOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_type') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineTypeOperation(
      clientRef: f.string('client_ref'),
      record: EntityTypeRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.entityType),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineType;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefinePropertyOperation extends DomainOperation {
  const DefinePropertyOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final PropertyRecord record;
  factory DefinePropertyOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_property') {
      throw const FormatException('Wrong operation kind');
    }
    return DefinePropertyOperation(
      clientRef: f.string('client_ref'),
      record: PropertyRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.property),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineProperty;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineRelationOperation extends DomainOperation {
  const DefineRelationOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final RelationRecord record;
  factory DefineRelationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_relation') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineRelationOperation(
      clientRef: f.string('client_ref'),
      record: RelationRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.relation),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineRelation;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineUnitOperation extends DomainOperation {
  const DefineUnitOperation({required this.clientRef, required this.record});
  final String clientRef;
  final UnitRecord record;
  factory DefineUnitOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_unit') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineUnitOperation(
      clientRef: f.string('client_ref'),
      record: UnitRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.unit),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineUnit;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineCalendarOperation extends DomainOperation {
  const DefineCalendarOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final CalendarRecord record;
  factory DefineCalendarOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_calendar') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineCalendarOperation(
      clientRef: f.string('client_ref'),
      record: CalendarRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.calendar),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineCalendar;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineValueOperation extends DomainOperation {
  const DefineValueOperation({required this.clientRef, required this.record});
  final String clientRef;
  final ValueDefinitionRecord record;
  factory DefineValueOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_value') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineValueOperation(
      clientRef: f.string('client_ref'),
      record: ValueDefinitionRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.valueDefinition),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineValue;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class DefineRuleOperation extends DomainOperation {
  const DefineRuleOperation({required this.clientRef, required this.record});
  final String clientRef;
  final RuleRecord record;
  factory DefineRuleOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'define_rule') {
      throw const FormatException('Wrong operation kind');
    }
    return DefineRuleOperation(
      clientRef: f.string('client_ref'),
      record: RuleRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.rule),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.defineRule;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class SetCompletenessOperation extends DomainOperation {
  const SetCompletenessOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final CompletenessRecord record;
  factory SetCompletenessOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'set_completeness') {
      throw const FormatException('Wrong operation kind');
    }
    return SetCompletenessOperation(
      clientRef: f.string('client_ref'),
      record: CompletenessRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.completeness),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.setCompleteness;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class SetCreativeBoundaryOperation extends DomainOperation {
  const SetCreativeBoundaryOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final BoundaryRecord record;
  factory SetCreativeBoundaryOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'set_creative_boundary') {
      throw const FormatException('Wrong operation kind');
    }
    return SetCreativeBoundaryOperation(
      clientRef: f.string('client_ref'),
      record: BoundaryRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.boundary),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.setCreativeBoundary;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class AddExceptionOperation extends DomainOperation {
  const AddExceptionOperation({required this.clientRef, required this.record});
  final String clientRef;
  final ExceptionRecord record;
  factory AddExceptionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'add_exception') {
      throw const FormatException('Wrong operation kind');
    }
    return AddExceptionOperation(
      clientRef: f.string('client_ref'),
      record: ExceptionRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.exception),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addException;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class AddSourceAnchorOperation extends DomainOperation {
  const AddSourceAnchorOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final AnchorRecord record;
  factory AddSourceAnchorOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'add_source_anchor') {
      throw const FormatException('Wrong operation kind');
    }
    return AddSourceAnchorOperation(
      clientRef: f.string('client_ref'),
      record: AnchorRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.anchor),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addSourceAnchor;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class RecordNarrativeReferenceOperation extends DomainOperation {
  const RecordNarrativeReferenceOperation({
    required this.clientRef,
    required this.record,
    required this.payload,
  });
  final String clientRef;
  final RecordKind record;
  final RecordPayload payload;
  factory RecordNarrativeReferenceOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record', 'payload'});
    if (f.string('kind') != 'record_narrative_reference') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordNarrativeReferenceOperation(
      clientRef: f.string('client_ref'),
      record: RecordKind.parse(_string(f.require('record'))),
      payload: RecordPayload.fromWire(f.require('payload')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordNarrativeReference;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', CanonicalString(record.wireName)),
    MapEntry('payload', payload.toWire()),
  ]);
}

final class RecordIssueDecisionOperation extends DomainOperation {
  const RecordIssueDecisionOperation({
    required this.clientRef,
    required this.record,
  });
  final String clientRef;
  final IssueDecisionRecord record;
  factory RecordIssueDecisionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'record_issue_decision') {
      throw const FormatException('Wrong operation kind');
    }
    return RecordIssueDecisionOperation(
      clientRef: f.string('client_ref'),
      record: IssueDecisionRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.issueDecision),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.recordIssueDecision;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class AdoptRecordVersionOperation extends DomainOperation {
  const AdoptRecordVersionOperation({
    required this.source,
    this.expectedVersion,
  });
  final RecordVersion source;
  final RecordVersionId? expectedVersion;
  factory AdoptRecordVersionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'source', 'expected_version'});
    if (f.string('kind') != 'adopt_record_version') {
      throw const FormatException('Wrong operation kind');
    }
    return AdoptRecordVersionOperation(
      source: RecordVersion.fromWire(f.require('source')),
      expectedVersion: _optionalObject(
        f,
        'expected_version',
        (value) => RecordVersionId.parse(_string(value)),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.adoptRecordVersion;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('source', source.toWire()),
    MapEntry(
      'expected_version',
      expectedVersion == null
          ? const CanonicalNull()
          : CanonicalString(expectedVersion!.value),
    ),
  ]);
}

final class TombstoneRecordOperation extends DomainOperation {
  const TombstoneRecordOperation({
    required this.record,
    required this.expectedVersion,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final String rationale;
  factory TombstoneRecordOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'rationale'});
    if (f.string('kind') != 'tombstone_record') {
      throw const FormatException('Wrong operation kind');
    }
    return TombstoneRecordOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.tombstoneRecord;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class MergeEntitiesOperation extends DomainOperation {
  const MergeEntitiesOperation({
    required this.source,
    required this.sourceVersion,
    required this.target,
    required this.targetVersion,
    required this.rationale,
  });
  final RecordRef source;
  final RecordVersionId sourceVersion;
  final RecordRef target;
  final RecordVersionId targetVersion;
  final String rationale;
  factory MergeEntitiesOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'source',
        'source_version',
        'target',
        'target_version',
        'rationale',
      });
    if (f.string('kind') != 'merge_entities') {
      throw const FormatException('Wrong operation kind');
    }
    return MergeEntitiesOperation(
      source: RecordRef.fromCanonical(f.require('source')),
      sourceVersion: RecordVersionId.parse(
        _string(f.require('source_version')),
      ),
      target: RecordRef.fromCanonical(f.require('target')),
      targetVersion: RecordVersionId.parse(
        _string(f.require('target_version')),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.mergeEntities;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('source', source.toCanonical()),
    MapEntry('source_version', CanonicalString(sourceVersion.value)),
    MapEntry('target', target.toCanonical()),
    MapEntry('target_version', CanonicalString(targetVersion.value)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class InstallPackOperation extends DomainOperation {
  const InstallPackOperation({required this.clientRef, required this.record});
  final String clientRef;
  final DomainPackRecord record;
  factory InstallPackOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'kind', 'client_ref', 'record'});
    if (f.string('kind') != 'install_pack') {
      throw const FormatException('Wrong operation kind');
    }
    return InstallPackOperation(
      clientRef: f.string('client_ref'),
      record: DomainPackRecord.fromWire(
        _operationRecordInput(f.require('record'), RecordKind.domainPack),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.installPack;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('record', _operationRecordOutput(record)),
  ]);
}

final class WithdrawEventOperation extends DomainOperation {
  const WithdrawEventOperation({
    required this.record,
    required this.expectedVersion,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final String rationale;
  factory WithdrawEventOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'rationale'});
    if (f.string('kind') != 'withdraw_event') {
      throw const FormatException('Wrong operation kind');
    }
    return WithdrawEventOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.withdrawEvent;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class ReviseCommunicationOperation extends DomainOperation {
  const ReviseCommunicationOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final CommunicationRecord replacement;
  final String rationale;
  factory ReviseCommunicationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'record',
        'expected_version',
        'replacement',
        'rationale',
      });
    if (f.string('kind') != 'revise_communication') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseCommunicationOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: CommunicationRecord.fromWire(
        _operationRecordInput(
          f.require('replacement'),
          RecordKind.communication,
        ),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseCommunication;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class ReviseInterpretationOperation extends DomainOperation {
  const ReviseInterpretationOperation({
    required this.record,
    required this.expectedVersion,
    this.interpretation,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final RecordRef? interpretation;
  final String rationale;
  factory ReviseInterpretationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'record',
        'expected_version',
        'interpretation',
        'rationale',
      });
    if (f.string('kind') != 'revise_interpretation') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseInterpretationOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      interpretation: _optionalObject(
        f,
        'interpretation',
        (value) => RecordRef.fromCanonical(value),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseInterpretation;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry(
      'interpretation',
      interpretation == null
          ? const CanonicalNull()
          : interpretation!.toCanonical(),
    ),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class ReviseSceneOperation extends DomainOperation {
  const ReviseSceneOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final SceneRecord replacement;
  final String rationale;
  factory ReviseSceneOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'record',
        'expected_version',
        'replacement',
        'rationale',
      });
    if (f.string('kind') != 'revise_scene') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseSceneOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: SceneRecord.fromWire(
        _operationRecordInput(f.require('replacement'), RecordKind.sceneRef),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseScene;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class ReviseAttitudeOperation extends DomainOperation {
  const ReviseAttitudeOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final EpistemicAttitudeRecord replacement;
  final String rationale;
  factory ReviseAttitudeOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'record',
        'expected_version',
        'replacement',
        'rationale',
      });
    if (f.string('kind') != 'revise_attitude') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseAttitudeOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: EpistemicAttitudeRecord.fromWire(
        _operationRecordInput(
          f.require('replacement'),
          RecordKind.epistemicAttitude,
        ),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseAttitude;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class ReviseItemPowerOperation extends DomainOperation {
  const ReviseItemPowerOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
    required this.rationale,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final ItemPowerRecord replacement;
  final String rationale;
  factory ReviseItemPowerOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'record',
        'expected_version',
        'replacement',
        'rationale',
      });
    if (f.string('kind') != 'revise_item_power') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseItemPowerOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: ItemPowerRecord.fromWire(
        _operationRecordInput(f.require('replacement'), RecordKind.itemPower),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseItemPower;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class ReviseDefinitionOperation extends DomainOperation {
  const ReviseDefinitionOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final RecordPayload replacement;
  factory ReviseDefinitionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'replacement'});
    if (f.string('kind') != 'revise_definition') {
      throw const FormatException('Wrong operation kind');
    }
    return ReviseDefinitionOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: RecordPayload.fromWire(f.require('replacement')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.reviseDefinition;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', replacement.toWire()),
  ]);
}

final class UpgradePackOperation extends DomainOperation {
  const UpgradePackOperation({
    required this.record,
    required this.expectedVersion,
    required this.replacement,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final DomainPackRecord replacement;
  factory UpgradePackOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'replacement'});
    if (f.string('kind') != 'upgrade_pack') {
      throw const FormatException('Wrong operation kind');
    }
    return UpgradePackOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      replacement: DomainPackRecord.fromWire(
        _operationRecordInput(f.require('replacement'), RecordKind.domainPack),
      ),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.upgradePack;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('replacement', _operationRecordOutput(replacement)),
  ]);
}

final class IntroduceDefinitionOperation extends DomainOperation {
  const IntroduceDefinitionOperation({
    required this.clientRef,
    required this.namespace,
    required this.key,
    required this.name,
    this.parent,
    required this.applicability,
    required this.classificationExecutable,
  });
  final String clientRef;
  final String namespace;
  final String key;
  final String name;
  final RecordId? parent;
  final Applicability applicability;
  final bool classificationExecutable;
  factory IntroduceDefinitionOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'client_ref',
        'namespace',
        'key',
        'name',
        'parent',
        'applicability',
        'classification_executable',
      });
    if (f.string('kind') != 'introduce_definition') {
      throw const FormatException('Wrong operation kind');
    }
    return IntroduceDefinitionOperation(
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      name: f.string('name'),
      parent: _optionalObject(
        f,
        'parent',
        (value) => RecordId.parse(_string(value)),
      ),
      applicability: Applicability.fromWire(f.require('applicability')),
      classificationExecutable: f.boolean('classification_executable'),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.introduceDefinition;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('name', CanonicalString(name)),
    MapEntry(
      'parent',
      parent == null ? const CanonicalNull() : CanonicalString(parent!.value),
    ),
    MapEntry('applicability', applicability.toWire()),
    MapEntry(
      'classification_executable',
      CanonicalBool(classificationExecutable),
    ),
  ]);
}

final class IntroduceInstanceOperation extends DomainOperation {
  IntroduceInstanceOperation({
    required this.clientRef,
    required this.name,
    this.classification,
    required Iterable<WorldAssociation> worldAssociations,
  }) : worldAssociations = List.unmodifiable(worldAssociations);
  final String clientRef;
  final ContextualName name;
  final RecordId? classification;
  final List<WorldAssociation> worldAssociations;
  factory IntroduceInstanceOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'client_ref',
        'name',
        'classification',
        'world_associations',
      });
    if (f.string('kind') != 'introduce_instance') {
      throw const FormatException('Wrong operation kind');
    }
    return IntroduceInstanceOperation(
      clientRef: f.string('client_ref'),
      name: ContextualName.fromWire(f.require('name')),
      classification: _optionalObject(
        f,
        'classification',
        (value) => RecordId.parse(_string(value)),
      ),
      worldAssociations: f
          .array('world_associations')
          .map((value) => WorldAssociation.fromWire(value)),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.introduceInstance;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('name', name.toWire()),
    MapEntry(
      'classification',
      classification == null
          ? const CanonicalNull()
          : CanonicalString(classification!.value),
    ),
    MapEntry(
      'world_associations',
      CanonicalArray(worldAssociations.map((value) => value.toWire())),
    ),
  ]);
}

final class AddNamedAttributeOperation extends DomainOperation {
  AddNamedAttributeOperation({
    required this.clientRef,
    required this.subject,
    required this.namespace,
    required this.key,
    required this.valueShape,
    required Iterable<RecordId> subjectTypes,
    required this.multiplicity,
    required this.value,
    required this.evidence,
  }) : subjectTypes = List.unmodifiable(subjectTypes);
  final String clientRef;
  final RecordRef subject;
  final String namespace;
  final String key;
  final ValueShape valueShape;
  final List<RecordId> subjectTypes;
  final Multiplicity multiplicity;
  final DomainValue value;
  final AttributeEvidence evidence;
  factory AddNamedAttributeOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'client_ref',
        'subject',
        'namespace',
        'key',
        'value_shape',
        'subject_types',
        'multiplicity',
        'value',
        'evidence',
      });
    if (f.string('kind') != 'add_named_attribute') {
      throw const FormatException('Wrong operation kind');
    }
    return AddNamedAttributeOperation(
      clientRef: f.string('client_ref'),
      subject: RecordRef.fromCanonical(f.require('subject')),
      namespace: f.string('namespace'),
      key: f.string('key'),
      valueShape: ValueShape.fromWire(f.require('value_shape')),
      subjectTypes: f
          .array('subject_types')
          .map((value) => RecordId.parse(_string(value))),
      multiplicity: Multiplicity.fromName(_string(f.require('multiplicity'))),
      value: DomainValue.fromWire(f.require('value')),
      evidence: AttributeEvidence.fromWire(f.require('evidence')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.addNamedAttribute;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('subject', subject.toCanonical()),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('value_shape', valueShape.toWire()),
    MapEntry(
      'subject_types',
      CanonicalArray(subjectTypes.map((value) => CanonicalString(value.value))),
    ),
    MapEntry('multiplicity', CanonicalString(multiplicity.name)),
    MapEntry('value', value.toWire()),
    MapEntry('evidence', evidence.toWire()),
  ]);
}

final class InitializeInstanceOperation extends DomainOperation {
  const InitializeInstanceOperation({
    required this.clientRef,
    required this.instance,
    required this.start,
    required this.definition,
    required this.scope,
    required this.validity,
  });
  final String clientRef;
  final RecordRef instance;
  final RecordRef start;
  final VersionRef definition;
  final Scope scope;
  final Validity validity;
  factory InitializeInstanceOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'kind',
        'client_ref',
        'instance',
        'start',
        'definition',
        'scope',
        'validity',
      });
    if (f.string('kind') != 'initialize_instance') {
      throw const FormatException('Wrong operation kind');
    }
    return InitializeInstanceOperation(
      clientRef: f.string('client_ref'),
      instance: RecordRef.fromCanonical(f.require('instance')),
      start: RecordRef.fromCanonical(f.require('start')),
      definition: VersionRef.fromCanonical(f.require('definition')),
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.initializeInstance;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('instance', instance.toCanonical()),
    MapEntry('start', start.toCanonical()),
    MapEntry('definition', definition.toCanonical()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
  ]);
}

final class RefineClassificationOperation extends DomainOperation {
  const RefineClassificationOperation({
    required this.record,
    required this.expectedVersion,
    required this.entityType,
  });
  final RecordRef record;
  final RecordVersionId expectedVersion;
  final RecordId entityType;
  factory RefineClassificationOperation.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'kind', 'record', 'expected_version', 'entity_type'});
    if (f.string('kind') != 'refine_classification') {
      throw const FormatException('Wrong operation kind');
    }
    return RefineClassificationOperation(
      record: RecordRef.fromCanonical(f.require('record')),
      expectedVersion: RecordVersionId.parse(
        _string(f.require('expected_version')),
      ),
      entityType: RecordId.parse(_string(f.require('entity_type'))),
    );
  }
  @override
  DomainOperationKind get kind => DomainOperationKind.refineClassification;
  @override
  CanonicalObject toWire() => tagged(kind.wireName, [
    MapEntry('record', record.toCanonical()),
    MapEntry('expected_version', CanonicalString(expectedVersion.value)),
    MapEntry('entity_type', CanonicalString(entityType.value)),
  ]);
}
