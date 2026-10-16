import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'cardinality_checks.dart';
import 'writing_binding.dart';
import 'writing_candidate.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
(RecordVersion, RelationRecord) resolveWritingRelation(
  List<RecordVersion> rows,
  String name,
) {
  final found = [
    for (final row in rows)
      if (row.payload case final RelationRecord relation)
        if (relation.key == name || relation.labels.values.contains(name))
          (row, relation),
  ];
  if (found.length != 1) {
    throw FormatException("Which exact authored relationship is '$name'?");
  }
  return found.single;
}

bool supportedWritingRelationLimit(RuleRecord rule) =>
    rule.relationCardinality != null &&
    rule.executable &&
    rule.kind == RuleKind.physicalConstraint &&
    rule.commitPolicy == CommitPolicy.alwaysBlock &&
    rule.applicability is UniverseApplicability &&
    rule.validity is UnspecifiedValidity &&
    rule.subjectTypes.isEmpty &&
    rule.targetPredicates.isEmpty &&
    rule.expression == const LiteralExpr(true) &&
    rule.capabilities.length == 1 &&
    rule.capabilities.single == relationCardinalityCapability &&
    rule.knowledgeBoundary == null &&
    rule.knowledgePolicy == null &&
    rule.channelChronology == null;

(RecordVersion, AssertionRecord, PropositionRecord, RelationRecord) _authored(
  List<RecordVersion> rows,
  String handle,
  Frame frame,
) {
  const message =
      'Retrieve the current pinned authored relationship handle before editing it.';
  for (final record in rows) {
    if (record.recordVersionId.value != handle) continue;
    if (record.payload is! AssertionRecord) break;
    final assertion = record.payload as AssertionRecord;
    if (assertion.establishedBy != null ||
        assertion.attributeMode != AttributeMode.instance ||
        assertion.scope.context != frame.context) {
      break;
    }
    for (final p in rows) {
      if (p.identity.recordId != assertion.proposition.record ||
          p.payload is! PropositionRecord) {
        continue;
      }
      final proposition = p.payload as PropositionRecord;
      for (final d in rows) {
        if (d.identity.recordId == proposition.predicate.record &&
            d.payload is RelationRecord) {
          return (record, assertion, proposition, d.payload as RelationRecord);
        }
      }
    }
    break;
  }
  throw const FormatException(message);
}

CardinalityKey _group(WritingRelationGrouping grouping) =>
    CardinalityKey.fromWire(grouping.toWire());
void _checkRoles(
  RelationRecord relation,
  CardinalityKey grouping,
  String counted,
) {
  if (!relation.roles.any((r) => r.name == counted) ||
      grouping is RoleCardinalityKey &&
          !relation.roles.any((r) => r.name == grouping.role)) {
    throw const FormatException(
      'Grouping and counted roles must be actual declared relationship roles.',
    );
  }
}

Iterable<MapEntry<String, List<String>>> _entries(
  Map<String, List<String>> values,
) => CanonicalObject(
  values.keys.map((key) => MapEntry(key, const CanonicalNull())),
).fields.map((field) => MapEntry(field.key, values[field.key]!));

