import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show eventApplies;

import 'writing_projection.dart';

CanonicalObject _object(Map<String, CanonicalValue> fields) =>
    CanonicalObject(fields.entries);
CanonicalValue _text(String? value) =>
    value == null ? const CanonicalNull() : CanonicalString(value);
CanonicalValue _bool(bool? value) =>
    value == null ? const CanonicalNull() : CanonicalBool(value);
String? _first(Map<String, String> labels) => labels.isEmpty
    ? null
    : wireString(
        CanonicalObject(
          labels.entries.map((e) => MapEntry(e.key, CanonicalString(e.value))),
        ).fields.first.value,
      );

String? writingContractLabel(RecordPayload payload) => switch (payload) {
  EntityRecord(:final labels, :final names) =>
    _first(labels) ?? (names.isEmpty ? null : names.first.text),
  PropertyRecord(:final key) ||
  RelationRecord(:final key) ||
  UnitRecord(:final key) ||
  CalendarRecord(:final key) => key,
  EntityTypeRecord(:final name) => name,
  WorkRecord(:final title) => title,
  WorkVersionRecord(:final versionLabel) => versionLabel,
  SceneRecord(:final sceneId) => sceneId,
  RealmRecord(:final labels) => _first(labels),
  WorldRecord(:final selector) => selector,
  RepresentedContextRecord(:final labels, :final kind) =>
    _first(labels) ?? (kind is AuthoredContext ? kind.label : null),
  _ => null,
};

CanonicalValue _applicability(
  Applicability value,
  String? Function(RecordId) name, {
  bool omitMissing = false,
}) => switch (value) {
  UniverseApplicability() => CanonicalString('universe'),
  WorldsApplicability(:final worldIds) => _object({
    'worlds': CanonicalArray([
      for (final world in worldIds)
        if (!omitMissing ||
            name(RecordId.parse(world.value.replaceFirst('wld_', 'rec_'))) !=
                null)
          _text(name(RecordId.parse(world.value.replaceFirst('wld_', 'rec_')))),
    ]),
  }),
  _ => CanonicalString('unresolved'),
};

CanonicalValue plainWritingScope(Scope scope, String? Function(RecordId) name) {
  final applicability = _applicability(scope.applicability, name);
  return scope.realm == null
      ? applicability
      : _object({
          'applicability': applicability,
          'realm': _text(name(scope.realm!.record)),
        });
}

bool supportedWritingPolicy(RuleRecord rule) {
  if (!rule.executable ||
      rule.kind != RuleKind.physicalConstraint ||
      rule.targetPredicates.length != 1 ||
      rule.subjectTypes.isNotEmpty ||
      rule.knowledgeBoundary != null ||
      rule.knowledgePolicy != null ||
      rule.channelChronology != null ||
      rule.relationCardinality != null ||
      rule.capabilities.length != 1) {
    return false;
  }
  if (rule.capabilities.single == 'resources.accounting.v1') {
    return rule.commitPolicy == CommitPolicy.blockUnlessException &&
        rule.expression is LiteralExpr &&
        (rule.expression as LiteralExpr).value;
  }
  final expression = rule.expression;
  return rule.capabilities.single == 'opposing_evidence.v1' &&
      rule.commitPolicy == CommitPolicy.alwaysBlock &&
      expression is NoOpposingEvidenceExpr &&
      expression.subject is RecordOperand &&
      expression.context is RecordOperand &&
      expression.predicate == rule.targetPredicates.single;
}

