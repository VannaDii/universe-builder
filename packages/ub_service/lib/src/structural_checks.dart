import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart'
    show InvalidArgumentError, UnsupportedSemanticsError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/ub_store.dart' show validateImageMetadata;

import 'cardinality_checks.dart';
import 'communication_checks.dart';
import 'knowledge_boundaries.dart';
import 'knowledge_checks.dart';
import 'provenance_checks.dart';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'candidate', message: message);
final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
bool _blank(String text) => !_nonWhitespace.hasMatch(text);
int _bytes(String text) => utf8.encode(text).length;
RecordId _alias(TypedId id, int prefix) =>
    RecordId.parse('rec_${id.value.substring(prefix)}');

bool valueConformsToShape(DomainValue value, ValueShape shape) => switch ((
  value,
  shape,
)) {
  (TextValue(), SimpleValueShape(kind: SimpleShapeKind.text)) ||
  (BooleanValue(), SimpleValueShape(kind: SimpleShapeKind.boolean)) ||
  (IntegerValue(), SimpleValueShape(kind: SimpleShapeKind.integer)) ||
  (DecimalValue(), SimpleValueShape(kind: SimpleShapeKind.decimal)) ||
  (RationalValue(), SimpleValueShape(kind: SimpleShapeKind.rational)) ||
  (TemporalValue(), SimpleValueShape(kind: SimpleShapeKind.temporal)) ||
  (SpatialValue(), SimpleValueShape(kind: SimpleShapeKind.spatial)) ||
  (ReferenceValue(kind: ValueReferenceKind.entity), EntityRefShape()) => true,
  (QuantityValue(unit: final a), QuantityShape(unit: final b)) => a == b,
  (RangeValue(unit: final a), RangeShape(unit: final b)) => a == b,
  (EnumValue(definition: final a), EnumShape(definition: final b)) ||
  (
    StructuredValue(definition: final a),
    StructuredShape(definition: final b),
  ) => a == b,
  (SequenceValue(:final items), SequenceShape(:final item)) => items.every(
    (v) => valueConformsToShape(v, item),
  ),
  _ => false,
};

void _actionContract(
  ActionDefinitionRecord action,
  UniverseId universe,
  Map<RecordId, RecordPayload> map,
) {
  final contract = action.consequenceContract;
  if (contract == null) return;
  try {
    contract.validate();
  } on FormatException catch (e) {
    throw _invalid(e.message);
  }
  PropertyRecord property(RecordRef ref) {
    if (ref.universe != universe) {
      throw _invalid('consequence property must name the action universe');
    }
    final p = map[ref.record];
    if (p is! PropertyRecord) {
      throw _invalid('consequence predicate must resolve to a property');
    }
    return p;
  }

  for (final slot in contract.slots) {
    final target = property(slot.target.predicate);
    if (slot.condition case AttributeEqualsEffect(
      :final predicate,
      :final value,
    )) {
      if (!valueConformsToShape(value, property(predicate).value)) {
        throw _invalid(
          'consequence condition value does not conform to its property',
        );
      }
    }
    switch (slot.change) {
      case SetEffect(:final value):
        if (!valueConformsToShape(value, target.value)) {
          throw _invalid(
            'consequence set value does not conform to its property',
          );
        }
      case DeltaEffect(
        :final unit,
        :final delta,
        :final minimum,
        :final maximum,
      ):
        final matches = switch ((target.value, unit)) {
          (SimpleValueShape(kind: SimpleShapeKind.integer), null) => [
            delta,
            minimum,
            maximum,
          ].every((n) => n.amount.scale == 0),
          (SimpleValueShape(kind: SimpleShapeKind.decimal), null) => true,
          (QuantityShape(unit: final expected), final UnitId actual)
              when expected == actual =>
            map[_alias(actual, UnitId.prefix.length)] is UnitRecord,
          _ => false,
        };
        if (target.multiplicity != Multiplicity.single || !matches) {
          throw _invalid(
            'consequence delta requires a single integer/decimal or exact-unit quantity property',
          );
        }
    }
  }
}

