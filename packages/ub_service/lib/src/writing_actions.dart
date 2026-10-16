import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';
import 'writing_units.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

AttributeRequirement _role(
  UniverseId universe,
  List<RecordVersion> rows,
  Frame frame,
  RoleValue value,
) => AttributeRequirement(
  value.role,
  RecordRef(
    universe: universe,
    record: resolveWritingProperty(rows, value.property).$1.identity.recordId,
  ),
  bindWritingValue(universe, rows, frame, value.value),
);

ActionDefinitionRecord _build(
  UniverseId universe,
  List<RecordVersion> rows,
  Frame frame,
  WritingAction action,
  Set<WorldId>? worldScope,
) {
  final requirements = [
    for (final requirement in action.requirements)
      _role(universe, rows, frame, requirement),
  ];
  final slots = <EffectSlot>[];
  for (var position = 0; position < action.effects.length; position++) {
    final effect = action.effects[position];
    final (property, definition) = resolveWritingProperty(
      rows,
      effect.property,
    );
    final EffectChange change;
    switch (effect.change) {
      case WritingSetChange(:final value, :final negated):
        change = SetEffect(
          negated ? Polarity.refutation : Polarity.support,
          bindWritingValue(universe, rows, frame, value),
        );
      case WritingDeltaChange(
        :final amount,
        :final minimum,
        :final maximum,
        :final unit,
      ):
        UnitId? bound;
        switch (definition.value) {
          case SimpleValueShape(
                kind: SimpleShapeKind.integer || SimpleShapeKind.decimal,
              )
              when unit == null:
            break;
          case QuantityShape(unit: final expected):
            if (unit == null) {
              throw const FormatException(
                "Specify the quantity delta's authored unit.",
              );
            }
            bound = resolveWritingUnit(rows, unit);
            if (bound != expected) {
              throw const FormatException(
                'Quantity delta unit does not match its authored property; no conversion is inferred.',
              );
            }
          default:
            throw const FormatException(
              'Delta effects require finite decimal magnitudes with the exact authored property unit; no conversion or rounding.',
            );
        }
        change = DeltaEffect(
          delta: ConsequenceDecimal(amount.digits),
          minimum: ConsequenceDecimal(minimum.digits),
          maximum: ConsequenceDecimal(maximum.digits),
          unit: bound,
        );
    }
    final condition = effect.condition;
    final EffectCondition boundCondition;
    if (condition == null) {
      boundCondition = const AlwaysEffect();
    } else {
      final value = _role(universe, rows, frame, condition);
      boundCondition = AttributeEqualsEffect(
        value.role,
        value.predicate,
        value.value,
      );
    }
    slots.add(
      EffectSlot(
        slot: 'effect_${position + 1}',
        order: position,
        presence: effect.optional
            ? EffectPresence.optional
            : EffectPresence.required,
        target: EffectTarget(
          effect.role,
          RecordRef(universe: universe, record: property.identity.recordId),
        ),
        condition: boundCondition,
        change: change,
        lifetime: switch (effect.lifetime) {
          WritingUntilChangedEffectLifetime() => const UntilChangedEffect(),
          WritingTicksEffectLifetime(:final count) => TicksEffect(
            ConsequenceInteger(count.digits),
          ),
        },
      ),
    );
  }
  return ActionDefinitionRecord(
    namespace: 'authoring',
    key: action.name,
    labels: {},
    requirements: requirements,
    consequenceContract: ConsequenceContract(slots),
    scope: Scope(
      context: frame.context,
      applicability: bindWritingApplicability(
        rows,
        action.scope,
        worldScope: worldScope,
      ),
    ),
    validity:
        action.atTick != null || action.lifetime is! FactUnspecifiedLifetime
        ? bindWritingLifetime(
            bindWritingTime(frame, rows, action.atTick),
            action.lifetime,
          )
        : const UnspecifiedValidity(),
  );
}

