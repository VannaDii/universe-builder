part of 'request.dart';

enum StoryContextKind {
  narrator('narrator'),
  dream('dream'),
  account('account'),
  embedded('embedded');

  const StoryContextKind(this.wireName);
  final String wireName;
  static StoryContextKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown StoryContextKind'),
  );
}

enum WritingEditionBinding {
  current('current'),
  unbound('unbound');

  const WritingEditionBinding(this.wireName);
  final String wireName;
  static WritingEditionBinding fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown WritingEditionBinding'),
  );
}

enum PlainPropertyType {
  text('text'),
  boolean('boolean'),
  integer('integer'),
  decimal('decimal'),
  object('object'),
  quantity('quantity');

  const PlainPropertyType(this.wireName);
  final String wireName;
  static PlainPropertyType fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown PlainPropertyType'),
  );
}

enum PlainPersistence {
  unspecified('unspecified'),
  untilChanged('until_changed'),
  explicitInterval('explicit_interval');

  const PlainPersistence(this.wireName);
  final String wireName;
  static PlainPersistence fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown PlainPersistence'),
  );
}

sealed class WritingDisclosure {
  const WritingDisclosure();
  CanonicalObject toWire();
  static WritingDisclosure fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'name',
      'fact_handle',
      'event_handle',
    });
    return switch (f.string('kind')) {
      'object' => WritingObjectDisclosure.fromWire(value),
      'fact' => WritingFactDisclosure.fromWire(value),
      'event' => WritingEventDisclosure.fromWire(value),
      _ => throw const FormatException('Unknown WritingDisclosure'),
    };
  }
}

final class WritingObjectDisclosure extends WritingDisclosure {
  WritingObjectDisclosure({required this.name});
  final String name;
  factory WritingObjectDisclosure.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'kind'});
    if (f.string('kind') != 'object') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingObjectDisclosure(name: wireString(f.require('name')));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('object')),
    MapEntry('name', CanonicalString(name)),
  ]);
}

final class WritingFactDisclosure extends WritingDisclosure {
  WritingFactDisclosure({required this.factHandle});
  final String factHandle;
  factory WritingFactDisclosure.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'fact_handle', 'kind'});
    if (f.string('kind') != 'fact') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingFactDisclosure(
      factHandle: wireString(f.require('fact_handle')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('fact')),
    MapEntry('fact_handle', CanonicalString(factHandle)),
  ]);
}

final class WritingEventDisclosure extends WritingDisclosure {
  WritingEventDisclosure({required this.eventHandle});
  final String eventHandle;
  factory WritingEventDisclosure.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'event_handle', 'kind'});
    if (f.string('kind') != 'event') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingEventDisclosure(
      eventHandle: wireString(f.require('event_handle')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('event')),
    MapEntry('event_handle', CanonicalString(eventHandle)),
  ]);
}

sealed class WritingEffectChange {
  const WritingEffectChange();
  CanonicalObject toWire();
  static WritingEffectChange fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'amount',
      'minimum',
      'maximum',
      'unit',
      'value',
      'negated',
    });
    return switch (f.string('kind')) {
      'delta' => WritingDeltaChange.fromWire(value),
      'set' => WritingSetChange.fromWire(value),
      _ => throw const FormatException('Unknown WritingEffectChange'),
    };
  }
}

final class WritingDeltaChange extends WritingEffectChange {
  WritingDeltaChange({
    required CanonicalNumber amount,
    required CanonicalNumber minimum,
    required CanonicalNumber maximum,
    this.unit,
  }) : amount = _factNumber(amount),
       minimum = _factNumber(minimum),
       maximum = _factNumber(maximum);
  final CanonicalNumber amount;
  final CanonicalNumber minimum;
  final CanonicalNumber maximum;
  final String? unit;
  factory WritingDeltaChange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'amount',
      'minimum',
      'maximum',
      'unit',
      'kind',
    });
    if (f.string('kind') != 'delta') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingDeltaChange(
      amount: _writingNumber(f.require('amount')),
      minimum: _writingNumber(f.require('minimum')),
      maximum: _writingNumber(f.require('maximum')),
      unit: f.optional('unit', (v) => wireString(v)),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('delta')),
    MapEntry('amount', amount),
    MapEntry('minimum', minimum),
    MapEntry('maximum', maximum),
    MapEntry(
      'unit',
      unit == null ? const CanonicalNull() : CanonicalString(unit!),
    ),
  ]);
}

final class WritingSetChange extends WritingEffectChange {
  WritingSetChange({required this.value, this.negated = false});
  final FactValue value;
  final bool negated;
  factory WritingSetChange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'value', 'negated', 'kind'});
    if (f.string('kind') != 'set') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingSetChange(
      value: FactValue.fromWire(f.require('value')),
      negated: f.values.containsKey('negated')
          ? _writingBool(f.require('negated'))
          : false,
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('set')),
    MapEntry('value', value.toWire()),
    MapEntry('negated', CanonicalBool(negated)),
  ]);
}

sealed class WritingEffectLifetime {
  const WritingEffectLifetime();
  CanonicalObject toWire();
  static WritingEffectLifetime fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'count'});
    return switch (f.string('kind')) {
      'until_changed' => WritingUntilChangedEffectLifetime.fromWire(value),
      'ticks' => WritingTicksEffectLifetime.fromWire(value),
      _ => throw const FormatException('Unknown WritingEffectLifetime'),
    };
  }
}

final class WritingUntilChangedEffectLifetime extends WritingEffectLifetime {
  WritingUntilChangedEffectLifetime();
  factory WritingUntilChangedEffectLifetime.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'until_changed') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingUntilChangedEffectLifetime();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('until_changed'))]);
}

final class WritingTicksEffectLifetime extends WritingEffectLifetime {
  WritingTicksEffectLifetime({required CanonicalNumber count})
    : count = _factNumber(count);
  final CanonicalNumber count;
  factory WritingTicksEffectLifetime.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'count', 'kind'});
    if (f.string('kind') != 'ticks') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingTicksEffectLifetime(
      count: _writingNumber(f.require('count')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('ticks')),
    MapEntry('count', count),
  ]);
}

sealed class WritingConstraint {
  const WritingConstraint();
  CanonicalObject toWire();
  static WritingConstraint fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'name',
      'property',
      'scope',
      'object',
    });
    return switch (f.string('kind')) {
      'resource_accounting' => WritingResourceAccountingConstraint.fromWire(
        value,
      ),
      'no_opposing_evidence' => WritingNoOpposingEvidenceConstraint.fromWire(
        value,
      ),
      _ => throw const FormatException('Unknown WritingConstraint'),
    };
  }
}

final class WritingResourceAccountingConstraint extends WritingConstraint {
  WritingResourceAccountingConstraint({
    required this.name,
    required this.property,
    required this.scope,
  });
  final String name;
  final String property;
  final String scope;
  factory WritingResourceAccountingConstraint.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'property', 'scope', 'kind'});
    if (f.string('kind') != 'resource_accounting') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingResourceAccountingConstraint(
      name: wireString(f.require('name')),
      property: wireString(f.require('property')),
      scope: wireString(f.require('scope')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('resource_accounting')),
    MapEntry('name', CanonicalString(name)),
    MapEntry('property', CanonicalString(property)),
    MapEntry('scope', CanonicalString(scope)),
  ]);
}

final class WritingNoOpposingEvidenceConstraint extends WritingConstraint {
  WritingNoOpposingEvidenceConstraint({
    required this.name,
    required this.object,
    required this.property,
    required this.scope,
  });
  final String name;
  final String object;
  final String property;
  final String scope;
  factory WritingNoOpposingEvidenceConstraint.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'object',
      'property',
      'scope',
      'kind',
    });
    if (f.string('kind') != 'no_opposing_evidence') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingNoOpposingEvidenceConstraint(
      name: wireString(f.require('name')),
      object: wireString(f.require('object')),
      property: wireString(f.require('property')),
      scope: wireString(f.require('scope')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('no_opposing_evidence')),
    MapEntry('name', CanonicalString(name)),
    MapEntry('object', CanonicalString(object)),
    MapEntry('property', CanonicalString(property)),
    MapEntry('scope', CanonicalString(scope)),
  ]);
}

