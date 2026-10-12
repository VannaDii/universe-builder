import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'communication_checks.dart';
import 'knowledge_checks.dart';
import 'knowledge_boundaries.dart';
import 'writing_binding.dart';
import 'writing_contract_projection.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
RuleRecord _replace(RuleRecord rule, Map<String, CanonicalValue> edits) =>
    RuleRecord.fromWire(
      CanonicalObject(
        {...Map.fromEntries(rule.toWire().fields), ...edits}.entries,
      ),
    );

bool supportedWritingBoundary(RuleRecord rule) =>
    rule.knowledgeBoundary != null &&
    rule.capabilities.length == 1 &&
    rule.capabilities.single == knowledgeBoundaryCapability &&
    rule.kind == RuleKind.physicalConstraint &&
    rule.commitPolicy == CommitPolicy.alwaysBlock &&
    rule.executable &&
    rule.knowledgePolicy == null &&
    rule.channelChronology == null &&
    rule.relationCardinality == null &&
    rule.expression == const LiteralExpr(true) &&
    rule.targetPredicates.isEmpty &&
    rule.subjectTypes.isEmpty &&
    (rule.applicability is UniverseApplicability ||
        rule.applicability is WorldsApplicability) &&
    rule.validity is CalendarIntervalValidity;

bool supportedWritingKnowledgePolicy(RuleRecord rule) {
  if ((rule.knowledgePolicy == null && rule.channelChronology == null) ||
      rule.relationCardinality != null ||
      rule.knowledgeBoundary != null) {
    return false;
  }
  try {
    validateKnowledgeRule(rule);
    validateChannelChronologyRule(rule);
    return true;
  } on InvalidArgumentError {
    return false;
  }
}

bool permittedWritingPolicyCorrection(RuleRecord old, RuleRecord replacement) {
  RuleRecord permitted;
  if (supportedWritingKnowledgePolicy(old)) {
    permitted = _replace(old, {
      if (old.knowledgePolicy != null && replacement.knowledgePolicy != null)
        'knowledgePolicy': KnowledgePolicy(
          context: old.knowledgePolicy!.context,
          mode: replacement.knowledgePolicy!.mode,
        ).toWire(),
      if (old.channelChronology != null &&
          replacement.channelChronology != null)
        'channelChronology': ChannelChronology(
          channel: old.channelChronology!.channel,
          forwardOnly: replacement.channelChronology!.forwardOnly,
          minimumDelay: replacement.channelChronology!.minimumDelay,
          maximumDelay: replacement.channelChronology!.maximumDelay,
        ).toWire(),
    });
  } else if (supportedWritingPolicy(old) || supportedWritingBoundary(old)) {
    permitted = _replace(old, {
      'applicability': replacement.applicability.toWire(),
      'validity': replacement.validity.toWire(),
    });
  } else {
    return false;
  }
  return permitted == replacement &&
      (supportedWritingPolicy(replacement) ||
          supportedWritingKnowledgePolicy(replacement) ||
          supportedWritingBoundary(replacement));
}

RuleRecord _correct(
  RuleRecord old,
  WritingPolicyCorrection patch,
  Frame frame,
  List<RecordVersion> rows,
  Set<WorldId>? worldScope,
) {
  if (!_nonWhitespace.hasMatch(patch.reason)) {
    throw const FormatException('Explain the explicit policy correction');
  }
  final edits = <String, CanonicalValue>{};
  if (patch.mode != null) {
    final policy = old.knowledgePolicy;
    if (policy == null) {
      throw const FormatException(
        'Only a knowledge policy accepts a mode correction',
      );
    }
    edits['knowledgePolicy'] = KnowledgePolicy(
      context: policy.context,
      mode: patch.mode!,
    ).toWire();
  }
  if (patch.forwardOnly != null ||
      patch.minimumDelay != null ||
      patch.maximumDelay != null ||
      patch.clearMinimumDelay ||
      patch.clearMaximumDelay) {
    final channel = old.channelChronology;
    if (channel == null) {
      throw const FormatException(
        'Only a channel policy accepts ordering/delay corrections',
      );
    }
    if (patch.clearMinimumDelay && patch.minimumDelay != null ||
        patch.clearMaximumDelay && patch.maximumDelay != null) {
      throw const FormatException(
        'Choose a replacement delay or explicitly clear it, not both',
      );
    }
    edits['channelChronology'] = ChannelChronology(
      channel: channel.channel,
      forwardOnly: patch.forwardOnly ?? channel.forwardOnly,
      minimumDelay: patch.clearMinimumDelay
          ? null
          : patch.minimumDelay ?? channel.minimumDelay,
      maximumDelay: patch.clearMaximumDelay
          ? null
          : patch.maximumDelay ?? channel.maximumDelay,
    ).toWire();
  }
  if (patch.scope != null || patch.atTick != null || patch.lifetime != null) {
    if (!supportedWritingPolicy(old) && !supportedWritingBoundary(old)) {
      throw const FormatException(
        'Knowledge and channel policies retain universe-wide scope and unspecified validity',
      );
    }
    if (patch.scope != null) {
      edits['applicability'] = bindWritingApplicability(
        rows,
        patch.scope!,
        worldScope: worldScope,
      ).toWire();
    }
    if (patch.atTick != null && patch.lifetime != null) {
      edits['validity'] = bindWritingLifetime(
        bindWritingTime(frame, rows, patch.atTick),
        patch.lifetime!,
      ).toWire();
    } else if (patch.atTick != null || patch.lifetime != null) {
      throw const FormatException(
        'A policy time correction needs both an explicit tick and lifetime',
      );
    }
  }
  final replacement = _replace(old, edits);
  if (replacement == old) {
    throw const FormatException(
      'Specify a changed policy setting; omitted settings stay unchanged',
    );
  }
  if (!permittedWritingPolicyCorrection(old, replacement)) {
    throw const FormatException(
      'This policy correction changes unsupported policy semantics',
    );
  }
  return replacement;
}

