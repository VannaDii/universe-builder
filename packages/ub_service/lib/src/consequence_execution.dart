import 'package:ub_contracts/ub_contracts.dart'
    show InvalidArgumentError, EvaluationLimitReachedError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'event.action.effects', message: message);
typedef AuthoredConsequence = (RecordId, PropositionRecord, EntityEffect);

RecordRef _owner(
  EventRecord event,
  String role,
  Map<RecordId, RecordVersion> records,
) {
  final matches = event.participants.where((p) => p.role == role).toList();
  if (matches.isEmpty) throw _invalid('effect role has no owner');
  final ref = matches.first.record, row = records[matches.first.record.record];
  if (matches.length != 1 ||
      row?.payload is! EntityRecord ||
      ref.universe != row!.identity.universeId) {
    throw _invalid('effect role must identify exactly one owning entity');
  }
  return ref;
}

ExactAmount _magnitude(DomainValue value, UnitId? unit) {
  final DomainValue amount;
  switch ((value, unit)) {
    case (IntegerValue() || DecimalValue(), null):
      amount = value;
    case (
          QuantityValue(value: final v, unit: final actual),
          final UnitId expected,
        )
        when actual == expected:
      amount = v;
    default:
      throw _invalid(
        'resource requires an exact numeric amount in the declared unit',
      );
  }
  final digits = switch (amount) {
    IntegerValue(:final digits) || DecimalValue(:final digits) => digits,
    _ => throw _invalid(
      'resource magnitude must be an exact bounded integer or finite decimal',
    ),
  };
  return ExactAmount.tryParse(digits) ??
      (throw _invalid(
        'resource amount exceeds supported exact decimal precision',
      ));
}

bool _outside(ExactAmount value, ExactAmount min, ExactAmount max) {
  final a = value.compareChecked(min);
  if (a == null) {
    throw _invalid('resource comparison exceeds exact decimal bounds');
  }
  if (a < 0) return true;
  final b = value.compareChecked(max);
  if (b == null) {
    throw _invalid('resource comparison exceeds exact decimal bounds');
  }
  return b > 0;
}

ExactAmount _balanceAfter(
  List<RecordVersion> rows,
  Map<RecordId, RecordVersion> byId,
  EventRecord event,
  EffectSlot slot,
  Frame frame,
  List<List<RecordId>> worlds,
  void Function(int) charge,
) {
  final change = slot.change;
  if (change is! DeltaEffect) throw _invalid('not a delta slot');
  final target = _owner(event, slot.target.role, byId);
  final balances = <(BigInt, int)>{};
  for (final world in worlds) {
    final supported = <(BigInt, int)>{}, refuted = <(BigInt, int)>{};
    charge(rows.length);
    for (final row in rows) {
      final a = row.payload;
      if (a is! AssertionRecord) continue;
      final p = byId[a.proposition.record]?.payload;
      if (p is! PropositionRecord ||
          p.subject != target ||
          p.predicate != slot.target.predicate ||
          p.context != frame.context ||
          a.scope.context != frame.context ||
          p.roles.isNotEmpty ||
          p.quantification != Quantification.particular) {
        continue;
      }
      final applies = switch (a.scope.applicability) {
        UniverseApplicability() => true,
        WorldsApplicability(:final worldIds) => worldIds.any(
          (w) => world.any((r) => r.value.substring(4) == w.value.substring(4)),
        ),
        _ => throw _invalid('resource scope unresolved'),
      };
      if (!applies) continue;
      switch (rules.eventApplies(a.validity, frame.time, rows)) {
        case false:
          continue;
        case null:
          throw _invalid('resource pre-event time evidence unresolved');
        case true:
          break;
      }
      if (a.scope.realm != null ||
          a.precision != Precision.exact ||
          a.alternatives.isNotEmpty) {
        throw _invalid(
          'resource pre-event evidence is uncertain or nonobjective',
        );
      }
      final n = _magnitude(
        p.value ?? (throw _invalid('resource pre-value missing')),
        change.unit,
      );
      (a.polarity == Polarity.support ? supported : refuted).add((
        n.coefficient,
        n.scale,
      ));
    }
    if (supported.length != 1 || supported.any(refuted.contains)) {
      throw _invalid(
        'resource pre-event balance missing, conflicting or ambiguous',
      );
    }
    final beforeKey = supported.single,
        before = ExactAmount(beforeKey.$1, beforeKey.$2);
    if (_outside(before, change.minimum.amount, change.maximum.amount)) {
      throw _invalid('resource pre-event balance outside declared bounds');
    }
    final after =
        before.addChecked(change.delta.amount) ??
        (throw _invalid('resource arithmetic overflow'));
    if (_outside(after, change.minimum.amount, change.maximum.amount)) {
      throw _invalid(
        'resource transition underflow or overflow of declared bounds',
      );
    }
    balances.add((after.coefficient, after.scale));
  }
  if (balances.length != 1) {
    throw _invalid('resource balance differs across event worlds');
  }
  return ExactAmount(balances.single.$1, balances.single.$2);
}