sealed class WritingInstanceStart {
  const WritingInstanceStart();
  CanonicalObject toWire();
  static WritingInstanceStart fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'event', 'handle'});
    return switch (f.string('kind')) {
      'occurred' => WritingOccurredInstanceStart.fromWire(value),
      'existing' => WritingExistingInstanceStart.fromWire(value),
      _ => throw const FormatException('Unknown WritingInstanceStart'),
    };
  }
}

final class WritingOccurredInstanceStart extends WritingInstanceStart {
  WritingOccurredInstanceStart({required this.event});
  final WritingEvent event;
  factory WritingOccurredInstanceStart.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'event', 'kind'});
    if (f.string('kind') != 'occurred') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingOccurredInstanceStart(
      event: WritingEvent.fromWire(f.require('event')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('occurred')),
    MapEntry('event', event.toWire()),
  ]);
}

final class WritingExistingInstanceStart extends WritingInstanceStart {
  WritingExistingInstanceStart({required this.handle});
  final String handle;
  factory WritingExistingInstanceStart.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'handle', 'kind'});
    if (f.string('kind') != 'existing') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingExistingInstanceStart(
      handle: wireString(f.require('handle')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('existing')),
    MapEntry('handle', CanonicalString(handle)),
  ]);
}

sealed class WritingParent {
  const WritingParent();
  CanonicalObject toWire();
  static WritingParent fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'name'});
    return switch (f.string('kind')) {
      'root' => WritingRootParent.fromWire(value),
      'definition' => WritingDefinitionParent.fromWire(value),
      _ => throw const FormatException('Unknown WritingParent'),
    };
  }
}

final class WritingRootParent extends WritingParent {
  WritingRootParent();
  factory WritingRootParent.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'root') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingRootParent();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('root'))]);
}

final class WritingDefinitionParent extends WritingParent {
  WritingDefinitionParent({required this.name});
  final String name;
  factory WritingDefinitionParent.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'kind'});
    if (f.string('kind') != 'definition') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingDefinitionParent(name: wireString(f.require('name')));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('definition')),
    MapEntry('name', CanonicalString(name)),
  ]);
}

sealed class WritingRelationGrouping {
  const WritingRelationGrouping();
  CanonicalObject toWire();
  static WritingRelationGrouping fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'role'});
    return switch (f.string('kind')) {
      'subject' => WritingSubjectGrouping.fromWire(value),
      'role' => WritingRoleGrouping.fromWire(value),
      _ => throw const FormatException('Unknown WritingRelationGrouping'),
    };
  }
}

final class WritingSubjectGrouping extends WritingRelationGrouping {
  WritingSubjectGrouping();
  factory WritingSubjectGrouping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'subject') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingSubjectGrouping();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('subject'))]);
}

final class WritingRoleGrouping extends WritingRelationGrouping {
  WritingRoleGrouping({required this.role});
  final String role;
  factory WritingRoleGrouping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'role', 'kind'});
    if (f.string('kind') != 'role') {
      throw const FormatException('Wrong writing variant');
    }
    return WritingRoleGrouping(role: wireString(f.require('role')));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('role')),
    MapEntry('role', CanonicalString(role)),
  ]);
}