RuleRecord _rule(
  String name,
  String capability, {
  KnowledgePolicy? knowledge,
  ChannelChronology? channel,
  KnowledgeBoundary? boundary,
  Applicability applicability = const UniverseApplicability(),
  Validity validity = const UnspecifiedValidity(),
  Expr expression = const LiteralExpr(true),
  List<String> targets = const [],
  CommitPolicy commitPolicy = CommitPolicy.alwaysBlock,
}) => RuleRecord(
  namespace: 'authoring',
  key: name,
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: commitPolicy,
  applicability: applicability,
  validity: validity,
  targetPredicates: targets,
  expression: expression,
  capabilities: [capability],
  executable: true,
  knowledgePolicy: knowledge,
  channelChronology: channel,
  knowledgeBoundary: boundary,
);

/// Compile visible pinned policy edits and declarations without altering canon.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingPolicies({
  required UniverseId universe,
  required Frame frame,
  required List<RecordVersion> rows,
  required List<WritingPolicyCorrection> corrections,
  required List<WritingKnowledgeBoundary> boundaries,
  required List<WritingKnowledgePolicy> policies,
  required List<WritingConstraint> constraints,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      clarifications = <String>[];
  final edited = <String>{}, names = <String>{};
  void attempt(List<DomainOperation> Function() build, String addition) {
    try {
      operations.addAll(build());
      additions.add(addition);
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on InvalidArgumentError catch (error) {
      clarifications.add(error.message);
    } on NotFoundOrNotAccessibleError catch (error) {
      clarifications.add(error.message);
    }
  }

  DefineRuleOperation define(RuleRecord rule) =>
      DefineRuleOperation(clientRef: RecordId.generate().value, record: rule);
  bool exists(String name, {bool labels = true}) => rows.any(
    (row) =>
        row.payload is RuleRecord &&
        ((row.payload as RuleRecord).key == name ||
            labels && (row.payload as RuleRecord).labels.values.contains(name)),
  );
  for (final patch in corrections) {
    if (!edited.add(patch.policyHandle)) {
      clarifications.add('Correct each policy once in a delta');
      continue;
    }
    attempt(() {
      final found = rows
          .where(
            (row) =>
                row.recordVersionId.value == patch.policyHandle &&
                row.payload is RuleRecord &&
                (supportedWritingPolicy(row.payload as RuleRecord) ||
                    supportedWritingKnowledgePolicy(
                      row.payload as RuleRecord,
                    ) ||
                    supportedWritingBoundary(row.payload as RuleRecord)) &&
                ((row.payload as RuleRecord).knowledgePolicy == null ||
                    (row.payload as RuleRecord).knowledgePolicy!.context ==
                        frame.context) &&
                ((row.payload as RuleRecord).knowledgeBoundary == null ||
                    (row.payload as RuleRecord).knowledgeBoundary!.context ==
                        frame.context),
          )
          .toList();
      if (found.isEmpty) {
        throw const FormatException(
          'Retrieve the current author-visible policy handle before correcting it',
        );
      }
      final original = found.first;
      return [
        ReviseDefinitionOperation(
          record: RecordRef(
            universe: universe,
            record: original.identity.recordId,
          ),
          expectedVersion: original.recordVersionId,
          replacement: _correct(
            original.payload as RuleRecord,
            patch,
            frame,
            rows,
            worldScope,
          ),
        ),
      ];
    }, 'Policy correction: ${patch.reason}; private contract review required');
  }
  for (final boundary in boundaries) {
    attempt(
      () {
        if (!_nonWhitespace.hasMatch(boundary.name) ||
            exists(boundary.name, labels: false)) {
          throw const FormatException(
            'Use a uniquely named knowledge boundary; retrieve a current policy handle to revise it',
          );
        }
        final holder =
            resolveWritingObject(rows, boundary.holder, frame) ??
            (throw FormatException(
              "Which exact holder is '${boundary.holder}' ?",
            ));
        final scope = bindWritingApplicability(
          rows,
          boundary.scope,
          worldScope: worldScope,
        );
        if ((scope is! UniverseApplicability &&
                scope is! WorldsApplicability) ||
            boundary.lifetime is! FactUntilLifetime ||
            boundary.atTick == null) {
          throw const FormatException(
            'A knowledge boundary needs explicit world scope, start and exclusive end on the selected calendar',
          );
        }
        final time = bindWritingTime(frame, rows, boundary.atTick);
        final period = bindWritingLifetime(time, boundary.lifetime);
        final proposition = bindWritingClaim(
          universe,
          rows,
          frame,
          boundary.claim,
        );
        final added = <DomainOperation>[];
        final reference = bindWritingProposition(
          added,
          universe,
          proposition,
          rows,
        );
        added.add(
          define(
            _rule(
              boundary.name,
              knowledgeBoundaryCapability,
              applicability: scope,
              validity: period,
              boundary: KnowledgeBoundary(
                holder: RecordRef(universe: universe, record: holder),
                proposition: reference,
                context: frame.context,
              ),
            ),
          ),
        );
        return added;
      },
      'Explicit knowledge boundary: ${boundary.name}; private contract review required',
    );
  }
  for (final policy in policies) {
    attempt(
      () {
        final name = switch (policy) {
          WritingKnowledgeModePolicy(:final name) => name,
          WritingChannelPolicy(:final name) => name,
        };
        if (!_nonWhitespace.hasMatch(name) || exists(name)) {
          throw const FormatException(
            'Explicitly declare a uniquely named knowledge/communication policy; revisions require advanced review.',
          );
        }
        final rule = switch (policy) {
          WritingKnowledgeModePolicy(:final mode) => _rule(
            name,
            knowledgeAcquisitionCapability,
            knowledge: KnowledgePolicy(context: frame.context, mode: mode),
          ),
          WritingChannelPolicy(
            :final channel,
            :final forwardOnly,
            :final minimumDelay,
            :final maximumDelay,
          ) =>
            _rule(
              name,
              communicationChronologyCapability,
              channel: ChannelChronology(
                channel: channel,
                forwardOnly: forwardOnly,
                minimumDelay: minimumDelay,
                maximumDelay: maximumDelay,
              ),
            ),
        };
        validateKnowledgeRule(rule);
        validateChannelChronologyRule(rule);
        return [define(rule)];
      },
      'Explicit knowledge/communication policy; separate author contract review required.',
    );
  }
  for (final constraint in constraints) {
    final (name, key, scope) = switch (constraint) {
      WritingResourceAccountingConstraint(
        :final name,
        :final property,
        :final scope,
      ) =>
        (name, property, scope),
      WritingNoOpposingEvidenceConstraint(
        :final name,
        :final property,
        :final scope,
      ) =>
        (name, property, scope),
    };
    attempt(() {
      if (!_nonWhitespace.hasMatch(name) || !names.add(name) || exists(name)) {
        throw const FormatException(
          'Introduce a uniquely named constraint; existing policies require explicit revision.',
        );
      }
      final (_, property) = resolveWritingProperty(rows, key);
      final predicate = '${property.namespace}:${property.key}';
      final Expr expression;
      final String capability;
      final CommitPolicy commitPolicy;
      if (constraint is WritingResourceAccountingConstraint) {
        if (!(property.value is QuantityShape ||
                property.value is SimpleValueShape &&
                    ((property.value as SimpleValueShape).kind ==
                            SimpleShapeKind.integer ||
                        (property.value as SimpleValueShape).kind ==
                            SimpleShapeKind.decimal)) ||
            property.multiplicity != Multiplicity.single) {
          throw const FormatException(
            'Resource accounting requires an explicitly authored single integer/decimal/quantity property.',
          );
        }
        expression = const LiteralExpr(true);
        capability = 'resources.accounting.v1';
        commitPolicy = CommitPolicy.blockUnlessException;
      } else {
        final object =
            (constraint as WritingNoOpposingEvidenceConstraint).object;
        final id =
            resolveWritingObject(rows, object, frame) ??
            (throw FormatException(
              "Which exact object is '$object' for the constraint?",
            ));
        expression = NoOpposingEvidenceExpr(
          RecordOperand(RecordRef(universe: universe, record: id)),
          predicate,
          RecordOperand(frame.context),
        );
        capability = 'opposing_evidence.v1';
        commitPolicy = CommitPolicy.alwaysBlock;
      }
      return [
        define(
          _rule(
            name,
            capability,
            targets: [predicate],
            expression: expression,
            commitPolicy: commitPolicy,
            applicability: bindWritingApplicability(
              rows,
              scope,
              worldScope: worldScope,
            ),
          ),
        ),
      ];
    }, 'New authored constraint: $name; use separate author contract review.');
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