List<bool> _conditionTruths(
  List<RecordVersion> rows,
  Map<RecordId, RecordVersion> byId,
  EventRecord event,
  EffectSlot slot,
  Frame frame,
  List<List<RecordId>> worlds,
  void Function(int) charge,
) {
  final condition = slot.condition;
  if (condition is! AttributeEqualsEffect) {
    return List.filled(worlds.length, true);
  }
  final index = rules.EvaluationIndex(rows);
  final subject = _owner(event, condition.role, byId);
  final property = byId[condition.predicate.record]?.payload;
  if (property is! PropertyRecord) {
    throw _invalid('condition property unavailable');
  }
  final values = <DomainValue>[condition.value];
  for (final r in rows) {
    charge(1);
    final v = switch (r.payload) {
      PropositionRecord p
          when p.predicate == condition.predicate &&
              p.context == frame.context =>
        p.value,
      ItemPowerRecord p when p.powerPredicate == condition.predicate => p.value,
      _ => null,
    };
    if (v != null && !values.contains(v)) values.add(v);
  }
  final truths = <bool>[];
  for (final world in worlds) {
    final supported = <DomainValue>[];
    var refutedExpected = false;
    for (final value in values) {
      charge(rows.length);
      final expr = ClaimExpr(
        subject: RecordOperand(subject),
        predicate: '${property.namespace}:${property.key}',
        value: ValueOperand(value),
        polarity: Polarity.support,
      );
      final (evidence, complete) = rules.evaluateExpression(
        expr,
        rules.EvaluationContext(
          frame: frame,
          baseSnapshot: rows,
          index: index,
          worldScope: world,
        ),
      );
      if (!complete || evidence.outcome == rules.EvidenceOutcome.conflicting) {
        throw _invalid(
          'effect condition unresolved: incomplete or conflicting pre-event evidence',
        );
      }
      if (evidence.outcome == rules.EvidenceOutcome.supported) {
        supported.add(value);
      }
      if (evidence.outcome == rules.EvidenceOutcome.refuted &&
          value == condition.value) {
        refutedExpected = true;
      }
    }
    final single = property.multiplicity == Multiplicity.single;
    if (single && supported.length > 1) {
      throw _invalid(
        'effect condition unresolved: incompatible pre-event values',
      );
    }
    if (supported.contains(condition.value)) {
      truths.add(true);
    } else if (refutedExpected || single && supported.length == 1) {
      truths.add(false);
    } else {
      throw _invalid(
        'effect condition unresolved: no established pre-event truth',
      );
    }
  }
  return truths;
}