final class CheckChangesRequest extends Request {
  CheckChangesRequest({
    required this.universe,
    required this.contextId,
    Iterable<WritingWorld> worlds = const [],
    Iterable<WritingStoryContext> storyContexts = const [],
    Iterable<WritingNarrativeWork> narrativeWorks = const [],
    Iterable<WritingWorkEdition> workEditions = const [],
    Iterable<WritingScene> scenes = const [],
    Iterable<WritingSceneCorrection> sceneCorrections = const [],
    Iterable<ObjectChange> changes = const [],
    Iterable<WritingAlias> aliases = const [],
    Iterable<DefinitionChange> definitions = const [],
    Iterable<WritingProperty> properties = const [],
    Iterable<WritingPropertyCorrection> propertyCorrections = const [],
    Iterable<WritingUnit> units = const [],
    Iterable<WritingAction> actions = const [],
    Iterable<WritingItemPower> itemPowers = const [],
    Iterable<WritingItemPowerCorrection> itemPowerCorrections = const [],
    Iterable<WritingPolicyCorrection> policyCorrections = const [],
    Iterable<WritingAttitudeCorrection> attitudeCorrections = const [],
    Iterable<WritingMessageCorrection> messageCorrections = const [],
    Iterable<WritingInterpretationCorrection> interpretationCorrections =
        const [],
    Iterable<WritingDefinitionCorrection> definitionCorrections = const [],
    Iterable<WritingActionCorrection> actionCorrections = const [],
    Iterable<WritingConstraint> constraints = const [],
    Iterable<WritingExhaustiveSet> exhaustiveSets = const [],
    Iterable<WritingRelationDefinition> relationDefinitions = const [],
    Iterable<WritingRelationLimit> relationLimits = const [],
    Iterable<WritingRelationCorrection> relationCorrections = const [],
    Iterable<WritingRelationLimitCorrection> relationLimitCorrections =
        const [],
    Iterable<WritingRelationship> relationships = const [],
    Iterable<WritingRelationshipCorrection> relationshipCorrections = const [],
    Iterable<WritingRelationshipEnding> relationshipEndings = const [],
    Iterable<WritingKnowledgePolicy> knowledgePolicies = const [],
    Iterable<WritingKnowledgeBoundary> knowledgeBoundaries = const [],
    Iterable<WritingInitialization> initializations = const [],
    Iterable<WritingEventCorrection> eventCorrections = const [],
    Iterable<WritingEventWithdrawal> eventWithdrawals = const [],
    Iterable<WritingEvent> events = const [],
    Iterable<WritingMessage> messages = const [],
    Iterable<WritingAttitude> attitudes = const [],
    Iterable<WritingCorrection> corrections = const [],
    Iterable<WritingFactEnding> factEndings = const [],
    Iterable<WritingFactWithdrawal> factWithdrawals = const [],
    Iterable<String> questions = const [],
  }) : worlds = List.unmodifiable(worlds),
       storyContexts = List.unmodifiable(storyContexts),
       narrativeWorks = List.unmodifiable(narrativeWorks),
       workEditions = List.unmodifiable(workEditions),
       scenes = List.unmodifiable(scenes),
       sceneCorrections = List.unmodifiable(sceneCorrections),
       changes = List.unmodifiable(changes),
       aliases = List.unmodifiable(aliases),
       definitions = List.unmodifiable(definitions),
       properties = List.unmodifiable(properties),
       propertyCorrections = List.unmodifiable(propertyCorrections),
       units = List.unmodifiable(units),
       actions = List.unmodifiable(actions),
       itemPowers = List.unmodifiable(itemPowers),
       itemPowerCorrections = List.unmodifiable(itemPowerCorrections),
       policyCorrections = List.unmodifiable(policyCorrections),
       attitudeCorrections = List.unmodifiable(attitudeCorrections),
       messageCorrections = List.unmodifiable(messageCorrections),
       interpretationCorrections = List.unmodifiable(interpretationCorrections),
       definitionCorrections = List.unmodifiable(definitionCorrections),
       actionCorrections = List.unmodifiable(actionCorrections),
       constraints = List.unmodifiable(constraints),
       exhaustiveSets = List.unmodifiable(exhaustiveSets),
       relationDefinitions = List.unmodifiable(relationDefinitions),
       relationLimits = List.unmodifiable(relationLimits),
       relationCorrections = List.unmodifiable(relationCorrections),
       relationLimitCorrections = List.unmodifiable(relationLimitCorrections),
       relationships = List.unmodifiable(relationships),
       relationshipCorrections = List.unmodifiable(relationshipCorrections),
       relationshipEndings = List.unmodifiable(relationshipEndings),
       knowledgePolicies = List.unmodifiable(knowledgePolicies),
       knowledgeBoundaries = List.unmodifiable(knowledgeBoundaries),
       initializations = List.unmodifiable(initializations),
       eventCorrections = List.unmodifiable(eventCorrections),
       eventWithdrawals = List.unmodifiable(eventWithdrawals),
       events = List.unmodifiable(events),
       messages = List.unmodifiable(messages),
       attitudes = List.unmodifiable(attitudes),
       corrections = List.unmodifiable(corrections),
       factEndings = List.unmodifiable(factEndings),
       factWithdrawals = List.unmodifiable(factWithdrawals),
       questions = List.unmodifiable(questions);
  @override
  final Selector universe;
  final ContextId contextId;
  final List<WritingWorld> worlds;
  final List<WritingStoryContext> storyContexts;
  final List<WritingNarrativeWork> narrativeWorks;
  final List<WritingWorkEdition> workEditions;
  final List<WritingScene> scenes;
  final List<WritingSceneCorrection> sceneCorrections;
  final List<ObjectChange> changes;
  final List<WritingAlias> aliases;
  final List<DefinitionChange> definitions;
  final List<WritingProperty> properties;
  final List<WritingPropertyCorrection> propertyCorrections;
  final List<WritingUnit> units;
  final List<WritingAction> actions;
  final List<WritingItemPower> itemPowers;
  final List<WritingItemPowerCorrection> itemPowerCorrections;
  final List<WritingPolicyCorrection> policyCorrections;
  final List<WritingAttitudeCorrection> attitudeCorrections;
  final List<WritingMessageCorrection> messageCorrections;
  final List<WritingInterpretationCorrection> interpretationCorrections;
  final List<WritingDefinitionCorrection> definitionCorrections;
  final List<WritingActionCorrection> actionCorrections;
  final List<WritingConstraint> constraints;
  final List<WritingExhaustiveSet> exhaustiveSets;
  final List<WritingRelationDefinition> relationDefinitions;
  final List<WritingRelationLimit> relationLimits;
  final List<WritingRelationCorrection> relationCorrections;
  final List<WritingRelationLimitCorrection> relationLimitCorrections;
  final List<WritingRelationship> relationships;
  final List<WritingRelationshipCorrection> relationshipCorrections;
  final List<WritingRelationshipEnding> relationshipEndings;
  final List<WritingKnowledgePolicy> knowledgePolicies;
  final List<WritingKnowledgeBoundary> knowledgeBoundaries;
  final List<WritingInitialization> initializations;
  final List<WritingEventCorrection> eventCorrections;
  final List<WritingEventWithdrawal> eventWithdrawals;
  final List<WritingEvent> events;
  final List<WritingMessage> messages;
  final List<WritingAttitude> attitudes;
  final List<WritingCorrection> corrections;
  final List<WritingFactEnding> factEndings;
  final List<WritingFactWithdrawal> factWithdrawals;
  final List<String> questions;
  factory CheckChangesRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'universe',
      'context_id',
      'worlds',
      'story_contexts',
      'narrative_works',
      'work_editions',
      'scenes',
      'scene_corrections',
      'changes',
      'aliases',
      'definitions',
      'properties',
      'property_corrections',
      'units',
      'actions',
      'item_powers',
      'item_power_corrections',
      'policy_corrections',
      'attitude_corrections',
      'message_corrections',
      'interpretation_corrections',
      'definition_corrections',
      'action_corrections',
      'constraints',
      'exhaustive_sets',
      'relation_definitions',
      'relation_limits',
      'relation_corrections',
      'relation_limit_corrections',
      'relationships',
      'relationship_corrections',
      'relationship_endings',
      'knowledge_policies',
      'knowledge_boundaries',
      'initializations',
      'event_corrections',
      'event_withdrawals',
      'events',
      'messages',
      'attitudes',
      'corrections',
      'fact_endings',
      'fact_withdrawals',
      'questions',
    });
    return CheckChangesRequest(
      universe: Selector.fromWire(f.require('universe')),
      contextId: ContextId.parse(wireString(f.require('context_id'))),
      worlds: f
          .array('worlds', defaultEmpty: true)
          .map((v) => WritingWorld.fromWire(v)),
      storyContexts: f
          .array('story_contexts', defaultEmpty: true)
          .map((v) => WritingStoryContext.fromWire(v)),
      narrativeWorks: f
          .array('narrative_works', defaultEmpty: true)
          .map((v) => WritingNarrativeWork.fromWire(v)),
      workEditions: f
          .array('work_editions', defaultEmpty: true)
          .map((v) => WritingWorkEdition.fromWire(v)),
      scenes: f
          .array('scenes', defaultEmpty: true)
          .map((v) => WritingScene.fromWire(v)),
      sceneCorrections: f
          .array('scene_corrections', defaultEmpty: true)
          .map((v) => WritingSceneCorrection.fromWire(v)),
      changes: f
          .array('changes', defaultEmpty: true)
          .map((v) => ObjectChange.fromWire(v)),
      aliases: f
          .array('aliases', defaultEmpty: true)
          .map((v) => WritingAlias.fromWire(v)),
      definitions: f
          .array('definitions', defaultEmpty: true)
          .map((v) => DefinitionChange.fromWire(v)),
      properties: f
          .array('properties', defaultEmpty: true)
          .map((v) => WritingProperty.fromWire(v)),
      propertyCorrections: f
          .array('property_corrections', defaultEmpty: true)
          .map((v) => WritingPropertyCorrection.fromWire(v)),
      units: f
          .array('units', defaultEmpty: true)
          .map((v) => WritingUnit.fromWire(v)),
      actions: f
          .array('actions', defaultEmpty: true)
          .map((v) => WritingAction.fromWire(v)),
      itemPowers: f
          .array('item_powers', defaultEmpty: true)
          .map((v) => WritingItemPower.fromWire(v)),
      itemPowerCorrections: f
          .array('item_power_corrections', defaultEmpty: true)
          .map((v) => WritingItemPowerCorrection.fromWire(v)),
      policyCorrections: f
          .array('policy_corrections', defaultEmpty: true)
          .map((v) => WritingPolicyCorrection.fromWire(v)),
      attitudeCorrections: f
          .array('attitude_corrections', defaultEmpty: true)
          .map((v) => WritingAttitudeCorrection.fromWire(v)),
      messageCorrections: f
          .array('message_corrections', defaultEmpty: true)
          .map((v) => WritingMessageCorrection.fromWire(v)),
      interpretationCorrections: f
          .array('interpretation_corrections', defaultEmpty: true)
          .map((v) => WritingInterpretationCorrection.fromWire(v)),
      definitionCorrections: f
          .array('definition_corrections', defaultEmpty: true)
          .map((v) => WritingDefinitionCorrection.fromWire(v)),
      actionCorrections: f
          .array('action_corrections', defaultEmpty: true)
          .map((v) => WritingActionCorrection.fromWire(v)),
      constraints: f
          .array('constraints', defaultEmpty: true)
          .map((v) => WritingConstraint.fromWire(v)),
      exhaustiveSets: f
          .array('exhaustive_sets', defaultEmpty: true)
          .map((v) => WritingExhaustiveSet.fromWire(v)),
      relationDefinitions: f
          .array('relation_definitions', defaultEmpty: true)
          .map((v) => WritingRelationDefinition.fromWire(v)),
      relationLimits: f
          .array('relation_limits', defaultEmpty: true)
          .map((v) => WritingRelationLimit.fromWire(v)),
      relationCorrections: f
          .array('relation_corrections', defaultEmpty: true)
          .map((v) => WritingRelationCorrection.fromWire(v)),
      relationLimitCorrections: f
          .array('relation_limit_corrections', defaultEmpty: true)
          .map((v) => WritingRelationLimitCorrection.fromWire(v)),
      relationships: f
          .array('relationships', defaultEmpty: true)
          .map((v) => WritingRelationship.fromWire(v)),
      relationshipCorrections: f
          .array('relationship_corrections', defaultEmpty: true)
          .map((v) => WritingRelationshipCorrection.fromWire(v)),
      relationshipEndings: f
          .array('relationship_endings', defaultEmpty: true)
          .map((v) => WritingRelationshipEnding.fromWire(v)),
      knowledgePolicies: f
          .array('knowledge_policies', defaultEmpty: true)
          .map((v) => WritingKnowledgePolicy.fromWire(v)),
      knowledgeBoundaries: f
          .array('knowledge_boundaries', defaultEmpty: true)
          .map((v) => WritingKnowledgeBoundary.fromWire(v)),
      initializations: f
          .array('initializations', defaultEmpty: true)
          .map((v) => WritingInitialization.fromWire(v)),
      eventCorrections: f
          .array('event_corrections', defaultEmpty: true)
          .map((v) => WritingEventCorrection.fromWire(v)),
      eventWithdrawals: f
          .array('event_withdrawals', defaultEmpty: true)
          .map((v) => WritingEventWithdrawal.fromWire(v)),
      events: f
          .array('events', defaultEmpty: true)
          .map((v) => WritingEvent.fromWire(v)),
      messages: f
          .array('messages', defaultEmpty: true)
          .map((v) => WritingMessage.fromWire(v)),
      attitudes: f
          .array('attitudes', defaultEmpty: true)
          .map((v) => WritingAttitude.fromWire(v)),
      corrections: f
          .array('corrections', defaultEmpty: true)
          .map((v) => WritingCorrection.fromWire(v)),
      factEndings: f
          .array('fact_endings', defaultEmpty: true)
          .map((v) => WritingFactEnding.fromWire(v)),
      factWithdrawals: f
          .array('fact_withdrawals', defaultEmpty: true)
          .map((v) => WritingFactWithdrawal.fromWire(v)),
      questions: f
          .array('questions', defaultEmpty: true)
          .map((v) => wireString(v)),
    );
  }
  @override
  String get toolName => 'universe_check_changes';
  @override
  CanonicalObject toArgs() => CanonicalObject([
    MapEntry('universe', universe.toWire()),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('worlds', CanonicalArray(worlds.map((v) => v.toWire()))),
    MapEntry(
      'story_contexts',
      CanonicalArray(storyContexts.map((v) => v.toWire())),
    ),
    MapEntry(
      'narrative_works',
      CanonicalArray(narrativeWorks.map((v) => v.toWire())),
    ),
    MapEntry(
      'work_editions',
      CanonicalArray(workEditions.map((v) => v.toWire())),
    ),
    MapEntry('scenes', CanonicalArray(scenes.map((v) => v.toWire()))),
    MapEntry(
      'scene_corrections',
      CanonicalArray(sceneCorrections.map((v) => v.toWire())),
    ),
    MapEntry('changes', CanonicalArray(changes.map((v) => v.toWire()))),
    MapEntry('aliases', CanonicalArray(aliases.map((v) => v.toWire()))),
    MapEntry('definitions', CanonicalArray(definitions.map((v) => v.toWire()))),
    MapEntry('properties', CanonicalArray(properties.map((v) => v.toWire()))),
    MapEntry(
      'property_corrections',
      CanonicalArray(propertyCorrections.map((v) => v.toWire())),
    ),
    MapEntry('units', CanonicalArray(units.map((v) => v.toWire()))),
    MapEntry('actions', CanonicalArray(actions.map((v) => v.toWire()))),
    MapEntry('item_powers', CanonicalArray(itemPowers.map((v) => v.toWire()))),
    MapEntry(
      'item_power_corrections',
      CanonicalArray(itemPowerCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'policy_corrections',
      CanonicalArray(policyCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'attitude_corrections',
      CanonicalArray(attitudeCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'message_corrections',
      CanonicalArray(messageCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'interpretation_corrections',
      CanonicalArray(interpretationCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'definition_corrections',
      CanonicalArray(definitionCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'action_corrections',
      CanonicalArray(actionCorrections.map((v) => v.toWire())),
    ),
    MapEntry('constraints', CanonicalArray(constraints.map((v) => v.toWire()))),
    MapEntry(
      'exhaustive_sets',
      CanonicalArray(exhaustiveSets.map((v) => v.toWire())),
    ),
    MapEntry(
      'relation_definitions',
      CanonicalArray(relationDefinitions.map((v) => v.toWire())),
    ),
    MapEntry(
      'relation_limits',
      CanonicalArray(relationLimits.map((v) => v.toWire())),
    ),
    MapEntry(
      'relation_corrections',
      CanonicalArray(relationCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'relation_limit_corrections',
      CanonicalArray(relationLimitCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'relationships',
      CanonicalArray(relationships.map((v) => v.toWire())),
    ),
    MapEntry(
      'relationship_corrections',
      CanonicalArray(relationshipCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'relationship_endings',
      CanonicalArray(relationshipEndings.map((v) => v.toWire())),
    ),
    MapEntry(
      'knowledge_policies',
      CanonicalArray(knowledgePolicies.map((v) => v.toWire())),
    ),
    MapEntry(
      'knowledge_boundaries',
      CanonicalArray(knowledgeBoundaries.map((v) => v.toWire())),
    ),
    MapEntry(
      'initializations',
      CanonicalArray(initializations.map((v) => v.toWire())),
    ),
    MapEntry(
      'event_corrections',
      CanonicalArray(eventCorrections.map((v) => v.toWire())),
    ),
    MapEntry(
      'event_withdrawals',
      CanonicalArray(eventWithdrawals.map((v) => v.toWire())),
    ),
    MapEntry('events', CanonicalArray(events.map((v) => v.toWire()))),
    MapEntry('messages', CanonicalArray(messages.map((v) => v.toWire()))),
    MapEntry('attitudes', CanonicalArray(attitudes.map((v) => v.toWire()))),
    MapEntry('corrections', CanonicalArray(corrections.map((v) => v.toWire()))),
    MapEntry(
      'fact_endings',
      CanonicalArray(factEndings.map((v) => v.toWire())),
    ),
    MapEntry(
      'fact_withdrawals',
      CanonicalArray(factWithdrawals.map((v) => v.toWire())),
    ),
    MapEntry(
      'questions',
      CanonicalArray(questions.map((v) => CanonicalString(v))),
    ),
  ]);
}

final class WritingWorld {
  WritingWorld({required this.name, this.introduce = false});
  final String name;
  final bool introduce;
  factory WritingWorld.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'introduce'});
    return WritingWorld(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
  ]);
}

final class WritingStoryContext {
  WritingStoryContext({
    required this.name,
    this.introduce = false,
    required this.kind,
    this.narrator,
    required this.parent,
    required this.calendar,
    required this.storyTime,
  });
  final String name;
  final bool introduce;
  final StoryContextKind kind;
  final String? narrator;
  final String parent;
  final String calendar;
  final String storyTime;
  factory WritingStoryContext.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'introduce',
      'kind',
      'narrator',
      'parent',
      'calendar',
      'story_time',
    });
    return WritingStoryContext(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
      kind: StoryContextKind.fromName(wireString(f.require('kind'))),
      narrator: f.optional('narrator', (v) => wireString(v)),
      parent: wireString(f.require('parent')),
      calendar: wireString(f.require('calendar')),
      storyTime: wireString(f.require('story_time')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry(
      'narrator',
      narrator == null ? const CanonicalNull() : CanonicalString(narrator!),
    ),
    MapEntry('parent', CanonicalString(parent)),
    MapEntry('calendar', CanonicalString(calendar)),
    MapEntry('story_time', CanonicalString(storyTime)),
  ]);
}

final class WritingNarrativeWork {
  WritingNarrativeWork({
    required this.name,
    required this.introduce,
    required this.kind,
  });
  final String name;
  final bool introduce;
  final WorkKind kind;
  factory WritingNarrativeWork.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'introduce', 'kind'});
    return WritingNarrativeWork(
      name: wireString(f.require('name')),
      introduce: _writingBool(f.require('introduce')),
      kind: WorkKind.fromName(wireString(f.require('kind'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('kind', CanonicalString(kind.wireName)),
  ]);
}

final class WritingWorkEdition {
  WritingWorkEdition({
    required this.work,
    required this.name,
    required this.introduce,
    required this.binding,
  });
  final String work;
  final String name;
  final bool introduce;
  final WritingEditionBinding binding;
  factory WritingWorkEdition.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'work', 'name', 'introduce', 'binding'});
    return WritingWorkEdition(
      work: wireString(f.require('work')),
      name: wireString(f.require('name')),
      introduce: _writingBool(f.require('introduce')),
      binding: WritingEditionBinding.fromName(wireString(f.require('binding'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('work', CanonicalString(work)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('binding', CanonicalString(binding.wireName)),
  ]);
}

final class WritingScene {
  WritingScene({
    required this.name,
    required this.introduce,
    required this.work,
    required this.edition,
    required this.narrationContext,
    this.viewpoint,
    BigInt? readerOrder,
    Iterable<String> depictedEvents = const [],
    Iterable<WritingDisclosure> disclosures = const [],
  }) : readerOrder = readerOrder == null ? null : checkedU64(readerOrder),
       depictedEvents = List.unmodifiable(depictedEvents),
       disclosures = List.unmodifiable(disclosures);
  final String name;
  final bool introduce;
  final String work;
  final String edition;
  final String narrationContext;
  final String? viewpoint;
  final BigInt? readerOrder;
  final List<String> depictedEvents;
  final List<WritingDisclosure> disclosures;
  factory WritingScene.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'introduce',
      'work',
      'edition',
      'narration_context',
      'viewpoint',
      'reader_order',
      'depicted_events',
      'disclosures',
    });
    return WritingScene(
      name: wireString(f.require('name')),
      introduce: _writingBool(f.require('introduce')),
      work: wireString(f.require('work')),
      edition: wireString(f.require('edition')),
      narrationContext: wireString(f.require('narration_context')),
      viewpoint: f.optional('viewpoint', (v) => wireString(v)),
      readerOrder: f.optional(
        'reader_order',
        (v) => WireFields(CanonicalObject([MapEntry('n', v)]), {'n'}).u64('n'),
      ),
      depictedEvents: f
          .array('depicted_events', defaultEmpty: true)
          .map((v) => wireString(v)),
      disclosures: f
          .array('disclosures', defaultEmpty: true)
          .map((v) => WritingDisclosure.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('work', CanonicalString(work)),
    MapEntry('edition', CanonicalString(edition)),
    MapEntry('narration_context', CanonicalString(narrationContext)),
    MapEntry(
      'viewpoint',
      viewpoint == null ? const CanonicalNull() : CanonicalString(viewpoint!),
    ),
    MapEntry(
      'reader_order',
      readerOrder == null
          ? const CanonicalNull()
          : CanonicalNumber(readerOrder!.toString()),
    ),
    MapEntry(
      'depicted_events',
      CanonicalArray(depictedEvents.map((v) => CanonicalString(v))),
    ),
    MapEntry('disclosures', CanonicalArray(disclosures.map((v) => v.toWire()))),
  ]);
}

final class WritingSceneCorrection {
  WritingSceneCorrection({
    required this.sceneHandle,
    required this.reason,
    this.narrationContext,
    this.viewpoint,
    this.clearViewpoint = false,
    BigInt? readerOrder,
    this.clearReaderOrder = false,
    Iterable<String>? depictedEvents,
    Iterable<WritingDisclosure>? disclosures,
  }) : readerOrder = readerOrder == null ? null : checkedU64(readerOrder),
       depictedEvents = depictedEvents == null
           ? null
           : List.unmodifiable(depictedEvents),
       disclosures = disclosures == null
           ? null
           : List.unmodifiable(disclosures);
  final String sceneHandle;
  final String reason;
  final String? narrationContext;
  final String? viewpoint;
  final bool clearViewpoint;
  final BigInt? readerOrder;
  final bool clearReaderOrder;
  final List<String>? depictedEvents;
  final List<WritingDisclosure>? disclosures;
  factory WritingSceneCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'scene_handle',
      'reason',
      'narration_context',
      'viewpoint',
      'clear_viewpoint',
      'reader_order',
      'clear_reader_order',
      'depicted_events',
      'disclosures',
    });
    return WritingSceneCorrection(
      sceneHandle: wireString(f.require('scene_handle')),
      reason: wireString(f.require('reason')),
      narrationContext: f.optional('narration_context', (v) => wireString(v)),
      viewpoint: f.optional('viewpoint', (v) => wireString(v)),
      clearViewpoint: f.values.containsKey('clear_viewpoint')
          ? _writingBool(f.require('clear_viewpoint'))
          : false,
      readerOrder: f.optional(
        'reader_order',
        (v) => WireFields(CanonicalObject([MapEntry('n', v)]), {'n'}).u64('n'),
      ),
      clearReaderOrder: f.values.containsKey('clear_reader_order')
          ? _writingBool(f.require('clear_reader_order'))
          : false,
      depictedEvents: f.optional(
        'depicted_events',
        (v) => _writingArray(v).map((v) => wireString(v)),
      ),
      disclosures: f.optional(
        'disclosures',
        (v) => _writingArray(v).map((v) => WritingDisclosure.fromWire(v)),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('scene_handle', CanonicalString(sceneHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'narration_context',
      narrationContext == null
          ? const CanonicalNull()
          : CanonicalString(narrationContext!),
    ),
    MapEntry(
      'viewpoint',
      viewpoint == null ? const CanonicalNull() : CanonicalString(viewpoint!),
    ),
    MapEntry('clear_viewpoint', CanonicalBool(clearViewpoint)),
    MapEntry(
      'reader_order',
      readerOrder == null
          ? const CanonicalNull()
          : CanonicalNumber(readerOrder!.toString()),
    ),
    MapEntry('clear_reader_order', CanonicalBool(clearReaderOrder)),
    MapEntry(
      'depicted_events',
      depictedEvents == null
          ? const CanonicalNull()
          : CanonicalArray(depictedEvents!.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'disclosures',
      disclosures == null
          ? const CanonicalNull()
          : CanonicalArray(disclosures!.map((v) => v.toWire())),
    ),
  ]);
}

final class WritingItemPower {
  WritingItemPower({
    required this.item,
    required this.holderProperty,
    required this.abilityProperty,
    required this.value,
    required this.scope,
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
  });
  final String item;
  final String holderProperty;
  final String abilityProperty;
  final FactValue value;
  final String scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory WritingItemPower.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'item',
      'holder_property',
      'ability_property',
      'value',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingItemPower(
      item: wireString(f.require('item')),
      holderProperty: wireString(f.require('holder_property')),
      abilityProperty: wireString(f.require('ability_property')),
      value: FactValue.fromWire(f.require('value')),
      scope: wireString(f.require('scope')),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('item', CanonicalString(item)),
    MapEntry('holder_property', CanonicalString(holderProperty)),
    MapEntry('ability_property', CanonicalString(abilityProperty)),
    MapEntry('value', value.toWire()),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingItemPowerCorrection {
  WritingItemPowerCorrection({
    required this.grantHandle,
    required this.reason,
    this.value,
    this.scope,
    this.atTick,
    this.atDate,
    this.lifetime,
    this.endTick,
    this.endDate,
  });
  final String grantHandle;
  final String reason;
  final FactValue? value;
  final String? scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime? lifetime;
  final String? endTick;
  final String? endDate;
  factory WritingItemPowerCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'grant_handle',
      'reason',
      'value',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
      'end_tick',
      'end_date',
    });
    return WritingItemPowerCorrection(
      grantHandle: wireString(f.require('grant_handle')),
      reason: wireString(f.require('reason')),
      value: f.optional('value', (v) => FactValue.fromWire(v)),
      scope: f.optional('scope', (v) => wireString(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.optional('lifetime', (v) => FactLifetime.fromWire(v)),
      endTick: f.optional('end_tick', (v) => wireString(v)),
      endDate: f.optional('end_date', (v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('grant_handle', CanonicalString(grantHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry('value', value == null ? const CanonicalNull() : value!.toWire()),
    MapEntry(
      'scope',
      scope == null ? const CanonicalNull() : CanonicalString(scope!),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'lifetime',
      lifetime == null ? const CanonicalNull() : lifetime!.toWire(),
    ),
    MapEntry(
      'end_tick',
      endTick == null ? const CanonicalNull() : CanonicalString(endTick!),
    ),
    if (endDate != null) MapEntry('end_date', CanonicalString(endDate!)),
  ]);
}

final class WritingCheck {
  WritingCheck({
    required this.status,
    this.candidateHandle,
    required Iterable<String> additions,
    required Iterable<String> unchanged,
    required Iterable<String> clarifications,
    required Iterable<String> excluded,
    required Iterable<String> unknowns,
    this.validation,
    this.impact,
  }) : additions = List.unmodifiable(additions),
       unchanged = List.unmodifiable(unchanged),
       clarifications = List.unmodifiable(clarifications),
       excluded = List.unmodifiable(excluded),
       unknowns = List.unmodifiable(unknowns);
  final String status;
  final String? candidateHandle;
  final List<String> additions;
  final List<String> unchanged;
  final List<String> clarifications;
  final List<String> excluded;
  final List<String> unknowns;
  final CanonicalValue? validation;
  final CanonicalValue? impact;
  factory WritingCheck.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'status',
      'candidate_handle',
      'additions',
      'unchanged',
      'clarifications',
      'excluded',
      'unknowns',
      'validation',
      'impact',
    });
    return WritingCheck(
      status: wireString(f.require('status')),
      candidateHandle: f.optional('candidate_handle', (v) => wireString(v)),
      additions: f
          .array('additions', defaultEmpty: false)
          .map((v) => wireString(v)),
      unchanged: f
          .array('unchanged', defaultEmpty: false)
          .map((v) => wireString(v)),
      clarifications: f
          .array('clarifications', defaultEmpty: false)
          .map((v) => wireString(v)),
      excluded: f
          .array('excluded', defaultEmpty: false)
          .map((v) => wireString(v)),
      unknowns: f
          .array('unknowns', defaultEmpty: false)
          .map((v) => wireString(v)),
      validation: f.optional('validation', (v) => v),
      impact: f.optional('impact', (v) => v),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('status', CanonicalString(status)),
    MapEntry(
      'candidate_handle',
      candidateHandle == null
          ? const CanonicalNull()
          : CanonicalString(candidateHandle!),
    ),
    MapEntry(
      'additions',
      CanonicalArray(additions.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'unchanged',
      CanonicalArray(unchanged.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'clarifications',
      CanonicalArray(clarifications.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'excluded',
      CanonicalArray(excluded.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'unknowns',
      CanonicalArray(unknowns.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'validation',
      validation == null ? const CanonicalNull() : validation!,
    ),
    MapEntry('impact', impact == null ? const CanonicalNull() : impact!),
  ]);
}

final class WritingProperty {
  WritingProperty({
    required this.name,
    this.introduce = false,
    required this.valueType,
    this.unit,
    required this.singleValue,
    required this.persistence,
  });
  final String name;
  final bool introduce;
  final PlainPropertyType valueType;
  final String? unit;
  final bool singleValue;
  final PlainPersistence persistence;
  factory WritingProperty.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'introduce',
      'value_type',
      'unit',
      'single_value',
      'persistence',
    });
    return WritingProperty(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
      valueType: PlainPropertyType.fromName(
        wireString(f.require('value_type')),
      ),
      unit: f.optional('unit', (v) => wireString(v)),
      singleValue: _writingBool(f.require('single_value')),
      persistence: PlainPersistence.fromName(
        wireString(f.require('persistence')),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('value_type', CanonicalString(valueType.wireName)),
    MapEntry(
      'unit',
      unit == null ? const CanonicalNull() : CanonicalString(unit!),
    ),
    MapEntry('single_value', CanonicalBool(singleValue)),
    MapEntry('persistence', CanonicalString(persistence.wireName)),
  ]);
}

final class WritingPropertyCorrection {
  WritingPropertyCorrection({
    required this.name,
    this.singleValue,
    this.persistence,
    required this.reason,
  });
  final String name;
  final bool? singleValue;
  final PlainPersistence? persistence;
  final String reason;
  factory WritingPropertyCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'single_value',
      'persistence',
      'reason',
    });
    return WritingPropertyCorrection(
      name: wireString(f.require('name')),
      singleValue: f.optional('single_value', (v) => _writingBool(v)),
      persistence: f.optional(
        'persistence',
        (v) => PlainPersistence.fromName(wireString(v)),
      ),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry(
      'single_value',
      singleValue == null ? const CanonicalNull() : CanonicalBool(singleValue!),
    ),
    MapEntry(
      'persistence',
      persistence == null
          ? const CanonicalNull()
          : CanonicalString(persistence!.wireName),
    ),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class RoleValue {
  RoleValue({required this.role, required this.property, required this.value});
  final String role;
  final String property;
  final FactValue value;
  factory RoleValue.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'role', 'property', 'value'});
    return RoleValue(
      role: wireString(f.require('role')),
      property: wireString(f.require('property')),
      value: FactValue.fromWire(f.require('value')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('property', CanonicalString(property)),
    MapEntry('value', value.toWire()),
  ]);
}

final class WritingEffect {
  WritingEffect({
    required this.role,
    required this.property,
    required this.change,
    required this.lifetime,
    this.optional = false,
    this.condition,
  });
  final String role;
  final String property;
  final WritingEffectChange change;
  final WritingEffectLifetime lifetime;
  final bool optional;
  final RoleValue? condition;
  factory WritingEffect.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'role',
      'property',
      'change',
      'lifetime',
      'optional',
      'condition',
    });
    return WritingEffect(
      role: wireString(f.require('role')),
      property: wireString(f.require('property')),
      change: WritingEffectChange.fromWire(f.require('change')),
      lifetime: WritingEffectLifetime.fromWire(f.require('lifetime')),
      optional: f.values.containsKey('optional')
          ? _writingBool(f.require('optional'))
          : false,
      condition: f.optional('condition', (v) => RoleValue.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('property', CanonicalString(property)),
    MapEntry('change', change.toWire()),
    MapEntry('lifetime', lifetime.toWire()),
    MapEntry('optional', CanonicalBool(optional)),
    MapEntry(
      'condition',
      condition == null ? const CanonicalNull() : condition!.toWire(),
    ),
  ]);
}

final class WritingAction {
  WritingAction({
    required this.name,
    this.introduce = false,
    Iterable<RoleValue> requirements = const [],
    Iterable<WritingEffect> effects = const [],
    this.scope = 'unspecified',
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
  }) : requirements = List.unmodifiable(requirements),
       effects = List.unmodifiable(effects);
  final String name;
  final bool introduce;
  final List<RoleValue> requirements;
  final List<WritingEffect> effects;
  final String scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory WritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'introduce',
      'requirements',
      'effects',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingAction(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
      requirements: f
          .array('requirements', defaultEmpty: true)
          .map((v) => RoleValue.fromWire(v)),
      effects: f
          .array('effects', defaultEmpty: true)
          .map((v) => WritingEffect.fromWire(v)),
      scope: f.values.containsKey('scope')
          ? wireString(f.require('scope'))
          : 'unspecified',
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry(
      'requirements',
      CanonicalArray(requirements.map((v) => v.toWire())),
    ),
    MapEntry('effects', CanonicalArray(effects.map((v) => v.toWire()))),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingInitialization {
  WritingInitialization({
    required this.instance,
    required Iterable<String> initialValueHandles,
    required this.start,
    required this.scope,
    required this.lifetime,
  }) : initialValueHandles = List.unmodifiable(initialValueHandles);
  final String instance;
  final List<String> initialValueHandles;
  final WritingInstanceStart start;
  final String scope;
  final FactLifetime lifetime;
  factory WritingInitialization.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'instance',
      'initial_value_handles',
      'start',
      'scope',
      'lifetime',
    });
    return WritingInitialization(
      instance: wireString(f.require('instance')),
      initialValueHandles: f
          .array('initial_value_handles', defaultEmpty: false)
          .map((v) => wireString(v)),
      start: WritingInstanceStart.fromWire(f.require('start')),
      scope: wireString(f.require('scope')),
      lifetime: FactLifetime.fromWire(f.require('lifetime')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('instance', CanonicalString(instance)),
    MapEntry(
      'initial_value_handles',
      CanonicalArray(initialValueHandles.map((v) => CanonicalString(v))),
    ),
    MapEntry('start', start.toWire()),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingUnit {
  WritingUnit({
    required this.name,
    this.introduce = false,
    required this.dimension,
    required this.symbol,
  });
  final String name;
  final bool introduce;
  final String dimension;
  final String symbol;
  factory WritingUnit.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'introduce', 'dimension', 'symbol'});
    return WritingUnit(
      name: wireString(f.require('name')),
      introduce: f.values.containsKey('introduce')
          ? _writingBool(f.require('introduce'))
          : false,
      dimension: wireString(f.require('dimension')),
      symbol: wireString(f.require('symbol')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('dimension', CanonicalString(dimension)),
    MapEntry('symbol', CanonicalString(symbol)),
  ]);
}

final class WritingDefinitionCorrection {
  WritingDefinitionCorrection({
    required this.name,
    required this.reason,
    this.parent,
    this.scope,
  });
  final String name;
  final String reason;
  final WritingParent? parent;
  final String? scope;
  factory WritingDefinitionCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'reason', 'parent', 'scope'});
    return WritingDefinitionCorrection(
      name: wireString(f.require('name')),
      reason: wireString(f.require('reason')),
      parent: f.optional('parent', (v) => WritingParent.fromWire(v)),
      scope: f.optional('scope', (v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'parent',
      parent == null ? const CanonicalNull() : parent!.toWire(),
    ),
    MapEntry(
      'scope',
      scope == null ? const CanonicalNull() : CanonicalString(scope!),
    ),
  ]);
}

final class WritingActionCorrection {
  WritingActionCorrection({
    required this.name,
    required this.reason,
    Iterable<RoleValue>? requirements,
    Iterable<WritingEffect>? effects,
    this.scope,
    this.atTick,
    this.atDate,
    this.lifetime,
  }) : requirements = requirements == null
           ? null
           : List.unmodifiable(requirements),
       effects = effects == null ? null : List.unmodifiable(effects);
  final String name;
  final String reason;
  final List<RoleValue>? requirements;
  final List<WritingEffect>? effects;
  final String? scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime? lifetime;
  factory WritingActionCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'reason',
      'requirements',
      'effects',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingActionCorrection(
      name: wireString(f.require('name')),
      reason: wireString(f.require('reason')),
      requirements: f.optional(
        'requirements',
        (v) => _writingArray(v).map((v) => RoleValue.fromWire(v)),
      ),
      effects: f.optional(
        'effects',
        (v) => _writingArray(v).map((v) => WritingEffect.fromWire(v)),
      ),
      scope: f.optional('scope', (v) => wireString(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.optional('lifetime', (v) => FactLifetime.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'requirements',
      requirements == null
          ? const CanonicalNull()
          : CanonicalArray(requirements!.map((v) => v.toWire())),
    ),
    MapEntry(
      'effects',
      effects == null
          ? const CanonicalNull()
          : CanonicalArray(effects!.map((v) => v.toWire())),
    ),
    MapEntry(
      'scope',
      scope == null ? const CanonicalNull() : CanonicalString(scope!),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'lifetime',
      lifetime == null ? const CanonicalNull() : lifetime!.toWire(),
    ),
  ]);
}

final class WritingExhaustiveSet {
  WritingExhaustiveSet({
    required this.subject,
    required this.property,
    required Iterable<String> members,
    required this.scope,
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
  }) : members = List.unmodifiable(members);
  final String subject;
  final String property;
  final List<String> members;
  final String scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory WritingExhaustiveSet.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'subject',
      'property',
      'members',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingExhaustiveSet(
      subject: wireString(f.require('subject')),
      property: wireString(f.require('property')),
      members: f
          .array('members', defaultEmpty: false)
          .map((v) => wireString(v)),
      scope: wireString(f.require('scope')),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('subject', CanonicalString(subject)),
    MapEntry('property', CanonicalString(property)),
    MapEntry('members', CanonicalArray(members.map((v) => CanonicalString(v)))),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingRelationDefinition {
  WritingRelationDefinition({
    required this.name,
    required this.introduce,
    required Iterable<WritingRelationRole> roles,
  }) : roles = List.unmodifiable(roles);
  final String name;
  final bool introduce;
  final List<WritingRelationRole> roles;
  factory WritingRelationDefinition.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'introduce', 'roles'});
    return WritingRelationDefinition(
      name: wireString(f.require('name')),
      introduce: _writingBool(f.require('introduce')),
      roles: f
          .array('roles', defaultEmpty: false)
          .map((v) => WritingRelationRole.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('introduce', CanonicalBool(introduce)),
    MapEntry('roles', CanonicalArray(roles.map((v) => v.toWire()))),
  ]);
}

final class WritingRelationRole {
  WritingRelationRole({required this.name, required this.multiple});
  final String name;
  final bool multiple;
  factory WritingRelationRole.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'multiple'});
    return WritingRelationRole(
      name: wireString(f.require('name')),
      multiple: _writingBool(f.require('multiple')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('multiple', CanonicalBool(multiple)),
  ]);
}

final class WritingRelationLimit {
  WritingRelationLimit({
    required this.name,
    required this.relation,
    required this.grouping,
    required this.countedRole,
    required int maximum,
    required this.scope,
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
  }) : maximum = _checkedRequestU32(maximum);
  final String name;
  final String relation;
  final WritingRelationGrouping grouping;
  final String countedRole;
  final int maximum;
  final String scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory WritingRelationLimit.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'relation',
      'grouping',
      'counted_role',
      'maximum',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingRelationLimit(
      name: wireString(f.require('name')),
      relation: wireString(f.require('relation')),
      grouping: WritingRelationGrouping.fromWire(f.require('grouping')),
      countedRole: wireString(f.require('counted_role')),
      maximum: _requestU32(f.require('maximum')),
      scope: wireString(f.require('scope')),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('relation', CanonicalString(relation)),
    MapEntry('grouping', grouping.toWire()),
    MapEntry('counted_role', CanonicalString(countedRole)),
    MapEntry('maximum', CanonicalNumber(maximum.toString())),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingRelationship {
  WritingRelationship({
    required this.relation,
    required this.subject,
    required Map<String, List<String>> participants,
    required this.scope,
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
    this.negated = false,
    this.statement = 'objective',
  }) : participants = Map.unmodifiable({
         for (final e in participants.entries)
           e.key: List<String>.unmodifiable(e.value),
       });
  final String relation;
  final String subject;
  final Map<String, List<String>> participants;
  final String scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  final bool negated;
  final String statement;
  factory WritingRelationship.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'relation',
      'subject',
      'participants',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
      'negated',
      'statement',
    });
    return WritingRelationship(
      relation: wireString(f.require('relation')),
      subject: wireString(f.require('subject')),
      participants: _writingRoleLists(f.require('participants')),
      scope: wireString(f.require('scope')),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
      negated: f.values.containsKey('negated')
          ? _writingBool(f.require('negated'))
          : false,
      statement: f.values.containsKey('statement')
          ? wireString(f.require('statement'))
          : 'objective',
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('relation', CanonicalString(relation)),
    MapEntry('subject', CanonicalString(subject)),
    MapEntry(
      'participants',
      CanonicalObject(
        participants.entries.map(
          (e) =>
              MapEntry(e.key, CanonicalArray(e.value.map(CanonicalString.new))),
        ),
      ),
    ),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
    MapEntry('negated', CanonicalBool(negated)),
    MapEntry('statement', CanonicalString(statement)),
  ]);
}

