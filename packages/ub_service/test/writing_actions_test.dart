import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'action_checks_test.dart' as a;
import 'writing_units_test.dart' as units;

PropertyRecord property(String key, ValueShape shape) => PropertyRecord(
  namespace: 'test',
  key: key,
  labels: {},
  value: shape,
  multiplicity: Multiplicity.single,
  persistence: PersistenceSemantics.persistentUntilChanged,
  exclusive: false,
  symmetric: false,
  transitive: false,
);
List<RecordVersion> rows() => [
  ...a.fixture().where((row) => row.payload is! EventRecord),
  f.row(7, property('stock', const SimpleValueShape(SimpleShapeKind.integer))),
  f.row(8, property('distance', QuantityShape(UnitId.fromRecordId(f.id(9))))),
  f.row(9, units.unit()),
  f.row(12, units.unit(key: 'foot', symbol: 'ft')),
  f.row(
    50,
    WorldRecord(
      selector: 'Ashen',
      labels: {},
      metadata: {},
      aliases: ['Ashen world'],
    ),
  ),
];
WritingEffect delta({
  String property = 'stock',
  String? unit,
  String amount = '9007199254740993',
}) => WritingEffect(
  role: 'actor',
  property: property,
  optional: true,
  condition: RoleValue(
    role: 'actor',
    property: 'charged',
    value: const FactBooleanValue(true),
  ),
  change: WritingDeltaChange(
    amount: CanonicalNumber(amount),
    minimum: const CanonicalNumber('0'),
    maximum: const CanonicalNumber('9007199254740994'),
    unit: unit,
  ),
  lifetime: WritingUntilChangedEffectLifetime(),
);
WritingAction action({
  String name = 'Spend',
  List<WritingEffect>? effects,
  String scope = 'universe',
  bool introduce = true,
}) => WritingAction(
  name: name,
  introduce: introduce,
  requirements: [
    RoleValue(
      role: 'actor',
      property: 'charged',
      value: const FactBooleanValue(true),
    ),
  ],
  effects: effects ?? [delta()],
  scope: scope,
);

