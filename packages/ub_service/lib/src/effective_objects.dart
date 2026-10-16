import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' hide EvidenceOutcome;

import 'resource_checks.dart';

bool? _combine(bool? a, bool? b) => a == false || b == false
    ? false
    : a == true && b == true
    ? true
    : null;
ObjectEvidence _evidence(
  RecordVersion record,
  List<(String, bool?)> checks, {
  Iterable<String> extra = const [],
}) {
  bool? applies = true;
  for (final (_, check) in checks) {
    applies = _combine(applies, check);
  }
  return ObjectEvidence(
    record: record,
    applicability: applies,
    unknowns: [
      for (final (name, check) in checks)
        if (check == null) name,
      ...extra,
    ],
  );
}

List<(String, bool?)> _scoped(
  Scope scope,
  Frame frame,
  List<RecordId> worlds,
) => [
  ('world_applicability', worldApplies(scope.applicability, worlds)),
  ('represented_context', scope.context == frame.context),
  ('realm_applicability', scope.realm == null ? true : null),
];
bool _sameRoles(PropositionRecord a, PropositionRecord b) =>
    a.roles.length == b.roles.length &&
    Iterable<int>.generate(a.roles.length).every(
      (i) =>
          a.roles[i].role == b.roles[i].role &&
          a.roles[i].participant == b.roles[i].participant,
    );