/// Checks the complete candidate's structure; no conflict, authorization or
/// approval is inferred from passing this function.
void validateStructuralCandidate(List<RecordVersion> records) {
  try {
    checkTemporalOrderings(records);
  } on TemporalOrderingError catch (e) {
    throw _invalid(e.message);
  }
  try {
    verifyEventEffects(records);
  } on EventEvaluationError catch (e) {
    throw _invalid(e.message);
  }
  final map = {for (final r in records) r.identity.recordId: r.payload};
  final actionNames = <(String, String)>{};
  for (final record in records) {
    final p = record.payload;
    validateProvenanceLinks(p, map);
    switch (p) {
      case ActionDefinitionRecord a:
        if (!actionNames.add((a.namespace, a.key))) {
          throw _invalid('duplicate action namespace/key');
        }
        if (_blank(a.namespace) ||
            _blank(a.key) ||
            _bytes(a.namespace) > 128 ||
            _bytes(a.key) > 128 ||
            a.requirements.length > 64 ||
            a.scope.realm != null ||
            a.scope.applicability is! UniverseApplicability &&
                a.scope.applicability is! WorldsApplicability) {
          throw _invalid(
            'action needs a bounded name, explicit scope and supported requirements',
          );
        }
        _actionContract(a, record.identity.universeId, map);
        final seen = <(String, RecordRef)>{};
        for (final req in a.requirements) {
          final d = map[req.predicate.record];
          if (_blank(req.role) ||
              _bytes(req.role) > 120 ||
              !seen.add((req.role, req.predicate)) ||
              d is! PropertyRecord ||
              !valueConformsToShape(req.value, d.value)) {
            throw _invalid(
              'action attributes need unique roles/properties and conforming values',
            );
          }
          req.value.validate();
        }
        if (map[a.scope.context.record] is! RepresentedContextRecord) {
          throw _invalid('action needs a represented context');
        }
      case ImageAssetRecord asset:
        validateImageMetadata(asset);
      case AppearanceRecord a:
        if (_blank(a.label) ||
            _bytes(a.label) > 256 ||
            _bytes(a.physicalDescription) > 64000 ||
            _bytes(a.atmosphere) > 16000 ||
            a.images.length > 16 ||
            a.links.length > 32 ||
            _blank(a.physicalDescription) &&
                _blank(a.atmosphere) &&
                a.images.isEmpty &&
                a.links.isEmpty) {
          throw _invalid(
            'appearance needs content within description, image and link limits',
          );
        }
        if (a.target case EntryAppearance(:final entry)) {
          if (!map.containsKey(entry.record)) {
            throw _invalid('appearance target unavailable');
          }
        }
        for (final image in a.images) {
          if (_bytes(image.caption) > 2000 ||
              map[image.asset.record] is! ImageAssetRecord) {
            throw _invalid(
              'appearance image must reference an imported image asset',
            );
          }
        }
        for (final link in a.links) {
          if (_bytes(link.note) > 2000 || !map.containsKey(link.entry.record)) {
            throw _invalid('appearance link unavailable or note exceeds limit');
          }
        }
        if (a.validity case CalendarIntervalValidity(
          :final calendar,
          :final start,
          :final end,
        )) {
          IntervalTime(calendar, start, end).validate();
          if (temporalOverlaps(a.validity, a.validity) != true) {
            throw _invalid(
              'appearance interval must have exact increasing or explicitly unbounded endpoints',
            );
          }
          if (map[_alias(calendar, CalendarId.prefix.length)]
              is! CalendarRecord) {
            throw _invalid(
              'appearance interval needs a known calendar and increasing boundaries',
            );
          }
        } else if (a.validity is! UnspecifiedValidity) {
          throw _invalid(
            'appearance supports unspecified or exact calendar interval validity',
          );
        }
      case RepresentedContextRecord c:
        final seen = <RecordId>{record.identity.recordId};
        var parent = c.parent;
        while (parent != null) {
          if (seen.length >= 32 || !seen.add(parent.record)) {
            throw _invalid(
              'represented-context nesting is cyclic or exceeds 32 levels',
            );
          }
          final ancestor = map[parent.record];
          if (ancestor is! RepresentedContextRecord) {
            throw _invalid('context parent must be a represented context');
          }
          parent = ancestor.parent;
        }
        if (c.chronology case final clock?) {
          try {
            clock.validate();
          } on FormatException catch (e) {
            throw _invalid(e.message);
          }
          if (map[_alias(clock.calendar, CalendarId.prefix.length)]
              is! CalendarRecord) {
            throw _invalid('story clock must reference a calendar definition');
          }
        }
      case RuleRecord r
          when r.kind == RuleKind.structuralInvariant &&
              r.commitPolicy != CommitPolicy.alwaysBlock:
        throw _invalid('structural invariants cannot be waived');
      case ItemPowerRecord p:
        if (map[p.item.record] is! EntityRecord) {
          throw _invalid('power item must be an entity');
        }
        final holder = map[p.holderPredicate.record],
            power = map[p.powerPredicate.record];
        if (holder is! PropertyRecord ||
            holder.value is! EntityRefShape ||
            holder.multiplicity != Multiplicity.single) {
          throw _invalid(
            'possession requires a single-valued entity-reference holder property',
          );
        }
        if (power is! PropertyRecord ||
            !valueConformsToShape(p.value, power.value)) {
          throw _invalid('power value must conform to its property');
        }
        if (p.scope.applicability is! UniverseApplicability &&
            p.scope.applicability is! WorldsApplicability) {
          throw _invalid('item power scope must be explicit');
        }
        p.value.validate();
      case EventRecord e:
        if (e.worlds.any(
          (w) => map[_alias(w, WorldId.prefix.length)] is! WorldRecord,
        )) {
          throw _invalid('event world is not a world');
        }
        if (e.region != null &&
            map[e.region!.record] is! EntityRecord &&
            map[e.region!.record] is! RealmRecord) {
          throw _invalid('event region must be an entity or realm');
        }
      case EpistemicAttitudeRecord a:
        if (map[a.holder.record] is! EntityRecord ||
            map[a.proposition.record] is! PropositionRecord) {
          throw _invalid('attitude requires a holder and a proposition');
        }
        if (a.acquisition case final acquisition?) {
          if (map[acquisition.truthContext.record]
                  is! RepresentedContextRecord ||
              acquisition.world != null &&
                  map[acquisition.world!.record] is! WorldRecord) {
            throw _invalid('knowledge truth context/world has the wrong kind');
          }
          if (acquisition.basis case CommunicationKnowledge(
            :final communication,
            :final interpretation,
          )) {
            if (map[communication.record] is! CommunicationRecord ||
                interpretation != null &&
                    map[interpretation.record] is! PropositionRecord) {
              throw _invalid(
                'knowledge receipt/interpretation has the wrong kind',
              );
            }
          }
        }
      case ObservationRecord o:
        if (map[o.observer.record] is! EntityRecord) {
          throw _invalid('observer must be an entity');
        }
      case CommunicationRecord c:
        if ([
          c.sender,
          ...c.intendedRecipients,
          ...c.actualRecipients,
        ].any((r) => map[r.record] is! EntityRecord)) {
          throw _invalid(
            'communication sender and recipients must be entities',
          );
        }
        if (c.actualRecipients.isNotEmpty && c.receivedAt == null) {
          throw _invalid(
            'actual communication receipt requires a receipt time',
          );
        }
      case RuleRecord rule:
        validateChannelChronologyRule(rule);
        validateKnowledgeRule(rule);
        validateKnowledgeBoundaryRule(rule, records);
        validateCardinalityRule(rule, records);
        if (rule.knowledgePolicy != null &&
            map[rule.knowledgePolicy!.context.record]
                is! RepresentedContextRecord) {
          throw _invalid(
            'knowledge policy context must be a represented context',
          );
        }
        for (final id in rule.subjectTypes) {
          if (map[id] is! EntityTypeRecord) {
            throw _invalid('rule subject type must resolve to a definition');
          }
        }
      case EntityRecord e:
        if (e.classification != null &&
            map[e.classification] is! EntityTypeRecord) {
          throw _invalid('entity type target is not an entity type');
        }
        for (final value in e.metadata.values) {
          value.validate();
        }
        for (final association in e.worldAssociations) {
          for (final v in association.qualifiers.values) {
            v.validate();
          }
        }
      case WorldRecord w:
        for (final value in w.metadata.values) {
          value.validate();
        }
      case SagaRecord s:
        final memberships = <(RecordId, String)>{};
        for (final m in s.memberships) {
          if (map[m.work.record] is! WorkRecord) {
            throw _invalid('saga membership must name a work');
          }
          if (!memberships.add((m.work.record, m.role))) {
            throw _invalid('duplicate saga work/role membership');
          }
        }
      case WorkVersionRecord w:
        if (map[w.work.record] is! WorkRecord) {
          throw _invalid('work version must name a work');
        }
      case PropositionRecord p:
        if (map[p.subject.record] is! EntityRecord &&
            map[p.subject.record] is! EntityTypeRecord) {
          throw _invalid(
            'proposition subject must be an instance or definition',
          );
        }
        if (map[p.context.record] is! RepresentedContextRecord) {
          throw _invalid('proposition context must be a represented context');
        }
        switch (map[p.predicate.record]) {
          case PropertyRecord property:
            final value = p.value;
            if (value == null) {
              throw _invalid('property proposition needs an explicit value');
            }
            value.validate();
            if (!valueConformsToShape(value, property.value) ||
                p.roles.isNotEmpty) {
              throw _invalid(
                'property value does not conform to its definition',
              );
            }
            if (definitionMatches(
                  p.subject.record,
                  property.subjectTypes,
                  records,
                  null,
                ) ==
                false) {
              throw _invalid('subject lacks a declared property type');
            }
          case RelationRecord relation:
            if (p.value != null) {
              throw _invalid(
                'relation proposition cannot carry a property value',
              );
            }
            for (final role in p.roles) {
              RoleDefinition? def;
              for (final d in relation.roles) {
                if (d.name == role.role) {
                  def = d;
                  break;
                }
              }
              if (def == null) throw _invalid('undefined relation role');
              if (map[role.participant.record] is! EntityRecord) {
                throw _invalid('role participant must be an entity');
              }
              if (definitionMatches(
                    role.participant.record,
                    def.participantTypes,
                    records,
                    null,
                  ) ==
                  false) {
                throw _invalid('participant lacks a declared role type');
              }
            }
            for (final role in relation.roles) {
              if (role.multiplicity == Multiplicity.single &&
                  p.roles.where((r) => r.role == role.name).length > 1) {
                throw _invalid('single role has multiple participants');
              }
            }
          default:
            throw _invalid(
              'proposition predicate must name a property or relation definition',
            );
        }
      case AssertionRecord a:
        if (a.validity case CalendarIntervalValidity(
          :final calendar,
          :final start,
          :final end,
        )) {
          IntervalTime(calendar, start, end).validate();
          if (start is ExactBound && end is ExactBound) {
            final integer = RegExp(r'^[+-]?[0-9]+$');
            final x = integer.hasMatch(start.value)
                    ? BigInt.tryParse(start.value)
                    : null,
                y = integer.hasMatch(end.value)
                    ? BigInt.tryParse(end.value)
                    : null;
            final min = -(BigInt.one << 127),
                max = (BigInt.one << 127) - BigInt.one;
            if (x != null &&
                y != null &&
                x >= min &&
                x <= max &&
                y >= min &&
                y <= max &&
                x > y) {
              throw _invalid('interval start is after its end');
            }
          }
        }
        if (map[a.proposition.record] is! PropositionRecord) {
          throw _invalid('assertion must name a proposition');
        }
        if (map[a.scope.context.record] is! RepresentedContextRecord) {
          throw _invalid('assertion context must be represented');
        }
        if (a.basis is DerivationBasis || a.basis is EventEffectBasis) {
          throw UnsupportedSemanticsError(
            message: 'event and derived evidence require their evaluator',
          );
        }
        for (final value in a.alternatives) {
          value.validate();
        }
      default:
        break;
    }
  }
}