/// Action declarations see the candidate; corrections locate their immutable
/// original in the pinned base. Omitted correction fields are retained exactly.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingActions({
  required UniverseId universe,
  required Frame frame,
  required List<RecordVersion> base,
  required List<RecordVersion> rows,
  required List<WritingAction> declarations,
  required List<WritingActionCorrection> corrections,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      clarifications = <String>[];
  final names = <String>{};
  void attempt(DomainOperation Function() build, String addition) {
    try {
      operations.add(build());
      additions.add(addition);
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on NotFoundOrNotAccessibleError catch (error) {
      clarifications.add(error.message);
    }
  }

  for (final action in declarations) {
    attempt(() {
      if (!action.introduce ||
          !_nonWhitespace.hasMatch(action.name) ||
          !names.add(action.name) ||
          rows.any(
            (row) =>
                row.payload is ActionDefinitionRecord &&
                ((row.payload as ActionDefinitionRecord).key == action.name ||
                    (row.payload as ActionDefinitionRecord).labels.values
                        .contains(action.name)),
          )) {
        throw const FormatException(
          'Explicitly introduce a uniquely named action; existing contracts require an explicit definition revision.',
        );
      }
      return DefineActionOperation(
        clientRef: RecordId.generate().value,
        record: _build(universe, rows, frame, action, worldScope),
      );
    }, 'New action contract: ${action.name}');
  }
  for (final patch in corrections) {
    attempt(() {
      if (!_nonWhitespace.hasMatch(patch.reason)) {
        throw const FormatException(
          'Give the reason for this action correction.',
        );
      }
      if (patch.requirements == null &&
          patch.effects == null &&
          patch.scope == null &&
          patch.atTick == null &&
          patch.lifetime == null) {
        throw const FormatException(
          'Specify the action fields to correct; omitted fields stay unchanged.',
        );
      }
      final found = [
        for (final row in base)
          if (row.payload case final ActionDefinitionRecord action)
            if (action.key == patch.name ||
                action.labels.values.contains(patch.name))
              (row, action),
      ];
      if (found.length != 1) {
        throw FormatException(
          "Which exact authored action is '${patch.name}' ?",
        );
      }
      final (original, action) = found.single;
      if ((patch.atTick != null) != (patch.lifetime != null)) {
        throw const FormatException(
          'An action validity correction requires an explicit tick and lifetime together.',
        );
      }
      if (patch.effects != null) {
        final contract = action.consequenceContract;
        if (contract == null) {
          throw const FormatException(
            'An action without a declared consequence contract requires advanced review.',
          );
        }
        for (var i = 0; i < contract.slots.length; i++) {
          if (contract.slots[i].slot != 'effect_${i + 1}' ||
              contract.slots[i].order != i) {
            throw const FormatException(
              'Editing custom effect slots/order requires advanced contract review; no authored slot metadata is discarded.',
            );
          }
        }
      }
      final other = rows
          .where((row) => row.identity.recordId != original.identity.recordId)
          .toList();
      if (other.any(
        (row) =>
            row.payload is ActionDefinitionRecord &&
            ((row.payload as ActionDefinitionRecord).key == patch.name ||
                (row.payload as ActionDefinitionRecord).labels.values.contains(
                  patch.name,
                )),
      )) {
        throw const FormatException(
          'Explicitly introduce a uniquely named action; existing contracts require an explicit definition revision.',
        );
      }
      final built = _build(
        universe,
        other,
        frame,
        WritingAction(
          name: patch.name,
          introduce: true,
          requirements: patch.requirements ?? [],
          effects: patch.effects ?? [],
          scope: patch.scope ?? 'unspecified',
          atTick: patch.atTick,
          lifetime: patch.lifetime ?? const FactUnspecifiedLifetime(),
        ),
        worldScope,
      );
      final replacement = ActionDefinitionRecord(
        namespace: action.namespace,
        key: action.key,
        labels: action.labels,
        requirements: patch.requirements == null
            ? action.requirements
            : built.requirements,
        consequenceContract: patch.effects == null
            ? action.consequenceContract
            : built.consequenceContract,
        scope: Scope(
          context: action.scope.context,
          realm: action.scope.realm,
          applicability: patch.scope == null
              ? action.scope.applicability
              : built.scope.applicability,
        ),
        validity: patch.atTick == null ? action.validity : built.validity,
      );
      return ReviseDefinitionOperation(
        record: RecordRef(
          universe: universe,
          record: original.identity.recordId,
        ),
        expectedVersion: original.recordVersionId,
        replacement: replacement,
      );
    }, 'Action contract correction: ${patch.name} — ${patch.reason}');
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