final class WritingRelationshipCorrection {
  WritingRelationshipCorrection({
    required this.relationshipHandle,
    required Map<String, List<String>> participants,
    required this.reason,
  }) : participants = Map.unmodifiable({
         for (final e in participants.entries)
           e.key: List<String>.unmodifiable(e.value),
       });
  final String relationshipHandle;
  final Map<String, List<String>> participants;
  final String reason;
  factory WritingRelationshipCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'relationship_handle',
      'participants',
      'reason',
    });
    return WritingRelationshipCorrection(
      relationshipHandle: wireString(f.require('relationship_handle')),
      participants: _writingRoleLists(f.require('participants')),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('relationship_handle', CanonicalString(relationshipHandle)),
    MapEntry(
      'participants',
      CanonicalObject(
        participants.entries.map(
          (e) =>
              MapEntry(e.key, CanonicalArray(e.value.map(CanonicalString.new))),
        ),
      ),
    ),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WritingRelationshipEnding {
  WritingRelationshipEnding({
    required this.relationshipHandle,
    this.endTick = '',
    this.endDate,
    required this.reason,
  });
  final String relationshipHandle;
  final String endTick;
  final String? endDate;
  final String reason;
  factory WritingRelationshipEnding.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'relationship_handle',
      'end_tick',
      'end_date',
      'reason',
    });
    return WritingRelationshipEnding(
      relationshipHandle: wireString(f.require('relationship_handle')),
      endTick: f.values.containsKey('end_tick')
          ? wireString(f.require('end_tick'))
          : '',
      endDate: f.optional('end_date', (v) => wireString(v)),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('relationship_handle', CanonicalString(relationshipHandle)),
    MapEntry('end_tick', CanonicalString(endTick)),
    if (endDate != null) MapEntry('end_date', CanonicalString(endDate!)),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WritingRelationCorrection {
  WritingRelationCorrection({
    required this.name,
    required Iterable<WritingRelationRoleCorrection> roles,
    required this.reason,
  }) : roles = List.unmodifiable(roles);
  final String name;
  final List<WritingRelationRoleCorrection> roles;
  final String reason;
  factory WritingRelationCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'roles', 'reason'});
    return WritingRelationCorrection(
      name: wireString(f.require('name')),
      roles: f
          .array('roles', defaultEmpty: false)
          .map((v) => WritingRelationRoleCorrection.fromWire(v)),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('roles', CanonicalArray(roles.map((v) => v.toWire()))),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WritingRelationRoleCorrection {
  WritingRelationRoleCorrection({
    required this.name,
    this.multiple,
    this.ordered,
    Iterable<String>? participantTypes,
  }) : participantTypes = participantTypes == null
           ? null
           : List.unmodifiable(participantTypes);
  final String name;
  final bool? multiple;
  final bool? ordered;
  final List<String>? participantTypes;
  factory WritingRelationRoleCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'multiple',
      'ordered',
      'participant_types',
    });
    return WritingRelationRoleCorrection(
      name: wireString(f.require('name')),
      multiple: f.optional('multiple', (v) => _writingBool(v)),
      ordered: f.optional('ordered', (v) => _writingBool(v)),
      participantTypes: f.optional(
        'participant_types',
        (v) => _writingArray(v).map((v) => wireString(v)),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry(
      'multiple',
      multiple == null ? const CanonicalNull() : CanonicalBool(multiple!),
    ),
    MapEntry(
      'ordered',
      ordered == null ? const CanonicalNull() : CanonicalBool(ordered!),
    ),
    MapEntry(
      'participant_types',
      participantTypes == null
          ? const CanonicalNull()
          : CanonicalArray(participantTypes!.map((v) => CanonicalString(v))),
    ),
  ]);
}