/// Realizes only explicitly authored mandatory effects. No writes or approvals.
List<AuthoredConsequence> authorActionEffects({
  required List<RecordVersion> records,
  required RecordId eventId,
  required EventRecord event,
  required ActionDefinitionRecord action,
  required Frame frame,
}) {
  final contract =
      action.consequenceContract ??
      (throw _invalid('action has no authored consequence contract'));
  final byId = {for (final r in records) r.identity.recordId: r};
  final scope = Scope(
    context: action.scope.context,
    applicability: event.worlds.isEmpty
        ? const UniverseApplicability()
        : WorldsApplicability(event.worlds),
  );
  final eventFrame = Frame(
    universe: frame.universe,
    continuity: frame.continuity,
    revision: frame.revision,
    context: scope.context,
    time: AtEventFrameTime(
      RecordRef(universe: frame.universe, record: eventId),
      EventTimeSide.before,
    ),
    perspective: frame.perspective,
    readerScene: frame.readerScene,
    personalSequence: frame.personalSequence,
  );
  final rows = [
    ...records,
    RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: frame.universe,
        recordId: eventId,
        recordKind: RecordKind.event,
      ),
      payload: event,
    ),
  ];
  final ({CalendarId calendar, BigInt coordinate}) time;
  try {
    time = rules.exactEventTime(event.time);
  } on rules.EventEvaluationError catch (e) {
    throw _invalid(e.message);
  }
  final worlds = event.worlds.isEmpty
      ? <List<RecordId>>[[]]
      : event.worlds
            .map((w) => [RecordId.parse('rec_${w.value.substring(4)}')])
            .toList();
  var remaining = 1000000;
  void charge(int cost) {
    remaining -= cost;
    if (remaining < 0) throw _invalid('consequence work budget exceeded');
  }

  final effects = <AuthoredConsequence>[];
  for (final slot in contract.slots) {
    final truths = _conditionTruths(
      rows,
      byId,
      event,
      slot,
      eventFrame,
      worlds,
      charge,
    );
    if (truths.every((v) => !v)) continue;
    if (truths.any((v) => !v)) {
      throw _invalid('condition differs across worlds');
    }
    if (slot.presence == EffectPresence.optional) {
      throw _invalid('author must specify optional action consequences');
    }
    final target = _owner(event, slot.target.role, byId);
    final Polarity polarity;
    final DomainValue value;
    switch (slot.change) {
      case SetEffect(polarity: final p, value: final v):
        polarity = p;
        value = v;
      case DeltaEffect(:final unit):
        final n = _balanceAfter(
          rows,
          byId,
          event,
          slot,
          eventFrame,
          worlds,
          charge,
        );
        final property = byId[slot.target.predicate.record]?.payload;
        final decimal =
            property is PropertyRecord &&
            property.value is SimpleValueShape &&
            (property.value as SimpleValueShape).kind ==
                SimpleShapeKind.decimal;
        final v = n.scale == 0 && !decimal
            ? IntegerValue(n.digits)
            : DecimalValue(n.digits);
        polarity = Polarity.support;
        value = unit == null ? v : QuantityValue(v, unit);
    }
    TemporalBound end = const UnboundedBound();
    if (slot.lifetime case TicksEffect(:final count)) {
      final n = time.coordinate + count.value;
      if (n < ExactAmount.minimum || n > ExactAmount.maximum) {
        throw _invalid('effect lifetime overflow');
      }
      end = ExactBound(n.toString());
    }
    final id = RecordId.generate();
    final proposition = PropositionRecord(
      subject: target,
      predicate: slot.target.predicate,
      value: value,
      context: scope.context,
      quantification: Quantification.particular,
    );
    effects.add((
      id,
      proposition,
      EntityEffect(
        slot: slot.slot,
        proposition: RecordRef(universe: frame.universe, record: id),
        polarity: polarity,
        validity: CalendarIntervalValidity(
          time.calendar,
          ExactBound(time.coordinate.toString()),
          end,
        ),
        scope: scope,
        order: BigInt.from(slot.order),
      ),
    ));
  }
  return effects;
}