/// Compile the full relationship writer segment. All rows are admitted; the
/// pinned base owns edit handles. Candidate refreshes reuse canonical lowering.
/// Returned operations exclude [priorOperations], which remain the caller's.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> excluded,
  List<String> clarifications,
})
compileWritingRelations({
  required UniverseId universe,
  required Frame frame,
  required List<RecordVersion> base,
  required CheckChangesRequest input,
  List<DomainOperation> priorOperations = const [],
  Set<WorldId>? worldScope,
}) {
  if (input.relationDefinitions.isEmpty &&
      input.relationLimits.isEmpty &&
      input.relationCorrections.isEmpty &&
      input.relationLimitCorrections.isEmpty &&
      input.relationshipCorrections.isEmpty &&
      input.relationshipEndings.isEmpty &&
      input.relationships.isEmpty) {
    return (
      operations: [],
      additions: [],
      unchanged: [],
      excluded: [],
      clarifications: [],
    );
  }
  final operations = [...priorOperations],
      additions = <String>[],
      unchanged = <String>[],
      excluded = <String>[],
      clarifications = <String>[];
  var rows = compileWritingCandidate(
    universe: universe,
    revision: frame.revision,
    base: base,
    operations: operations,
  );
  final revised = <RecordId>{}, edited = <RecordId>{};
  RecordRef ref(RecordId id) => RecordRef(universe: universe, record: id);
  RecordId object(String name) =>
      resolveWritingObject(rows, name, frame) ??
      (throw FormatException("Which exact authored participant is '$name'?"));
  Scope scope(String text) => Scope(
    context: frame.context,
    applicability: bindWritingApplicability(rows, text, worldScope: worldScope),
  );
  void attempt(
    List<DomainOperation> Function() build,
    String addition, {
    String? noChange,
  }) {
    final List<DomainOperation> added;
    try {
      added = build();
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
      return;
    } on InvalidArgumentError catch (error) {
      clarifications.add(error.message);
      return;
    } on NotFoundOrNotAccessibleError catch (error) {
      clarifications.add(error.message);
      return;
    }
    if (added.isEmpty) {
      if (noChange != null) unchanged.add(noChange);
      return;
    }
    operations.addAll(added);
    // Canonical compilation failures propagate, as in the owning workflow.
    rows = compileWritingCandidate(
      universe: universe,
      revision: frame.revision,
      base: base,
      operations: operations,
    );
    additions.add(addition);
  }

  for (final declaration in input.relationDefinitions) {
    attempt(
      () {
        if (!declaration.introduce ||
            !_nonWhitespace.hasMatch(declaration.name) ||
            rows.any(
              (r) =>
                  r.payload is RelationRecord &&
                  ((r.payload as RelationRecord).key == declaration.name ||
                      (r.payload as RelationRecord).labels.values.contains(
                        declaration.name,
                      )),
            )) {
          throw const FormatException(
            'Explicitly introduce a unique relationship name; existing definitions are not replaced.',
          );
        }
        final names = <String>{};
        if (declaration.roles.isEmpty ||
            declaration.roles.any(
              (role) =>
                  !_nonWhitespace.hasMatch(role.name) || !names.add(role.name),
            )) {
          throw const FormatException(
            'Declare distinct nonempty relationship role names.',
          );
        }
        return [
          DefineRelationOperation(
            clientRef: RecordId.generate().value,
            record: RelationRecord(
              namespace: 'authoring',
              key: declaration.name,
              labels: {},
              roles: [
                for (final role in declaration.roles)
                  RoleDefinition(
                    name: role.name,
                    participantTypes: [],
                    multiplicity: role.multiple
                        ? Multiplicity.multiple
                        : Multiplicity.single,
                    ordered: false,
                  ),
              ],
            ),
          ),
        ];
      },
      'Author relationship declaration: ${declaration.name}; private contract review required.',
    );
  }
  for (final limit in input.relationLimits) {
    attempt(
      () {
        if (!_nonWhitespace.hasMatch(limit.name) ||
            rows.any(
              (r) =>
                  r.payload is RuleRecord &&
                  (r.payload as RuleRecord).key == limit.name,
            )) {
          throw const FormatException(
            'Choose a unique explicit limit name; existing policies are not replaced.',
          );
        }
        final (record, definition) = resolveWritingRelation(
          rows,
          limit.relation,
        );
        final grouping = _group(limit.grouping);
        _checkRoles(definition, grouping, limit.countedRole);
        final validity = bindWritingLifetime(
          bindWritingTime(frame, rows, limit.atTick),
          limit.lifetime,
        );
        return [
          DefineRuleOperation(
            clientRef: RecordId.generate().value,
            record: RuleRecord(
              namespace: 'authoring',
              key: limit.name,
              labels: {},
              kind: RuleKind.physicalConstraint,
              commitPolicy: CommitPolicy.alwaysBlock,
              applicability: const UniverseApplicability(),
              targetPredicates: [],
              expression: const LiteralExpr(true),
              capabilities: [relationCardinalityCapability],
              executable: true,
              validity: const UnspecifiedValidity(),
              relationCardinality: RelationCardinality(
                relation: ref(record.identity.recordId),
                grouping: grouping,
                countedRole: limit.countedRole,
                maximum: limit.maximum,
                scope: scope(limit.scope),
                validity: validity,
              ),
            ),
          ),
        ];
      },
      'Author relationship limit: ${limit.name}; maximum ${limit.maximum}; private contract review required.',
    );
  }
  for (final patch in input.relationCorrections) {
    attempt(
      () {
        if (!_nonWhitespace.hasMatch(patch.reason) || patch.roles.isEmpty) {
          throw const FormatException(
            "Specify changed role fields and the author's reason; omitted fields stay unchanged.",
          );
        }
        final (original, definition) = resolveWritingRelation(base, patch.name);
        final roles = [...definition.roles], seen = <String>{};
        for (final changed in patch.roles) {
          if (!seen.add(changed.name) ||
              changed.multiple == null &&
                  changed.ordered == null &&
                  changed.participantTypes == null) {
            throw const FormatException(
              'Specify each changed declared role once with explicit changed fields.',
            );
          }
          final index = roles.indexWhere((r) => r.name == changed.name);
          if (index < 0) {
            throw FormatException(
              "'${changed.name}' is not a declared role of this relationship.",
            );
          }
          final old = roles[index];
          final types = <RecordId>[];
          if (changed.participantTypes != null) {
            for (final name in changed.participantTypes!) {
              final matches = rows
                  .where(
                    (r) =>
                        r.payload is EntityTypeRecord &&
                        ((r.payload as EntityTypeRecord).key == name ||
                            (r.payload as EntityTypeRecord).name == name ||
                            (r.payload as EntityTypeRecord).labels.values
                                .contains(name)),
                  )
                  .toList();
              if (matches.length != 1) {
                throw FormatException(
                  "Which exact participant type is '$name' ?",
                );
              }
              types.add(matches.single.identity.recordId);
            }
          }
          roles[index] = RoleDefinition(
            name: old.name,
            participantTypes: changed.participantTypes == null
                ? old.participantTypes
                : types,
            multiplicity: changed.multiple == null
                ? old.multiplicity
                : changed.multiple!
                ? Multiplicity.multiple
                : Multiplicity.single,
            ordered: changed.ordered ?? old.ordered,
          );
        }
        if (!revised.add(original.identity.recordId)) {
          throw const FormatException(
            'Revise each relationship contract only once per delta.',
          );
        }
        return [
          ReviseDefinitionOperation(
            record: ref(original.identity.recordId),
            expectedVersion: original.recordVersionId,
            replacement: RelationRecord(
              namespace: definition.namespace,
              key: definition.key,
              labels: definition.labels,
              roles: roles,
            ),
          ),
        ];
      },
      'Relationship contract correction: ${patch.name} — ${patch.reason}; private contract review required.',
    );
  }
  for (final patch in input.relationLimitCorrections) {
    attempt(
      () {
        if (!_nonWhitespace.hasMatch(patch.reason) ||
            patch.maximum == null &&
                patch.grouping == null &&
                patch.countedRole == null &&
                patch.scope == null &&
                patch.atTick == null &&
                patch.lifetime == null) {
          throw const FormatException(
            "Specify changed limit fields and the author's reason.",
          );
        }
        final matches = [
          for (final row in base)
            if (row.payload case final RuleRecord rule)
              if (rule.key == patch.name ||
                  rule.labels.values.contains(patch.name))
                (row, rule),
        ];
        if (matches.length != 1) {
          throw FormatException(
            "Which exact authored relationship limit is '${patch.name}' ?",
          );
        }
        final (original, rule) = matches.single;
        if (!supportedWritingRelationLimit(rule)) {
          throw const FormatException(
            'This relationship limit requires advanced contract review; its metadata will not be discarded.',
          );
        }
        final old = rule.relationCardinality!;
        final definitions = rows
            .where(
              (r) =>
                  r.identity.recordId == old.relation.record &&
                  r.payload is RelationRecord,
            )
            .toList();
        if (definitions.isEmpty) {
          throw const FormatException(
            'Retrieve the relationship definition before changing its limit.',
          );
        }
        final grouping = patch.grouping == null
                ? old.grouping
                : _group(patch.grouping!),
            counted = patch.countedRole ?? old.countedRole;
        _checkRoles(
          definitions.first.payload as RelationRecord,
          grouping,
          counted,
        );
        if ((patch.atTick != null) != (patch.lifetime != null)) {
          throw const FormatException(
            'Time correction requires both explicit tick and lifetime; omission preserves existing validity.',
          );
        }
        final limit = RelationCardinality(
          relation: old.relation,
          grouping: grouping,
          countedRole: counted,
          maximum: patch.maximum ?? old.maximum,
          scope: Scope(
            context: old.scope.context,
            realm: old.scope.realm,
            applicability: patch.scope == null
                ? old.scope.applicability
                : bindWritingApplicability(
                    rows,
                    patch.scope!,
                    worldScope: worldScope,
                  ),
          ),
          validity: patch.atTick == null
              ? old.validity
              : bindWritingLifetime(
                  bindWritingTime(frame, rows, patch.atTick),
                  patch.lifetime!,
                ),
        );
        final replacement = RuleRecord.fromWire(
          CanonicalObject([
            for (final entry in rule.toWire().fields)
              if (entry.key != 'relationCardinality') entry,
            MapEntry('relationCardinality', limit.toWire()),
          ]),
        );
        if (!revised.add(original.identity.recordId)) {
          throw const FormatException(
            'Revise each relationship contract only once per delta.',
          );
        }
        return [
          ReviseDefinitionOperation(
            record: ref(original.identity.recordId),
            expectedVersion: original.recordVersionId,
            replacement: replacement,
          ),
        ];
      },
      'Relationship limit correction: ${patch.name} — ${patch.reason}; private contract review required.',
    );
  }
  for (final patch in input.relationshipCorrections) {
    attempt(
      () {
        if (!_nonWhitespace.hasMatch(patch.reason)) {
          throw const FormatException(
            "Explain the author's relationship correction.",
          );
        }
        final (record, assertion, proposition, definition) = _authored(
          base,
          patch.relationshipHandle,
          frame,
        );
        if (!edited.add(record.identity.recordId)) {
          throw const FormatException(
            'Submit only one correction or ending for each relationship in a delta.',
          );
        }
        final roles = [...proposition.roles];
        for (final entry in _entries(patch.participants)) {
          final defs = definition.roles
              .where((r) => r.name == entry.key)
              .toList();
          if (defs.isEmpty) {
            throw FormatException(
              "'${entry.key}' is not a declared role of this relationship.",
            );
          }
          if (defs.first.multiplicity == Multiplicity.single &&
              entry.value.length > 1) {
            throw FormatException(
              "Role '${entry.key}' permits only one participant per occurrence.",
            );
          }
          roles.removeWhere((r) => r.role == entry.key);
          for (final name in entry.value) {
            roles.add(PropositionRole(entry.key, ref(object(name))));
          }
        }
        final replacement = PropositionRecord(
          predicate: proposition.predicate,
          subject: proposition.subject,
          context: proposition.context,
          quantification: proposition.quantification,
          value: proposition.value,
          roles: roles,
        );
        if (replacement == proposition) return [];
        final id = RecordId.generate();
        final next = AssertionRecord.fromWire(
          CanonicalObject([
            for (final entry in assertion.toWire().fields)
              if (entry.key != 'proposition' && entry.key != 'basis') entry,
            MapEntry('proposition', ref(id).toCanonical()),
            MapEntry('basis', const ImportedClaimBasis().toWire()),
          ]),
        );
        return [
          DefinePropositionOperation(clientRef: id.value, record: replacement),
          SupersedeAssertionOperation(
            record: ref(record.identity.recordId),
            expectedVersion: record.recordVersionId,
            replacement: next,
            rationale: patch.reason,
          ),
        ];
      },
      'Authored relationship participant correction: ${patch.reason}',
      noChange: 'Relationship participants unchanged.',
    );
  }
  for (final ending in input.relationshipEndings) {
    attempt(() {
      if (!_nonWhitespace.hasMatch(ending.reason)) {
        throw const FormatException(
          "Explain the author's relationship ending.",
        );
      }
      final (record, assertion, _, _) = _authored(
        base,
        ending.relationshipHandle,
        frame,
      );
      if (!edited.add(record.identity.recordId)) {
        throw const FormatException(
          'Submit only one correction or ending for each relationship in a delta.',
        );
      }
      if (assertion.validity is! CalendarIntervalValidity) {
        throw const FormatException(
          'Ending requires an authored calendar interval; instant or unspecified relationships require explicit historical correction.',
        );
      }
      return [
        EndAssertionAtOperation(
          record: ref(record.identity.recordId),
          expectedVersion: record.recordVersionId,
          at: ExactTime(
            (assertion.validity as CalendarIntervalValidity).calendar,
            ending.endTick,
          ),
          basis: const ImportedClaimBasis(),
        ),
      ];
    }, 'Authored relationship ends at ${ending.endTick}: ${ending.reason}');
  }
  for (final relationship in input.relationships) {
    if (!{
      'objective',
      'dialogue',
      'belief',
      'plan',
      'hypothetical',
      'metaphor',
    }.contains(relationship.statement)) {
      clarifications.add('Unknown relationship statement intent.');
      continue;
    }
    if (relationship.statement != 'objective') {
      excluded.add(
        '${relationship.subject}: ${relationship.relation} (${relationship.statement})',
      );
      continue;
    }
    attempt(
      () {
        final (record, definition) = resolveWritingRelation(
          rows,
          relationship.relation,
        );
        final roles = <PropositionRole>[];
        for (final entry in _entries(relationship.participants)) {
          final defs = definition.roles
              .where((r) => r.name == entry.key)
              .toList();
          if (defs.isEmpty) {
            throw FormatException(
              "'${entry.key}' is not a declared role of '${relationship.relation}'.",
            );
          }
          if (defs.first.multiplicity == Multiplicity.single &&
              entry.value.length > 1) {
            throw FormatException(
              "Role '${entry.key}' permits only one participant per occurrence.",
            );
          }
          for (final name in entry.value) {
            roles.add(PropositionRole(entry.key, ref(object(name))));
          }
        }
        final proposition = PropositionRecord(
          predicate: ref(record.identity.recordId),
          subject: ref(object(relationship.subject)),
          roles: roles,
          quantification: Quantification.particular,
          context: frame.context,
        );
        final validity = bindWritingLifetime(
              bindWritingTime(frame, rows, relationship.atTick),
              relationship.lifetime,
            ),
            cell = scope(relationship.scope);
        final polarity = relationship.negated
            ? Polarity.refutation
            : Polarity.support;
        for (final row in rows) {
          if (row.payload != proposition) continue;
          if (rows.any(
            (r) =>
                r.payload is AssertionRecord &&
                (r.payload as AssertionRecord).proposition.record ==
                    row.identity.recordId &&
                (r.payload as AssertionRecord).polarity == polarity &&
                (r.payload as AssertionRecord).scope == cell &&
                (r.payload as AssertionRecord).validity == validity &&
                (r.payload as AssertionRecord).attributeMode ==
                    AttributeMode.instance &&
                (r.payload as AssertionRecord).precision == Precision.exact &&
                (r.payload as AssertionRecord).alternatives.isEmpty,
          )) {
            return [];
          }
        }
        final id = RecordId.generate();
        return [
          RecordRelationOperation(
            clientRef: id.value,
            proposition: proposition,
            assertion: AssertionRecord(
              attributeMode: AttributeMode.instance,
              proposition: ref(id),
              polarity: polarity,
              scope: cell,
              validity: validity,
              persistence: PersistenceSemantics.explicitInterval,
              precision: Precision.exact,
              basis: const ImportedClaimBasis(),
            ),
          ),
        ];
      },
      '${relationship.subject}: relationship ${relationship.relation}',
      noChange:
          '${relationship.subject}: relationship ${relationship.relation}',
    );
  }
  return (
    operations: List.unmodifiable(operations.skip(priorOperations.length)),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    excluded: List.unmodifiable(excluded),
    clarifications: List.unmodifiable(clarifications),
  );
}