CanonicalObject plainWritingAction(
  ActionDefinitionRecord action,
  String? Function(RecordId) name,
) {
  final effects = <CanonicalValue>[];
  for (final slot
      in action.consequenceContract?.slots ?? const <EffectSlot>[]) {
    final change = switch (slot.change) {
      SetEffect(:final polarity, :final value) => _object({
        'kind': CanonicalString('set'),
        'value': plainWritingValue(value, name) ?? const CanonicalNull(),
        'negated': CanonicalBool(polarity == Polarity.refutation),
      }),
      DeltaEffect(:final delta, :final minimum, :final maximum, :final unit) =>
        _object({
          'kind': CanonicalString('delta'),
          'amount': CanonicalNumber(delta.digits),
          'minimum': CanonicalNumber(minimum.digits),
          'maximum': CanonicalNumber(maximum.digits),
          'unit': _text(unit == null ? null : name(unit.toRecordId())),
        }),
    };
    final condition = switch (slot.condition) {
      AlwaysEffect() => const CanonicalNull(),
      AttributeEqualsEffect(:final role, :final predicate, :final value) =>
        _object({
          'role': CanonicalString(role),
          'property': _text(name(predicate.record)),
          'value': plainWritingValue(value, name) ?? const CanonicalNull(),
        }),
    };
    final lifetime = switch (slot.lifetime) {
      UntilChangedEffect() => _object({
        'kind': CanonicalString('until_changed'),
      }),
      TicksEffect(:final count) => _object({
        'kind': CanonicalString('ticks'),
        'count': CanonicalNumber(count.digits),
      }),
    };
    effects.add(
      _object({
        'role': CanonicalString(slot.target.role),
        'property': _text(name(slot.target.predicate.record)),
        'change': change,
        'condition': condition,
        'optional': CanonicalBool(slot.presence == EffectPresence.optional),
        'lifetime': lifetime,
      }),
    );
  }
  return _object({
    'name': CanonicalString(action.key),
    'requirements': CanonicalArray(
      action.requirements.map(
        (r) => _object({
          'role': CanonicalString(r.role),
          'property': _text(name(r.predicate.record)),
          'value': plainWritingValue(r.value, name) ?? const CanonicalNull(),
        }),
      ),
    ),
    'effects': CanonicalArray(effects),
    'scope': _applicability(action.scope.applicability, name),
    'time': CanonicalString(plainWritingTime(action.validity.toWire(), name)),
    'contract_declared': CanonicalBool(action.consequenceContract != null),
  });
}