void main() {
  test(
    'exact ordered optional and conditional effects compile without execution',
    () {
      final base = rows();
      final result = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: base,
        rows: base,
        declarations: [
          action(
            effects: [
              delta(),
              WritingEffect(
                role: 'actor',
                property: 'charged',
                change: WritingSetChange(
                  value: const FactBooleanValue(false),
                  negated: true,
                ),
                lifetime: WritingTicksEffectLifetime(
                  count: const CanonicalNumber('2'),
                ),
              ),
            ],
          ),
        ],
        corrections: [],
      );
      expect(result.clarifications, isEmpty);
      expect(result.additions, ['New action contract: Spend']);
      final compiled = compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: base,
        operations: result.operations,
      );
      expect(compiled, hasLength(base.length + 1));
      final definition =
          compiled
                  .singleWhere(
                    (r) =>
                        r.identity.recordId ==
                        RecordId.parse(
                          (result.operations.single as DefineActionOperation)
                              .clientRef,
                        ),
                  )
                  .payload
              as ActionDefinitionRecord;
      expect(definition.requirements.single.predicate, f.ref(2));
      expect(definition.validity, isA<UnspecifiedValidity>());
      expect(definition.scope, a.scope);
      final slots = definition.consequenceContract!.slots;
      expect(slots.map((s) => s.slot), ['effect_1', 'effect_2']);
      expect(slots.map((s) => s.order), [0, 1]);
      expect(slots.first.presence, EffectPresence.optional);
      expect(
        (slots.first.condition as AttributeEqualsEffect).predicate,
        f.ref(2),
      );
      expect(
        (slots.first.change as DeltaEffect).delta.digits,
        '9007199254740993',
      );
      expect((slots.last.change as SetEffect).polarity, Polarity.refutation);
      expect((slots.last.lifetime as TicksEffect).count.digits, '2');
      for (final original in base) {
        expect(
          compiled
              .singleWhere(
                (r) => r.identity.recordId == original.identity.recordId,
              )
              .payload,
          original.payload,
        );
      }
    },
  );

  test('quantity deltas require exact authored units and world lookup remains scoped', () {
    final base = rows();
    final valid = compileWritingActions(
      universe: f.u,
      frame: a.frame,
      base: base,
      rows: base,
      declarations: [
        action(
          effects: [delta(property: 'distance', unit: 'm')],
          scope: ' ashen WORLD ',
        ),
      ],
      corrections: [],
    );
    expect(valid.clarifications, isEmpty);
    expect(
      compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: base,
        operations: valid.operations,
      ),
      hasLength(base.length + 1),
    );
    final definition =
        (valid.operations.single as DefineActionOperation).record;
    expect(
      definition.scope.applicability,
      WorldsApplicability([WorldId.parse('wld_${f.suffix(50)}')]),
    );
    expect(
      (definition.consequenceContract!.slots.single.change as DeltaEffect).unit,
      UnitId.fromRecordId(f.id(9)),
    );
    for (final effect in [
      delta(property: 'distance'),
      delta(property: 'distance', unit: 'ft'),
      delta(unit: 'm'),
      delta(property: 'charged'),
      delta(amount: '1e20'),
    ]) {
      final denied = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: base,
        rows: base,
        declarations: [
          action(effects: [effect]),
        ],
        corrections: [],
      );
      expect(denied.operations, isEmpty);
      expect(denied.clarifications, hasLength(1));
    }
    final restricted = compileWritingActions(
      universe: f.u,
      frame: a.frame,
      base: base,
      rows: base,
      declarations: [action(scope: 'Ashen')],
      corrections: [],
      worldScope: {},
    );
    expect(restricted.operations, isEmpty);
    expect(restricted.clarifications, hasLength(1));
    final duplicate = compileWritingActions(
      universe: f.u,
      frame: a.frame,
      base: base,
      rows: base,
      declarations: [
        action(),
        action(),
        action(introduce: false),
        action(name: '\u2003'),
      ],
      corrections: [],
    );
    expect(duplicate.operations, hasLength(1));
    expect(duplicate.clarifications, hasLength(3));
  });

  test(
    'corrections pin originals and retain omitted metadata contracts and scope',
    () {
      final base = rows();
      final introduced = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: base,
        rows: base,
        declarations: [action()],
        corrections: [],
      );
      final candidate = compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: base,
        operations: introduced.operations,
      );
      final original = candidate.singleWhere(
        (r) =>
            r.payload is ActionDefinitionRecord &&
            (r.payload as ActionDefinitionRecord).key == 'Spend',
      );
      final withMetadata = f.row(
        70,
        f.patch<ActionDefinitionRecord>(
          original.payload as ActionDefinitionRecord,
          {
            'namespace': CanonicalString('campaign'),
            'labels': CanonicalObject([
              MapEntry('en', CanonicalString('Expend')),
            ]),
          },
        ),
      );
      final pinned = [...base, withMetadata];
      final corrected = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: pinned,
        rows: pinned,
        declarations: [],
        corrections: [
          WritingActionCorrection(
            name: 'Expend',
            reason: 'No precondition',
            requirements: [],
          ),
        ],
      );
      expect(corrected.clarifications, isEmpty);
      final clearedEffects = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: pinned,
        rows: pinned,
        declarations: [],
        corrections: [
          WritingActionCorrection(
            name: 'Expend',
            reason: 'Remove declared effects',
            effects: [],
          ),
        ],
      );
      expect(clearedEffects.clarifications, isEmpty);
      final cleared =
          (clearedEffects.operations.single as ReviseDefinitionOperation)
                  .replacement
              as ActionDefinitionRecord;
      expect(cleared.consequenceContract!.slots, isEmpty);
      expect(
        cleared.requirements.map((r) => r.toWire().toText()),
        (withMetadata.payload as ActionDefinitionRecord).requirements.map(
          (r) => r.toWire().toText(),
        ),
      );
      final operation =
          corrected.operations.single as ReviseDefinitionOperation;
      expect(operation.expectedVersion, withMetadata.recordVersionId);
      expect(
        operation.replacement,
        f.patch<ActionDefinitionRecord>(
          withMetadata.payload as ActionDefinitionRecord,
          {'requirements': CanonicalArray([])},
        ),
      );
      final changed = compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: pinned,
        operations: corrected.operations,
      );
      expect(
        changed
            .singleWhere((r) => r.identity.recordId == f.id(70))
            .recordVersionId,
        isNot(withMetadata.recordVersionId),
      );
      expect(
        () => compileWritingCandidate(
          universe: f.u,
          revision: f.revision,
          base: changed,
          operations: corrected.operations,
        ),
        throwsA(isA<InvalidArgumentError>()),
      );
      final exactFrame = Frame(
        universe: a.frame.universe,
        continuity: a.frame.continuity,
        revision: a.frame.revision,
        context: a.frame.context,
        perspective: a.frame.perspective,
        time: AtFrameTime(ExactTime(a.cal, '10')),
      );
      final timeCorrection = compileWritingActions(
        universe: f.u,
        frame: exactFrame,
        base: pinned,
        rows: pinned,
        declarations: [],
        corrections: [
          WritingActionCorrection(
            name: 'Spend',
            reason: 'Set period',
            atTick: '12',
            lifetime: const FactUntilLifetime(endTick: '20'),
            scope: 'Ashen',
          ),
        ],
      );
      expect(timeCorrection.clarifications, isEmpty);
      final timed =
          (timeCorrection.operations.single as ReviseDefinitionOperation)
                  .replacement
              as ActionDefinitionRecord;
      expect(
        timed.validity,
        CalendarIntervalValidity(
          a.cal,
          const ExactBound('12'),
          const ExactBound('20'),
        ),
      );
      expect(
        timed.scope.applicability,
        WorldsApplicability([WorldId.parse('wld_${f.suffix(50)}')]),
      );
      expect(
        timed.consequenceContract!.toWire().toText(),
        (withMetadata.payload as ActionDefinitionRecord).consequenceContract!
            .toWire()
            .toText(),
      );
      final unpinned = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: base,
        rows: candidate,
        declarations: [],
        corrections: [
          WritingActionCorrection(
            name: 'Spend',
            reason: 'Unpinned',
            requirements: [],
          ),
        ],
      );
      expect(unpinned.operations, isEmpty);
      expect(
        unpinned.clarifications.single,
        contains('Which exact authored action'),
      );
    },
  );

  test(
    'legacy slot metadata and incomplete corrections require clarification',
    () {
      final base = rows();
      final legacy = base.singleWhere((r) => r.identity.recordId == f.id(5));
      final result = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: base,
        rows: base,
        declarations: [],
        corrections: [
          WritingActionCorrection(name: 'charged_action', reason: 'No change'),
          WritingActionCorrection(
            name: 'charged_action',
            reason: '',
            requirements: [],
          ),
          WritingActionCorrection(
            name: 'charged_action',
            reason: 'Incomplete time',
            atTick: '10',
          ),
          WritingActionCorrection(
            name: 'charged_action',
            reason: 'Replace legacy effects',
            effects: [],
          ),
        ],
      );
      expect(result.operations, isEmpty);
      expect(result.clarifications, hasLength(4));
      expect(result.clarifications.last, contains('advanced review'));
      final declared =
          (compileWritingActions(
                    universe: f.u,
                    frame: a.frame,
                    base: base,
                    rows: base,
                    declarations: [action()],
                    corrections: [],
                  ).operations.single
                  as DefineActionOperation)
              .record;
      final slot = declared.consequenceContract!.slots.single;
      final renamed = f.row(
        71,
        ActionDefinitionRecord(
          namespace: declared.namespace,
          key: declared.key,
          labels: {},
          requirements: declared.requirements,
          scope: declared.scope,
          validity: declared.validity,
          consequenceContract: ConsequenceContract([
            EffectSlot(
              slot: 'authored_slot',
              order: 0,
              presence: slot.presence,
              target: slot.target,
              condition: slot.condition,
              change: slot.change,
              lifetime: slot.lifetime,
            ),
          ]),
        ),
      );
      final cannotDiscard = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: [...base, renamed],
        rows: [...base, renamed],
        declarations: [],
        corrections: [
          WritingActionCorrection(
            name: 'Spend',
            reason: 'Replace',
            effects: [],
          ),
        ],
      );
      expect(cannotDiscard.operations, isEmpty);
      expect(
        cannotDiscard.clarifications.single,
        contains('no authored slot metadata is discarded'),
      );
      final allowed = compileWritingActions(
        universe: f.u,
        frame: a.frame,
        base: base,
        rows: base,
        declarations: [],
        corrections: [
          WritingActionCorrection(
            name: 'charged_action',
            reason: 'Update requirements',
            requirements: [],
          ),
        ],
      );
      expect(allowed.clarifications, isEmpty);
      expect(
        ((allowed.operations.single as ReviseDefinitionOperation).replacement
                as ActionDefinitionRecord)
            .consequenceContract,
        isNull,
      );
      expect(legacy.recordVersionId, f.ver(5));
    },
  );
}