/// The caller owns snapshot selection and permission filtering. Assembly never
/// grants access, establishes absent instance facts or chooses winning evidence.
List<EffectiveObject> assembleEffectiveObjects({
  required List<RecordVersion> records,
  required List<RecordId> ids,
  List<RecordId> predicates = const [],
  required Frame frame,
  WorldId? world,
  required bool restricted,
  Set<RecordId> excludedRules = const {},
}) {
  final worlds = <RecordId>[
    if (world != null)
      RecordId.parse('rec_${world.value.substring(WorldId.prefix.length)}'),
  ];
  final index = RecordIndex(records);
  final assertionsBySubject = <RecordId, List<int>>{},
      sharedPositions = <int>[];
  for (var i = 0; i < records.length; i++) {
    final p = records[i].payload;
    if (p is AssertionRecord) {
      final prop = index.get(p.proposition.record)?.payload;
      if (prop is PropositionRecord) {
        assertionsBySubject.putIfAbsent(prop.subject.record, () => []).add(i);
      }
    } else if (p is ActionDefinitionRecord ||
        p is RuleRecord &&
            !excludedRules.contains(records[i].identity.recordId)) {
      sharedPositions.add(i);
    }
  }
  List<ResourceGap>? resourceGaps;
  try {
    resourceGaps = assessResourceAccounting(
      records,
      frame,
      excludedRules: excludedRules,
    );
  } on InvalidArgumentError {
    resourceGaps = null;
  }
  var pairsRemaining = 1000000;
  final objects = <EffectiveObject>[];
  for (final id in ids) {
    final identity = index.get(id);
    if (identity == null ||
        identity.payload is! EntityRecord &&
            identity.payload is! EntityTypeRecord) {
      continue;
    }
    final chain = index.ancestry(id),
        ancestry = <RecordVersion>[],
        seen = <RecordId>{};
    RecordId? next = switch (identity.payload) {
      EntityRecord(
        classificationResolution: ClassificationResolution.resolved,
        :final classification,
      ) =>
        classification,
      EntityTypeRecord() => id,
      _ => null,
    };
    while (next != null) {
      if (!seen.add(next)) break;
      final r = index.get(next);
      if (r == null ||
          r.identity.universeId != identity.identity.universeId ||
          r.payload is! EntityTypeRecord) {
        break;
      }
      final t = r.payload as EntityTypeRecord;
      ancestry.add(r);
      if (!t.classificationExecutable ||
          t.parentResolution != ParentResolution.resolved) {
        break;
      }
      next = t.parent;
    }
    final definitionIds = ancestry.map((r) => r.identity.recordId).toSet();
    final positions = <int>{
      ...sharedPositions,
      for (final subject in [id, ...definitionIds])
        ...?assertionsBySubject[subject],
    }.toList()..sort();
    final shared = <ObjectEvidence>[],
        instance = <ObjectEvidence>[],
        initial = <ObjectEvidence>[];
    final requirements = <ObjectEvidence>[], rules = <ObjectEvidence>[];
    final dependencies = <RecordId>{},
        conflicts = <ObjectConflict>[],
        unknowns = <String>[];
    if (!chain.complete) unknowns.add('classification_or_ancestry_unresolved');
    if (restricted) {
      unknowns.add('current_permissions_or_perspective_limit_evidence');
    }
    for (final position in positions) {
      final r = records[position], payload = r.payload;
      switch (payload) {
        case AssertionRecord a:
          final p = index.get(a.proposition.record)?.payload;
          if (p is! PropositionRecord) continue;
          final direct =
              a.attributeMode == AttributeMode.instance &&
              p.subject.record == id;
          final inherited =
              a.attributeMode != AttributeMode.instance &&
              definitionIds.contains(p.subject.record);
          if (!(direct || inherited) ||
              predicates.isNotEmpty &&
                  !predicates.contains(p.predicate.record)) {
            continue;
          }
          final checks = _scoped(a.scope, frame, worlds)
            ..addAll([
              ('proposition_context', p.context == frame.context),
              (
                'temporal_applicability',
                eventAppliesIndexed(a.validity, frame.time, index),
              ),
            ]);
          if (inherited) {
            checks.add(('definition_ancestry', chain.complete ? true : null));
            final t = index.get(p.subject.record)?.payload;
            if (t is EntityTypeRecord) {
              checks.add((
                'ancestor_world_applicability',
                worldApplies(t.applicability, worlds),
              ));
            }
          }
          final property = index.get(p.predicate.record)?.payload;
          if (property is PropertyRecord) {
            checks.add((
              'property_subject_applicability',
              index.matches(id, property.subjectTypes, worlds),
            ));
          }
          final extra = <String>[];
          if (resourceGaps == null) {
            extra.add('resource_accounting_unresolved');
          } else {
            for (final gap in resourceGaps.where(
              (g) => g.assertion == r.identity.recordId,
            )) {
              extra.add(
                'resource_arrival_unexplained:${gap.fingerprint.value}',
              );
              unknowns.add('resource_arrival_unexplained');
              dependencies.addAll([
                gap.rule,
                gap.proposition,
                if (gap.acceptance != null) gap.acceptance!,
              ]);
            }
          }
          if (a.precision != Precision.exact || a.alternatives.isNotEmpty) {
            extra.add('assertion_value_or_precision_unresolved');
          }
          final row = _evidence(r, checks, extra: extra);
          if (row.applicability == false) continue;
          dependencies.addAll([
            p.predicate.record,
            a.proposition.record,
            ...p.roles.map((r) => r.participant.record),
          ]);
          switch (a.attributeMode) {
            case AttributeMode.instance:
              instance.add(row);
            case AttributeMode.shared:
              shared.add(row);
            case AttributeMode.initialValue:
              initial.add(row);
          }
        case ActionDefinitionRecord a:
          bool? relevant = a.requirements.isEmpty;
          for (final requirement in a.requirements) {
            final p = index.get(requirement.predicate.record)?.payload;
            final applies = p is PropertyRecord
                ? index.matches(id, p.subjectTypes, worlds)
                : null;
            relevant = relevant == true || applies == true
                ? true
                : relevant == null || applies == null
                ? null
                : false;
          }
          final row = _evidence(
            r,
            _scoped(a.scope, frame, worlds)..addAll([
              ('requirement_subject_applicability', relevant),
              (
                'temporal_applicability',
                eventAppliesIndexed(a.validity, frame.time, index),
              ),
            ]),
          );
          if (row.applicability != false) {
            dependencies.addAll(a.requirements.map((r) => r.predicate.record));
            requirements.add(row);
          }
        case RuleRecord rule:
          final typed =
              rule.knowledgeBoundary != null ||
              rule.channelChronology != null ||
              rule.knowledgePolicy != null ||
              rule.relationCardinality != null;
          final checks = <(String, bool?)>[
            (
              'rule_subject_applicability',
              index.matches(id, rule.subjectTypes, worlds),
            ),
            ('world_applicability', worldApplies(rule.applicability, worlds)),
            (
              'temporal_applicability',
              typed && rule.knowledgeBoundary == null
                  ? true
                  : eventAppliesIndexed(rule.validity, frame.time, index),
            ),
          ];
          if (rule.knowledgeBoundary case final b?) {
            checks.addAll([
              ('knowledge_boundary_context', b.context == frame.context),
              ('knowledge_boundary_holder', b.holder.record == id),
            ]);
            dependencies.addAll([
              b.holder.record,
              b.proposition.record,
              b.context.record,
            ]);
          }
          if (rule.knowledgePolicy case final policy?) {
            checks.add((
              'knowledge_truth_context',
              policy.context == frame.context,
            ));
          }
          if (rule.relationCardinality case final contract?) {
            checks.addAll(_scoped(contract.scope, frame, worlds));
            checks.add((
              'cardinality_validity',
              contract.validity is UnspecifiedValidity
                  ? true
                  : eventAppliesIndexed(contract.validity, frame.time, index),
            ));
          }
          final row = _evidence(r, checks);
          if (row.applicability != false) rules.add(row);
        default:
          break;
      }
    }
    if (instance.isEmpty) unknowns.add('instance_state_not_established');
    for (final predicate in predicates) {
      if (![...instance, ...shared].any((e) {
        final a = e.record.payload as AssertionRecord;
        final p = index.get(a.proposition.record)?.payload;
        return p is PropositionRecord && p.predicate.record == predicate;
      })) {
        unknowns.add('predicate_not_established:${predicate.value}');
      }
    }
    comparisons:
    for (final (isInitial, rows) in [
      (false, [...shared, ...instance]),
      (true, initial),
    ]) {
      for (var i = 0; i < rows.length; i++) {
        final a = rows[i], aa = a.record.payload as AssertionRecord;
        final ap = index.get(aa.proposition.record)?.payload;
        if (ap is! PropositionRecord) continue;
        for (var j = i + 1; j < rows.length; j++) {
          if (pairsRemaining == 0) {
            unknowns.add('conflict_comparison_budget_exhausted');
            break comparisons;
          }
          pairsRemaining--;
          final b = rows[j], ba = b.record.payload as AssertionRecord;
          final bp = index.get(ba.proposition.record)?.payload;
          if (bp is! PropositionRecord) continue;
          final equal =
              ap.value == bp.value ||
              ap.value != null &&
                  bp.value != null &&
                  compareValues(ap.value!, Comparator.eq, bp.value!) == true;
          final overlap = temporalOverlaps(aa.validity, ba.validity);
          final disjoint =
              aa.scope.applicability is WorldsApplicability &&
              ba.scope.applicability is WorldsApplicability &&
              !(aa.scope.applicability as WorldsApplicability).worldIds.any(
                (w) => (ba.scope.applicability as WorldsApplicability).worldIds
                    .contains(w),
              );
          final prop = index.get(ap.predicate.record)?.payload;
          if (ap.predicate == bp.predicate &&
              _sameRoles(ap, bp) &&
              aa.scope.realm == ba.scope.realm &&
              !disjoint &&
              overlap != false &&
              (equal && aa.polarity != ba.polarity ||
                  !equal &&
                      aa.polarity == Polarity.support &&
                      ba.polarity == Polarity.support &&
                      prop is PropertyRecord &&
                      (prop.multiplicity == Multiplicity.single ||
                          prop.exclusive))) {
            conflicts.add(
              ObjectConflict(
                applicability: _combine(
                  _combine(_combine(a.applicability, b.applicability), overlap),
                  aa.precision == Precision.exact &&
                          ba.precision == Precision.exact &&
                          aa.alternatives.isEmpty &&
                          ba.alternatives.isEmpty
                      ? true
                      : null,
                ),
                predicate: ap.predicate.record,
                assertions: [
                  a.record.recordVersionId,
                  b.record.recordVersionId,
                ],
                initialValues: isInitial,
              ),
            );
          }
        }
      }
    }
    if ([
      ...shared,
      ...instance,
      ...initial,
      ...requirements,
      ...rules,
    ].any((r) => r.applicability == null)) {
      unknowns.add('candidate_applicability_unresolved');
    }
    if (conflicts.any((c) => c.applicability == null)) {
      unknowns.add('conflict_applicability_unresolved');
    }
    if ([...shared, ...instance, ...initial].any(
      (r) => r.unknowns.contains('assertion_value_or_precision_unresolved'),
    )) {
      unknowns.add('assertion_value_or_precision_unresolved');
    }
    objects.add(
      EffectiveObject(
        identity: identity,
        contextualNames:
            frame.perspective is AuthorPerspective &&
                identity.payload is EntityRecord
            ? (identity.payload as EntityRecord).names.map(
                (n) => ContextualNameEvidence(
                  name: n,
                  applicability: eventApplies(n.validity, frame.time, records),
                ),
              )
            : [],
        ancestry: ancestry,
        ancestryComplete: chain.complete,
        sharedAttributes: shared,
        instanceFacts: instance,
        initialValueCandidates: initial,
        initializationReceipts: [],
        initializationHistoryCoverage: Coverage.partial,
        behavioralRequirements: requirements,
        rules: rules,
        dependencies: records.where(
          (r) => dependencies.contains(r.identity.recordId),
        ),
        conflicts: conflicts,
        unknowns: unknowns,
        coverage: restricted
            ? Coverage.restricted
            : unknowns.isNotEmpty
            ? Coverage.partial
            : Coverage.complete,
      ),
    );
  }
  return List.unmodifiable(objects);
}