/// Checks every submitted event against its contract and exact candidate state.
/// Historical undeclared events return exclusions rather than claiming coverage.
List<String> validateActionConsequences({
  required List<RecordVersion> records,
  required List<RecordVersion> base,
  required Set<RecordId> changed,
  required Frame frame,
}) {
  final byId = {for (final r in records) r.identity.recordId: r};
  var remaining = 1000000;
  void charge(int cost) {
    remaining -= cost;
    if (remaining < 0) {
      throw const EvaluationLimitReachedError(
        message: 'Consequence evaluation exceeded its work budget',
      );
    }
  }

  final exclusions = <String>[];
  final uses =
      <
        (RecordRef, RecordRef, RecordRef),
        List<
          ({List<WorldId> worlds, CalendarId calendar, BigInt tick, bool delta})
        >
      >{};
  for (final record in records) {
    charge(1);
    final p = record.payload;
    if (p is ActionDefinitionRecord &&
        changed.contains(record.identity.recordId) &&
        p.consequenceContract == null) {
      throw _invalid(
        'new or revised actions must declare a consequence contract',
      );
    }
    if (p is! EventRecord) continue;
    final action = byId[p.action?.record]?.payload;
    if (action is! ActionDefinitionRecord ||
        action.consequenceContract == null) {
      if (changed.contains(record.identity.recordId)) {
        throw _invalid(
          'new or revised events require a contract-bearing action',
        );
      }
      exclusions.add(
        'event:${record.identity.recordId.value}: historical undeclared consequences excluded',
      );
      continue;
    }
    final contract = action.consequenceContract!;
    try {
      contract.validate();
    } on FormatException catch (e) {
      throw _invalid(e.message);
    }
    if (action.scope.realm != null ||
        p.worlds.toSet().length != p.worlds.length) {
      throw _invalid(
        'contract execution requires realm-free scope and unique worlds',
      );
    }
    final worlds = p.worlds.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final scope = Scope(
      context: action.scope.context,
      applicability: worlds.isEmpty
          ? const UniverseApplicability()
          : WorldsApplicability(worlds),
    );
    final eventFrame = Frame(
      universe: frame.universe,
      continuity: frame.continuity,
      revision: frame.revision,
      context: scope.context,
      time: AtEventFrameTime(
        RecordRef(universe: frame.universe, record: record.identity.recordId),
        EventTimeSide.before,
      ),
      perspective: frame.perspective,
      readerScene: frame.readerScene,
      personalSequence: frame.personalSequence,
    );
    final queries = worlds.isEmpty
        ? <List<RecordId>>[[]]
        : worlds
              .map((w) => [RecordId.parse('rec_${w.value.substring(4)}')])
              .toList();
    final targets = <(RecordRef, RecordRef)>{};
    for (final slot in contract.slots) {
      charge(p.participants.length);
      final target = _owner(p, slot.target.role, byId);
      if (!targets.add((target, slot.target.predicate))) {
        throw _invalid('effect slots resolve to the same owner/property');
      }
      if (slot.condition case AttributeEqualsEffect(:final role)) {
        _owner(p, role, byId);
      }
    }
    final seen = <String>{};
    for (final effect in p.effects) {
      final slots = contract.slots.where((s) => s.slot == effect.slot);
      if (slots.isEmpty) {
        throw _invalid('effect slot is not permitted by the action');
      }
      final slot = slots.first;
      if (!seen.add(effect.slot)) throw _invalid('duplicate effect slot');
      final target = _owner(p, slot.target.role, byId);
      final prop = byId[effect.proposition.record]?.payload;
      if (prop is! PropositionRecord) {
        throw _invalid('effect proposition is unavailable');
      }
      var applies = effect.scope.applicability;
      if (applies is WorldsApplicability) {
        if (applies.worldIds.toSet().length != applies.worldIds.length) {
          throw _invalid('duplicate effect worlds');
        }
        final ids = applies.worldIds.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        applies = WorldsApplicability(ids);
      }
      final actualScope = Scope(
        context: effect.scope.context,
        realm: effect.scope.realm,
        applicability: applies,
      );
      if (actualScope != scope ||
          prop.context != scope.context ||
          prop.subject != target ||
          prop.predicate != slot.target.predicate ||
          prop.roles.isNotEmpty ||
          prop.quantification != Quantification.particular ||
          effect.order != BigInt.from(slot.order)) {
        throw _invalid(
          'effect must match declared owner, predicate, order, context and full event scope',
        );
      }
      if (slot.change case SetEffect(:final polarity, :final value)) {
        if (effect.polarity != polarity || prop.value != value) {
          throw _invalid(
            'effect polarity/value does not match declared assignment',
          );
        }
      }
      final time = p.time;
      if (time is! ExactTime) {
        throw _invalid('effect requires an exact named-calendar event time');
      }
      final tick =
          RegExp(r'^[+-]?[0-9]+$').stringMatch(time.value) == time.value
          ? BigInt.tryParse(time.value)
          : null;
      if (tick == null ||
          tick < ExactAmount.minimum ||
          tick > ExactAmount.maximum) {
        throw _invalid('invalid event coordinate');
      }
      TemporalBound end = const UnboundedBound();
      if (slot.lifetime case TicksEffect(:final count)) {
        final n = tick + count.value;
        if (n <= ExactAmount.minimum || n >= ExactAmount.maximum) {
          throw _invalid('effect lifetime overflow');
        }
        end = ExactBound(n.toString());
      }
      final expected = CalendarIntervalValidity(
        time.calendar,
        ExactBound(tick.toString()),
        end,
      );
      if (effect.validity != expected) {
        throw _invalid('effect lifetime must match the declared interval');
      }
    }
    if (p.occurrence is! SimpleOccurrence ||
        (p.occurrence as SimpleOccurrence).kind != OccurrenceKind.occurred) {
      continue;
    }
    for (final slot in contract.slots) {
      final present = seen.contains(slot.slot);
      final truths = _conditionTruths(
        records,
        byId,
        p,
        slot,
        eventFrame,
        queries,
        charge,
      );
      if (present && truths.any((t) => !t)) {
        throw _invalid(
          'effect supplied for a false condition in an event world',
        );
      }
      final enabled = truths.any((t) => t);
      if (!enabled && present ||
          enabled && slot.presence == EffectPresence.required && !present) {
        throw _invalid(
          'missing mandatory effect or effect supplied for a false condition',
        );
      }
      if (enabled && present) {
        final ({CalendarId calendar, BigInt coordinate}) time;
        try {
          time = rules.exactEventTime(p.time);
        } on rules.EventEvaluationError catch (e) {
          throw _invalid(e.message);
        }
        final usage = (
          worlds: p.worlds,
          calendar: time.calendar,
          tick: time.coordinate,
          delta: slot.change is DeltaEffect,
        );
        final history =
            uses[(
                  _owner(p, slot.target.role, byId),
                  slot.target.predicate,
                  action.scope.context,
                )] ??=
                [];
        for (final previous in history.where(
          (old) => usage.delta || old.delta,
        )) {
          charge(1);
          if ((usage.worlds.isEmpty ||
                  previous.worlds.isEmpty ||
                  usage.worlds.any(previous.worlds.contains)) &&
              (usage.calendar != previous.calendar ||
                  usage.tick == previous.tick)) {
            throw _invalid(
              'dependent resource uses require distinct times on the same named calendar',
            );
          }
        }
        history.add(usage);
      }
      if (enabled && present && slot.change is DeltaEffect) {
        final change = slot.change as DeltaEffect;
        final effect = p.effects.firstWhere((e) => e.slot == slot.slot);
        final post = byId[effect.proposition.record]?.payload;
        if (post is! PropositionRecord) {
          throw _invalid('resource post-value unavailable');
        }
        if (effect.polarity != Polarity.support) {
          throw _invalid('resource effects must support the proposed balance');
        }
        final proposed = _magnitude(
          post.value ?? (throw _invalid('resource post-value missing')),
          change.unit,
        );
        final expected = _balanceAfter(
          records,
          byId,
          p,
          slot,
          eventFrame,
          queries,
          charge,
        );
        if (proposed.coefficient != expected.coefficient ||
            proposed.scale != expected.scale) {
          throw _invalid(
            'resource post-value does not equal pre-value plus declared change',
          );
        }
      }
    }
  }
  for (final old in base) {
    final next = byId[old.identity.recordId]?.payload;
    if (old.payload
        case ActionDefinitionRecord(consequenceContract: ConsequenceContract())
        when next is ActionDefinitionRecord &&
            next.consequenceContract == null) {
      throw _invalid('a contracted action cannot discard its contract');
    }
  }
  return exclusions;
}
