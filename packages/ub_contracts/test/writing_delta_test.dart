import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String text) => CanonicalValue.parseWireJson(text);
const universe = Selector('Cycle');
final context = ContextId.parse('ctx_000000000000000000000001');
final invalid = throwsA(isA<InvalidArgumentError>());

void main() {
  test('complete change delta defaults every omitted family and never creates authority', () {
    final delta = CheckChangesRequest.fromWire(
      wire('{"universe":"Cycle","context_id":"ctx_000000000000000000000001"}'),
    );
    final back = Request.fromTool(
      'universe_check_changes',
      delta.toArgs(),
    ) as CheckChangesRequest;
    expect(back.changes, isEmpty);
    expect(back.worlds, isEmpty);
    expect(back.questions, isEmpty);
    expect(back.initializations, isEmpty);
    expect(back.scenes, isEmpty);
    final familyFields = delta
        .toArgs()
        .fields
        .where((e) => e.value is CanonicalArray)
        .toList();
    expect(familyFields, hasLength(42));
    expect(
      familyFields.every((e) => (e.value as CanonicalArray).items.isEmpty),
      isTrue,
    );
    final forbidden = CanonicalObject([
      ...delta.toArgs().fields,
      MapEntry('author_knowledge', CanonicalArray([])),
    ]);
    expect(
      () => Request.fromTool('universe_check_changes', forbidden),
      invalid,
    );
    expect(
      Request.decode(delta.toWire().toBytes()),
      isA<CheckChangesRequest>(),
    );
  });
  test('delta JSON retains exact numeric amounts and questions without filling in owners', () {
    final delta = Request.decode(
      wire(
        '{"tool":"universe_check_changes","args":{"universe":"Cycle","context_id":"ctx_000000000000000000000001","changes":[{"name":"Pistol","facts":[{"property":"stock","value":30.00}]}],"questions":["Who is the holder?"]}}',
      ).toBytes(),
    ) as CheckChangesRequest;
    expect(delta.changes.single.facts.single.value.toWire().toText(), '30.00');
    expect(delta.changes.single.introduce, isFalse);
    expect(delta.changes.single.facts.single.scope, 'unspecified');
    expect(delta.questions, ['Who is the holder?']);
    expect(delta.relationships, isEmpty);
  });
  test('delta limits count authored objects facts combined occurrences and questions', () {
    final fact = FactChange(
      property: 'age',
      value: FactNumberValue(const CanonicalNumber('40')),
    );
    final event = WritingEvent(action: 'Wait', participants: {});
    final allowed = CheckChangesRequest(
      universe: universe,
      contextId: context,
      changes: [ObjectChange(name: 'Mara', facts: List.filled(100, fact))],
      questions: List.filled(20, 'Who?'),
      events: List.filled(100, event),
    );
    allowed.validate();
    for (final delta in [
      CheckChangesRequest(
        universe: universe,
        contextId: context,
        questions: List.filled(21, 'Who?'),
      ),
      CheckChangesRequest(
        universe: universe,
        contextId: context,
        changes: List.filled(101, ObjectChange(name: 'Mara')),
      ),
      CheckChangesRequest(
        universe: universe,
        contextId: context,
        changes: [ObjectChange(name: 'Mara', facts: List.filled(101, fact))],
      ),
      CheckChangesRequest(
        universe: universe,
        contextId: context,
        events: List.filled(100, event),
        corrections: [
          WritingCorrection(
            factHandle: 'opaque',
            value: fact.value,
            reason: 'correct history',
          ),
        ],
      ),
    ]) {
      expect(delta.validate, invalid);
    }
    // Preserve owning validation; contracts do not invent a cap for every vector.
    CheckChangesRequest(
      universe: universe,
      contextId: context,
      definitions: List.filled(101, DefinitionChange(name: 'Type')),
    ).validate();
  });
  test(
    'fact intent validation rejects unknown statement time and empty scope',
    () {
      for (final fact in [
        FactChange(
          property: 'age',
          value: const FactTextValue('forty'),
          statement: 'guessed',
        ),
        FactChange(
          property: 'age',
          value: const FactTextValue('forty'),
          when: 'now',
        ),
        FactChange(
          property: 'age',
          value: const FactTextValue('forty'),
          scope: ' ',
        ),
      ]) {
        expect(
          CheckChangesRequest(
            universe: universe,
            contextId: context,
            changes: [
              ObjectChange(name: 'Mara', facts: [fact]),
            ],
          ).validate,
          invalid,
        );
      }
      for (final statement in [
        'objective',
        'dialogue',
        'belief',
        'plan',
        'hypothetical',
        'metaphor',
      ]) {
        CheckChangesRequest(
          universe: universe,
          contextId: context,
          changes: [
            ObjectChange(
              name: 'Mara',
              facts: [
                FactChange(
                  property: 'age',
                  value: const FactTextValue('forty'),
                  statement: statement,
                ),
              ],
            ),
          ],
        ).validate();
      }
    },
  );
  test(
    'scene reader order and depiction do not imply disclosure or story time',
    () {
      final scene = WritingScene.fromWire(
        wire(
          '{"name":"Scene","introduce":true,"work":"Memoir","edition":"First","narration_context":"Account","reader_order":18446744073709551615,"depicted_events":["opaque occurred event"]}',
        ),
      );
      expect(scene.readerOrder, BigInt.parse('18446744073709551615'));
      expect(scene.disclosures, isEmpty);
      expect(scene.viewpoint, isNull);
      expect(
        WritingScene.fromWire(scene.toWire()).readerOrder,
        scene.readerOrder,
      );
      final correction = WritingSceneCorrection(
        sceneHandle: 'opaque scene',
        reason: 'clear disclosed facts',
        depictedEvents: [],
        disclosures: [],
        clearReaderOrder: true,
      );
      expect(correction.disclosures, isEmpty);
      expect(correction.readerOrder, isNull);
      expect(
        WritingSceneCorrection(
          sceneHandle: 'opaque scene',
          reason: 'retain depiction',
        ).depictedEvents,
        isNull,
      );
      expect(
        () => WritingSceneCorrection.fromWire(
          wire(
            '{"scene_handle":"opaque","reason":"correction","reader_order":18446744073709551616}',
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'story contexts and edition bindings remain explicit authored choices',
    () {
      for (final kind in StoryContextKind.values) {
        final context = WritingStoryContext(
          name: 'Account',
          kind: kind,
          parent: 'Primary',
          calendar: 'Gregorian',
          storyTime: '1900-01-01',
        );
        expect(WritingStoryContext.fromWire(context.toWire()).kind, kind);
        expect(context.introduce, isFalse);
      }
      for (final binding in WritingEditionBinding.values) {
        final edition = WritingWorkEdition(
          work: 'Memoir',
          name: 'First',
          introduce: true,
          binding: binding,
        );
        expect(WritingWorkEdition.fromWire(edition.toWire()).binding, binding);
      }
      expect(
        () => WritingNarrativeWork.fromWire(
          wire('{"name":"Memoir","kind":"other"}'),
        ),
        throwsFormatException,
      );
    },
  );
  test('relationship roles preserve authored participant order with deep immutable copies', () {
    final children = ['Iven', 'Dara'];
    final roles = {'child': children};
    final relationship = WritingRelationship(
      relation: 'family',
      subject: 'Mara',
      participants: roles,
      scope: 'Earth',
    );
    children.clear();
    roles.clear();
    expect(relationship.participants['child'], ['Iven', 'Dara']);
    expect(relationship.participants.clear, throwsUnsupportedError);
    expect(relationship.participants['child']!.clear, throwsUnsupportedError);
    final correction = WritingRelationshipCorrection(
      relationshipHandle: 'opaque relationship',
      participants: {'child': []},
      reason: 'correct only this role',
    );
    expect(correction.participants['child'], isEmpty);
    expect(correction.participants.containsKey('parent'), isFalse);
    expect(
      WritingRelationshipCorrection.fromWire(correction.toWire())
          .participants['child'],
      isEmpty,
    );
    final empty = WritingExhaustiveSet(
      subject: 'Mara',
      property: 'children',
      members: [],
      scope: 'Earth',
    );
    expect(empty.members, isEmpty);
    expect(empty.lifetime, isA<FactUnspecifiedLifetime>());
  });
  test(
    'role multiplicity relation maxima and corrections keep separate meanings',
    () {
      final role = WritingRelationRole(name: 'child', multiple: true);
      final limit = WritingRelationLimit(
        name: 'Children',
        relation: 'family',
        grouping: WritingSubjectGrouping(),
        countedRole: 'child',
        maximum: 4294967295,
        scope: 'Earth',
      );
      expect(role.multiple, isTrue);
      expect(WritingRelationLimit.fromWire(limit.toWire()).maximum, 4294967295);
      expect(
        () => WritingRelationLimitCorrection.fromWire(
          wire(
            '{"name":"Children","reason":"correction","maximum":4294967296}',
          ),
        ),
        throwsFormatException,
      );
      final restrictions = <String>[];
      final correction = WritingRelationRoleCorrection(
        name: 'child',
        multiple: false,
        ordered: true,
        participantTypes: restrictions,
      );
      restrictions.add('Person');
      expect(correction.participantTypes, isEmpty);
      expect(
        WritingRelationRoleCorrection(name: 'child').participantTypes,
        isNull,
      );
    },
  );
  test('action effects retain exact authored numeric bounds and explicit conditions', () {
    final delta = WritingEffectChange.fromWire(
      wire('{"kind":"delta","amount":-1.00,"minimum":0.00,"maximum":1E3}'),
    ) as WritingDeltaChange;
    expect(delta.amount.digits, '-1.00');
    expect(delta.maximum.digits, '1E3');
    expect(delta.unit, isNull);
    final effect = WritingEffect(
      role: 'actor',
      property: 'stock',
      change: delta,
      lifetime: WritingTicksEffectLifetime(
        count: const CanonicalNumber('9007199254740993'),
      ),
      optional: true,
      condition: RoleValue(
        role: 'actor',
        property: 'ready',
        value: const FactBooleanValue(true),
      ),
    );
    expect(effect.optional, isTrue);
    expect(effect.condition!.property, 'ready');
    expect(
      (WritingEffect.fromWire(effect.toWire()).lifetime
              as WritingTicksEffectLifetime)
          .count
          .digits,
      '9007199254740993',
    );
    final correction = WritingActionCorrection(
      name: 'Fire',
      reason: 'explicit replacement',
      effects: [],
      requirements: [],
    );
    expect(correction.effects, isEmpty);
    expect(
      WritingActionCorrection(name: 'Fire', reason: 'retain effects').effects,
      isNull,
    );
    expect(
      () => WritingEffectChange.fromWire(
        wire('{"kind":"delta","amount":"-1","minimum":0,"maximum":8}'),
      ),
      throwsFormatException,
    );
  });
  test('initialization requires selected handles and explicit occurred start not classification', () {
    final start = WritingOccurredInstanceStart(
      event: WritingEvent(
        action: 'Manufacture',
        participants: {'instance': 'Pistol'},
      ),
    );
    final initialization = WritingInitialization(
      instance: 'Pistol',
      initialValueHandles: ['opaque approved initial value'],
      start: start,
      scope: 'Earth',
      lifetime: const FactUntilChangedLifetime(),
    );
    expect(
      WritingInitialization.fromWire(initialization.toWire()).start,
      isA<WritingOccurredInstanceStart>(),
    );
    expect(
      WritingInstanceStart.fromWire(
        wire('{"kind":"existing","handle":"opaque occurred start"}'),
      ),
      isA<WritingExistingInstanceStart>(),
    );
    expect(
      () => WritingInitialization.fromWire(
        wire(
          '{"instance":"Pistol","initial_value_handles":[],"scope":"Earth","lifetime":{"kind":"until_changed"}}',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => WritingInitialization.fromWire(
        CanonicalObject([
          ...initialization.toWire().fields,
          MapEntry('value_override', const CanonicalNumber('999')),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('deltas snapshot input families and generic response JSON keeps serde exponent form', () {
    final scenes = <WritingScene>[];
    final delta = CheckChangesRequest(
      universe: universe,
      contextId: context,
      scenes: scenes,
    );
    scenes.add(
      WritingScene(
        name: 'Scene',
        introduce: true,
        work: 'Memoir',
        edition: 'First',
        narrationContext: 'Primary',
      ),
    );
    expect(delta.scenes, isEmpty);
    expect(delta.scenes.clear, throwsUnsupportedError);
    final check = WritingCheck.fromWire(
      wire(
        '{"status":"checked","additions":[],"unchanged":[],"clarifications":[],"excluded":[],"unknowns":[],"validation":{"score":1E3}}',
      ),
    );
    expect(check.validation!.toText(), '{"score":1E3}');
    expect(check.candidateHandle, isNull);
  });
}