/// Plain declarations only: rows must already be permission/perspective filtered.
/// No source text, depiction, receipt or authored policy becomes inferred knowledge.
CanonicalObject projectWritingContracts({
  required ReadContractsRequest request,
  required List<RecordVersion> rows,
  required Frame frame,
  required bool restricted,
  Set<RecordId> excludedRules = const {},
}) {
  final byId = {for (final row in rows) row.identity.recordId: row};
  String? name(RecordId id) =>
      byId[id] == null ? null : writingContractLabel(byId[id]!.payload);
  CanonicalValue time(Validity validity) =>
      CanonicalString(plainWritingTime(validity.toWire(), name));
  CanonicalValue temporal(TemporalExpression value) =>
      CanonicalString(plainWritingTime(value.encode(canonical: false), name));
  CanonicalValue claim(PropositionRecord p) => _object({
    'subject': _text(name(p.subject.record)),
    'property': _text(name(p.predicate.record)),
    'value': p.value == null
        ? const CanonicalNull()
        : plainWritingValue(p.value!, name) ?? const CanonicalNull(),
  });
  CanonicalValue handle(RecordVersion row) => _text(
    frame.perspective is AuthorPerspective ? row.recordVersionId.value : null,
  );
  final groups = {
    for (final key in [
      'narrative',
      'actions',
      'units',
      'knowledge_boundaries',
      'knowledge_policies',
      'channels',
      'communications',
      'attitudes',
      'constraints',
      'exhaustive_sets',
      'relations',
      'relation_limits',
      'relationships',
      'item_powers',
      'properties',
    ])
      key: <CanonicalValue>[],
  };
  final author = frame.perspective is AuthorPerspective;
  for (final row in rows) {
    final payload = row.payload;
    switch (payload) {
      case WorkRecord() when author:
        groups['narrative']!.add(
          _object({
            'kind': CanonicalString('work'),
            'name': CanonicalString(payload.title),
            'work_kind': CanonicalString(payload.kind.wireName),
          }),
        );
      case WorkVersionRecord() when author:
        final binding = switch (payload.binding) {
          BoundWork(:final revision) => _object({
            'kind': CanonicalString('bound'),
            'revision': CanonicalString(revision.value),
          }),
          UnboundWork() => _object({'kind': CanonicalString('unbound')}),
          _ => _object({
            'kind': CanonicalString('segments'),
            'limitation': CanonicalString('Advanced segment bindings.'),
          }),
        };
        groups['narrative']!.add(
          _object({
            'kind': CanonicalString('edition'),
            'work': _text(name(payload.work.record)),
            'name': CanonicalString(payload.versionLabel),
            'binding': binding,
          }),
        );
      case RepresentedContextRecord(kind: NarratorContext(:final narrator))
          when author:
        final clock = payload.chronology;
        groups['narrative']!.add(
          _object({
            'kind': CanonicalString('narrator_context'),
            'name': _text(name(row.identity.recordId)),
            'narrator': _text(name(narrator.record)),
            'narrator_handle': CanonicalString(narrator.record.value),
            'parent': _text(
              payload.parent == null ? null : name(payload.parent!.record),
            ),
            'narration_time': clock == null
                ? const CanonicalNull()
                : temporal(ExactTime(clock.calendar, clock.current)),
          }),
        );
      case SceneRecord() when author:
        final edition = rows
            .where(
              (r) =>
                  r.recordVersionId == payload.workVersion.version &&
                  r.payload is WorkVersionRecord,
            )
            .firstOrNull;
        final depicted = <CanonicalValue>[];
        for (final event in payload.depictedEvents) {
          final found = byId[event.record];
          if (found?.payload case EventRecord(
            :final action,
            time: final eventTime,
          )) {
            depicted.add(
              _object({
                'event_handle': CanonicalString(found!.recordVersionId.value),
                'action': _text(action == null ? null : name(action.record)),
                'event_time': temporal(eventTime),
              }),
            );
          }
        }
        final disclosures = <CanonicalValue>[];
        for (final ref in payload.disclosedRecords) {
          final target = byId[ref.record];
          CanonicalValue declared = const CanonicalNull();
          if (target?.payload case AssertionRecord(
            :final proposition,
            :final polarity,
          )) {
            final p = byId[proposition.record]?.payload;
            if (p is PropositionRecord) {
              declared = _object({
                ...Map.fromEntries((claim(p) as CanonicalObject).fields),
                'polarity': polarity.toWire(),
              });
            }
          }
          disclosures.add(
            _object({
              'name': _text(name(ref.record)),
              'kind': _text(target?.payload.recordKind.wireName),
              'declared_fact': declared,
            }),
          );
        }
        groups['narrative']!.add(
          _object({
            'kind': CanonicalString('scene'),
            'name': CanonicalString(payload.sceneId),
            'scene_handle': CanonicalString(row.recordVersionId.value),
            'reader_scene_handle': CanonicalString(row.identity.recordId.value),
            'edition': _text(
              edition == null
                  ? null
                  : (edition.payload as WorkVersionRecord).versionLabel,
            ),
            'reader_order': payload.narrativePosition == null
                ? const CanonicalNull()
                : CanonicalNumber(payload.narrativePosition.toString()),
            'narration_context': _text(
              payload.narrationFrame == null
                  ? null
                  : name(payload.narrationFrame!.record),
            ),
            'viewpoint': _text(
              payload.viewpoint == null
                  ? null
                  : name(payload.viewpoint!.record),
            ),
            'depicted_events': CanonicalArray(depicted),
            'disclosure_count': CanonicalNumber(
              payload.disclosedRecords.length.toString(),
            ),
            'disclosures': CanonicalArray(disclosures),
            'limitation': CanonicalString(
              'Depiction and narration never establish reader disclosure or character knowledge.',
            ),
          }),
        );
      case ActionDefinitionRecord()
          when payload.scope.context == frame.context &&
              (request.actionNames.isEmpty ||
                  request.actionNames.any(
                    (n) =>
                        n == payload.key || payload.labels.values.contains(n),
                  )):
        groups['actions']!.add(plainWritingAction(payload, name));
      case UnitRecord():
        groups['units']!.add(
          _object({
            'name': CanonicalString(payload.key),
            'symbol': CanonicalString(payload.symbol),
            'dimension': CanonicalString(payload.dimension),
            'conversion_declared': CanonicalBool(
              payload.base != null || payload.scaleToBase != null,
            ),
            'time': time(payload.validity),
          }),
        );
      case PropertyRecord() when author:
        final valueType = payload.value is EntityRefShape
            ? CanonicalString('object')
            : Map.fromEntries(payload.value.toWire().fields)['kind']!;
        final persistence = switch (payload.persistence) {
          PersistenceSemantics.persistentUntilChanged => 'until_changed',
          PersistenceSemantics.explicitInterval => 'explicit_interval',
          PersistenceSemantics.unspecified => 'unspecified',
          PersistenceSemantics.instantaneousObservation =>
            'instantaneous_observation',
          PersistenceSemantics.conditionDependent => 'condition_dependent',
        };
        groups['properties']!.add(
          _object({
            'name': CanonicalString(payload.key),
            'single_value': CanonicalBool(
              payload.multiplicity == Multiplicity.single,
            ),
            'persistence': CanonicalString(persistence),
            'value_type': valueType,
            'unit': _text(
              payload.value is QuantityShape
                  ? name((payload.value as QuantityShape).unit.toRecordId())
                  : null,
            ),
            'limitation': CanonicalString(
              'Multiplicity/persistence revisions require private contract review; value type, units and other metadata stay unchanged. Existing facts retain their explicit validity and persistence.',
            ),
          }),
        );
      case ItemPowerRecord()
          when author && payload.scope.context == frame.context:
        groups['item_powers']!.add(
          _object({
            'grant_handle': CanonicalString(row.recordVersionId.value),
            'item': _text(name(payload.item.record)),
            'holder_property': _text(name(payload.holderPredicate.record)),
            'ability_property': _text(name(payload.powerPredicate.record)),
            'value':
                plainWritingValue(payload.value, name) ?? const CanonicalNull(),
            'scope': plainWritingScope(payload.scope, name),
            'time': time(payload.validity),
            'time_applicable': _bool(
              eventApplies(payload.validity, frame.time, rows),
            ),
            'limitation': CanonicalString(
              'Declaration only; the ability applies to the holder only while explicit holder-property evidence and this declaration both apply. Ownership relations do not establish possession.',
            ),
          }),
        );
      case RelationRecord():
        groups['relations']!.add(
          _object({
            'name': CanonicalString(payload.key),
            'roles': CanonicalArray(
              payload.roles.map(
                (role) => _object({
                  'name': CanonicalString(role.name),
                  'multiple': CanonicalBool(
                    role.multiplicity == Multiplicity.multiple,
                  ),
                  'ordered': CanonicalBool(role.ordered),
                  'participant_types': CanonicalArray(
                    role.participantTypes.map((id) => _text(name(id))),
                  ),
                }),
              ),
            ),
          }),
        );
      case AssertionRecord()
          when author &&
              payload.scope.context == frame.context &&
              eventApplies(payload.validity, frame.time, rows) != false:
        final p = byId[payload.proposition.record]?.payload;
        if (p is PropositionRecord &&
            byId[p.predicate.record]?.payload is RelationRecord) {
          groups['relationships']!.add(
            _object({
              'relationship_handle': _text(
                payload.establishedBy == null &&
                        payload.attributeMode == AttributeMode.instance
                    ? row.recordVersionId.value
                    : null,
              ),
              'relation': _text(name(p.predicate.record)),
              'subject': _text(name(p.subject.record)),
              'participants': CanonicalArray(
                p.roles.map(
                  (role) => _object({
                    'role': CanonicalString(role.role),
                    'object': _text(name(role.participant.record)),
                  }),
                ),
              ),
              'polarity': payload.polarity.toWire(),
              'scope': plainWritingScope(payload.scope, name),
              'time': time(payload.validity),
              'time_applicable': _bool(
                eventApplies(payload.validity, frame.time, rows),
              ),
              'limitation': CanonicalString(
                'Authored assertion; cross-occurrence limits are checked by the engine, not inferred from these declarations.',
              ),
            }),
          );
        }
      case CompletenessRecord() when payload.scope.context == frame.context:
        final property = rows
            .where(
              (r) =>
                  r.payload is PropertyRecord &&
                  '${(r.payload as PropertyRecord).namespace}:${(r.payload as PropertyRecord).key}' ==
                      payload.predicate,
            )
            .firstOrNull;
        groups['exhaustive_sets']!.add(
          _object({
            'subject': _text(name(payload.subject.record)),
            'property': _text(
              property == null
                  ? null
                  : (property.payload as PropertyRecord).key,
            ),
            'members': CanonicalArray(
              payload.members.map((m) => _text(name(m.record))),
            ),
            'kind': CanonicalString(
              payload.completeness is ObjectiveCompleteness
                  ? 'objective'
                  : 'observer_known',
            ),
            'scope': _applicability(
              payload.scope.applicability,
              name,
              omitMissing: true,
            ),
            'time': time(payload.validity),
            'time_applicable': _bool(
              eventApplies(payload.validity, frame.time, rows),
            ),
          }),
        );
      case EpistemicAttitudeRecord():
        final p = byId[payload.proposition.record]?.payload;
        if (author && (p is! PropositionRecord || p.context != frame.context)) {
          continue;
        }
        final basis = payload.acquisition?.basis;
        groups['attitudes']!.add(
          _object({
            'attitude_handle': handle(row),
            'certainty': _text(payload.certainty),
            'holder': _text(name(payload.holder.record)),
            'attitude': CanonicalString(payload.attitude.name),
            'claim': p is PropositionRecord ? claim(p) : const CanonicalNull(),
            'time': time(payload.validity),
            'applicable': _bool(
              eventApplies(payload.validity, frame.time, rows),
            ),
            'message_handle': _text(
              basis is CommunicationKnowledge
                  ? basis.communication.record.value
                  : null,
            ),
            'limitation': CanonicalString(
              'Attributed attitude; knowledge eligibility remains subject to existing truth/acquisition evaluator.',
            ),
          }),
        );
      case CommunicationRecord()
          when !author ||
              payload.content.any(
                (ref) =>
                    byId[ref.record]?.payload is PropositionRecord &&
                    (byId[ref.record]!.payload as PropositionRecord).context ==
                        frame.context,
              ):
        groups['communications']!.add(
          _object({
            'message_handle': CanonicalString(row.identity.recordId.value),
            'message_edit_handle': handle(row),
            'channel': _text(payload.channel),
            'to': CanonicalArray(
              payload.intendedRecipients
                  .map((r) => name(r.record))
                  .whereType<String>()
                  .map(CanonicalString.new),
            ),
            'from': _text(name(payload.sender.record)),
            'received_by': CanonicalArray(
              payload.actualRecipients
                  .map((r) => name(r.record))
                  .whereType<String>()
                  .map(CanonicalString.new),
            ),
            'sent_at': temporal(payload.sentAt),
            'received_at': payload.receivedAt == null
                ? const CanonicalNull()
                : temporal(payload.receivedAt!),
            'distorted': CanonicalBool(payload.distorted),
            'claims': CanonicalArray([
              for (final ref in payload.content)
                if (byId[ref.record]?.payload is PropositionRecord)
                  _object({
                    ...Map.fromEntries(
                      (claim(
                        byId[ref.record]!.payload as PropositionRecord,
                      ) as CanonicalObject).fields,
                    ),
                    'context': _text(
                      name(
                        (byId[ref.record]!.payload as PropositionRecord)
                            .context
                            .record,
                      ),
                    ),
                  }),
            ]),
          }),
        );
      case RuleRecord():
        if (excludedRules.contains(row.identity.recordId)) {
          continue;
        }
        final cardinality = payload.relationCardinality;
        if (cardinality != null && cardinality.scope.context == frame.context) {
          groups['relation_limits']!.add(
            _object({
              'name': CanonicalString(payload.key),
              'relation': _text(name(cardinality.relation.record)),
              'grouping': cardinality.grouping.toWire(),
              'counted_role': CanonicalString(cardinality.countedRole),
              'maximum': CanonicalNumber(cardinality.maximum.toString()),
              'scope': plainWritingScope(cardinality.scope, name),
              'time': time(cardinality.validity),
              'time_applicable': _bool(
                eventApplies(cardinality.validity, frame.time, rows),
              ),
              'policy': CanonicalString('always_block'),
              'limitation': CanonicalString(
                'Distinct authored participants across overlapping relation occurrences; no inferred minimum/exclusivity, conversion or ordinary exception.',
              ),
            }),
          );
        }
        if (supportedWritingPolicy(payload)) {
          final property = rows
              .where(
                (r) =>
                    r.payload is PropertyRecord &&
                    '${(r.payload as PropertyRecord).namespace}:${(r.payload as PropertyRecord).key}' ==
                        payload.targetPredicates.first,
              )
              .firstOrNull;
          final common = {
            'policy_handle': handle(row),
            'name': CanonicalString(payload.key),
            'property': _text(
              property == null
                  ? null
                  : (property.payload as PropertyRecord).key,
            ),
            'scope': _applicability(
              payload.applicability,
              name,
              omitMissing: true,
            ),
            'time': time(payload.validity),
          };
          if (payload.capabilities.single == 'resources.accounting.v1') {
            groups['constraints']!.add(
              _object({
                ...common,
                'kind': CanonicalString('resource_accounting'),
                'limitation': CanonicalString(
                  'Exact interval stock; acceptance retains unexplained arrival and needs a separate real author decision.',
                ),
              }),
            );
          } else if (payload.expression case NoOpposingEvidenceExpr(
            subject: RecordOperand(reference: final record),
          )) {
            groups['constraints']!.add(
              _object({
                ...common,
                'kind': CanonicalString('no_opposing_evidence'),
                'object': _text(name(record.record)),
              }),
            );
          }
        }
        final boundary = payload.knowledgeBoundary;
        if (author && boundary != null && boundary.context == frame.context) {
          final p = byId[boundary.proposition.record]?.payload;
          if (p is PropositionRecord) {
            groups['knowledge_boundaries']!.add(
              _object({
                'policy_handle': CanonicalString(row.recordVersionId.value),
                'name': CanonicalString(payload.key),
                'applicable': _bool(
                  eventApplies(payload.validity, frame.time, rows),
                ),
                'holder': _text(name(boundary.holder.record)),
                'claim': claim(p),
                'scope': plainWritingScope(
                  Scope(
                    applicability: payload.applicability,
                    context: boundary.context,
                  ),
                  name,
                ),
                'time': time(payload.validity),
                'limitation': CanonicalString(
                  'Explicit absence of knowledge only; no objective truth, automatic absence, or approval waiver.',
                ),
              }),
            );
          }
        }
        final policy = payload.knowledgePolicy;
        if (policy != null && policy.context == frame.context) {
          groups['knowledge_policies']!.add(
            _object({
              'policy_handle': handle(row),
              'name': CanonicalString(payload.key),
              'mode': CanonicalString(policy.mode.wireName),
              'limitation': CanonicalString(
                policy.mode == KnowledgeMode.authorEstablished
                    ? 'Use the separate private establish_knowledge author action with selected claim, time, lifetime and rationale, followed by exact approval; source text or ordinary approval cannot manufacture it.'
                    : 'Requires actual receipt, explicit interpretation, authored channel chronology, and objective truth.',
              ),
            }),
          );
        }
        final channel = payload.channelChronology;
        if (channel != null) {
          groups['channels']!.add(
            _object({
              'policy_handle': handle(row),
              'name': CanonicalString(payload.key),
              'channel': CanonicalString(channel.channel),
              'forward_only': CanonicalBool(channel.forwardOnly),
              'minimum_delay': _text(channel.minimumDelay),
              'maximum_delay': _text(channel.maximumDelay),
            }),
          );
        }
      default:
        break;
    }
  }
  return _object({
    for (final entry in groups.entries) entry.key: CanonicalArray(entry.value),
    'coverage': CanonicalString(restricted ? 'restricted' : 'bounded'),
    'limitation': CanonicalString(
      'Visible pinned authored declarations; absent contracts are unknown. Effects are computed and checked by the engine. Interpretation alone does not establish knowledge.',
    ),
  });
}