final class WritingRelationLimitCorrection {
  WritingRelationLimitCorrection({
    required this.name,
    int? maximum,
    this.grouping,
    this.countedRole,
    this.scope,
    this.atTick,
    this.atDate,
    this.lifetime,
    required this.reason,
  }) : maximum = maximum == null ? null : _checkedRequestU32(maximum);
  final String name;
  final int? maximum;
  final WritingRelationGrouping? grouping;
  final String? countedRole;
  final String? scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime? lifetime;
  final String reason;
  factory WritingRelationLimitCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'maximum',
      'grouping',
      'counted_role',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
      'reason',
    });
    return WritingRelationLimitCorrection(
      name: wireString(f.require('name')),
      maximum: f.optional('maximum', (v) => _requestU32(v)),
      grouping: f.optional(
        'grouping',
        (v) => WritingRelationGrouping.fromWire(v),
      ),
      countedRole: f.optional('counted_role', (v) => wireString(v)),
      scope: f.optional('scope', (v) => wireString(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.optional('lifetime', (v) => FactLifetime.fromWire(v)),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry(
      'maximum',
      maximum == null
          ? const CanonicalNull()
          : CanonicalNumber(maximum!.toString()),
    ),
    MapEntry(
      'grouping',
      grouping == null ? const CanonicalNull() : grouping!.toWire(),
    ),
    MapEntry(
      'counted_role',
      countedRole == null
          ? const CanonicalNull()
          : CanonicalString(countedRole!),
    ),
    MapEntry(
      'scope',
      scope == null ? const CanonicalNull() : CanonicalString(scope!),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'lifetime',
      lifetime == null ? const CanonicalNull() : lifetime!.toWire(),
    ),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WritingAlias {
  WritingAlias({
    required this.object,
    required this.text,
    this.language,
    this.community,
    this.role,
    this.atTick,
    this.atDate,
    this.lifetime,
  });
  final String object;
  final String text;
  final String? language;
  final String? community;
  final String? role;
  final String? atTick;
  final String? atDate;
  final FactLifetime? lifetime;
  factory WritingAlias.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'object',
      'text',
      'language',
      'community',
      'role',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingAlias(
      object: wireString(f.require('object')),
      text: wireString(f.require('text')),
      language: f.optional('language', (v) => wireString(v)),
      community: f.optional('community', (v) => wireString(v)),
      role: f.optional('role', (v) => wireString(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.optional('lifetime', (v) => FactLifetime.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('object', CanonicalString(object)),
    MapEntry('text', CanonicalString(text)),
    MapEntry(
      'language',
      language == null ? const CanonicalNull() : CanonicalString(language!),
    ),
    MapEntry(
      'community',
      community == null ? const CanonicalNull() : CanonicalString(community!),
    ),
    MapEntry(
      'role',
      role == null ? const CanonicalNull() : CanonicalString(role!),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'lifetime',
      lifetime == null ? const CanonicalNull() : lifetime!.toWire(),
    ),
  ]);
}

CanonicalNumber _writingNumber(CanonicalValue value) {
  if (value is! CanonicalNumber) {
    throw const FormatException('Expected writing number');
  }
  return _factNumber(value);
}

Map<String, List<String>> _writingRoleLists(CanonicalValue value) {
  if (value is! CanonicalObject) {
    throw const FormatException('Expected role/participant map');
  }
  return {
    for (final e in value.fields)
      e.key: _writingArray(e.value).map(wireString).toList(),
  };
}
