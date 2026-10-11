@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final fixtures = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/writing-delta.json').readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in fixtures.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust complete writing fields $index:$type', () {
      final value = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final encoded = switch (type) {
        'WritingWorld' => WritingWorld.fromWire(value).toWire(),
        'WritingStoryContext' => WritingStoryContext.fromWire(value).toWire(),
        'WritingNarrativeWork' => WritingNarrativeWork.fromWire(value).toWire(),
        'WritingWorkEdition' => WritingWorkEdition.fromWire(value).toWire(),
        'WritingScene' => WritingScene.fromWire(value).toWire(),
        'WritingSceneCorrection' => WritingSceneCorrection.fromWire(
          value,
        ).toWire(),
        'WritingItemPower' => WritingItemPower.fromWire(value).toWire(),
        'WritingItemPowerCorrection' => WritingItemPowerCorrection.fromWire(
          value,
        ).toWire(),
        'WritingCheck' => WritingCheck.fromWire(value).toWire(),
        'WritingProperty' => WritingProperty.fromWire(value).toWire(),
        'WritingPropertyCorrection' => WritingPropertyCorrection.fromWire(
          value,
        ).toWire(),
        'RoleValue' => RoleValue.fromWire(value).toWire(),
        'WritingEffect' => WritingEffect.fromWire(value).toWire(),
        'WritingAction' => WritingAction.fromWire(value).toWire(),
        'WritingInitialization' => WritingInitialization.fromWire(
          value,
        ).toWire(),
        'WritingUnit' => WritingUnit.fromWire(value).toWire(),
        'WritingDefinitionCorrection' => WritingDefinitionCorrection.fromWire(
          value,
        ).toWire(),
        'WritingActionCorrection' => WritingActionCorrection.fromWire(
          value,
        ).toWire(),
        'WritingExhaustiveSet' => WritingExhaustiveSet.fromWire(value).toWire(),
        'WritingRelationDefinition' => WritingRelationDefinition.fromWire(
          value,
        ).toWire(),
        'WritingRelationRole' => WritingRelationRole.fromWire(value).toWire(),
        'WritingRelationLimit' => WritingRelationLimit.fromWire(value).toWire(),
        'WritingRelationship' => WritingRelationship.fromWire(value).toWire(),
        'WritingRelationshipCorrection' =>
          WritingRelationshipCorrection.fromWire(value).toWire(),
        'WritingRelationshipEnding' => WritingRelationshipEnding.fromWire(
          value,
        ).toWire(),
        'WritingRelationCorrection' => WritingRelationCorrection.fromWire(
          value,
        ).toWire(),
        'WritingRelationRoleCorrection' =>
          WritingRelationRoleCorrection.fromWire(value).toWire(),
        'WritingRelationLimitCorrection' =>
          WritingRelationLimitCorrection.fromWire(value).toWire(),
        'WritingAlias' => WritingAlias.fromWire(value).toWire(),
        'WritingDisclosure' => WritingDisclosure.fromWire(value).toWire(),
        'WritingEffectChange' => WritingEffectChange.fromWire(value).toWire(),
        'WritingEffectLifetime' => WritingEffectLifetime.fromWire(
          value,
        ).toWire(),
        'WritingConstraint' => WritingConstraint.fromWire(value).toWire(),
        'WritingInstanceStart' => WritingInstanceStart.fromWire(value).toWire(),
        'WritingParent' => WritingParent.fromWire(value).toWire(),
        'WritingRelationGrouping' => WritingRelationGrouping.fromWire(
          value,
        ).toWire(),
        'StoryContextKind' => CanonicalString(
          StoryContextKind.fromName((value as CanonicalString).value).wireName,
        ),
        'WritingEditionBinding' => CanonicalString(
          WritingEditionBinding.fromName((value as CanonicalString).value)
              .wireName,
        ),
        'PlainPropertyType' => CanonicalString(
          PlainPropertyType.fromName((value as CanonicalString).value).wireName,
        ),
        'PlainPersistence' => CanonicalString(
          PlainPersistence.fromName((value as CanonicalString).value).wireName,
        ),
        'CheckChanges' => CheckChangesRequest.fromWire(value).toArgs(),
        _ => throw StateError('Unknown fixture'),
      };
      expect(encoded.toText(), (f['canonical_utf8']! as CanonicalString).value);
    });
  }
}
