import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'property_forms.dart';
import 'wire.dart';
import 'rule_knowledge_forms.dart';
import 'rule_constraint_forms.dart';

final class UnfinishedRuleForm {
  UnfinishedRuleForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    Iterable<PropertyLabelInput> labels = const [],
    this.kind = '',
    this.commitPolicy = '',
    this.scope = const ScopeInput(),
    Iterable<String> subjectTypes = const [],
    Iterable<String> targetPredicates = const [],
    Iterable<String> capabilities = const [],
    ExpressionInput? expression,
    this.executable,
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    this.revisionTarget,
    this.expectedRecordVersion,
    this.knowledge,
    this.constraints,
    this.evidence,
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       subjectTypes = List.unmodifiable(subjectTypes),
       targetPredicates = List.unmodifiable(targetPredicates),
       capabilities = List.unmodifiable(capabilities),
       expression = expression ?? ExpressionInput(),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, namespace, key, kind, commitPolicy, rationale;
  final List<PropertyLabelInput> labels;
  final ScopeInput scope;
  final List<String> subjectTypes, targetPredicates, capabilities;
  final ExpressionInput expression;
  final bool? executable;
  final TemporalValidityInput validity;
  final RuleRecord? original;
  final RuleKnowledgeInput? knowledge;
  final RuleConstraintInput? constraints;
  final RuleEvidenceInput? evidence;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('commit_policy', CanonicalString(commitPolicy)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
    MapEntry('scope', scope.toWire()),
    MapEntry(
      'subject_types',
      CanonicalArray(subjectTypes.map(CanonicalString.new)),
    ),
    MapEntry(
      'target_predicates',
      CanonicalArray(targetPredicates.map(CanonicalString.new)),
    ),
    MapEntry(
      'capabilities',
      CanonicalArray(capabilities.map(CanonicalString.new)),
    ),
    MapEntry('expression', expression.toWire()),
    if (executable != null) MapEntry('executable', CanonicalBool(executable!)),
    MapEntry('validity', validity.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
    if (knowledge != null) MapEntry('knowledge', knowledge!.toWire()),
    if (constraints != null) MapEntry('constraints', constraints!.toWire()),
    if (evidence != null) MapEntry('evidence', evidence!.toWire()),
    if (revisionTarget != null)
      MapEntry('revision_target', revisionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedRuleForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'kind',
      'commit_policy',
      'rationale',
      'labels',
      'scope',
      'subject_types',
      'target_predicates',
      'capabilities',
      'expression',
      'executable',
      'validity',
      'original',
      'knowledge',
      'constraints',
      'evidence',
      'draft_version',
      'revision_target',
      'expected_record_version',
    });
    return UnfinishedRuleForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      kind: f.string('kind'),
      commitPolicy: f.string('commit_policy'),
      rationale: f.string('rationale'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      scope: ScopeInput.fromWire(f.require('scope')),
      subjectTypes: f.array('subject_types').map(wireString),
      targetPredicates: f.array('target_predicates').map(wireString),
      capabilities: f.array('capabilities').map(wireString),
      expression: ExpressionInput.fromWire(f.require('expression')),
      executable: f.values.containsKey('executable')
          ? f.boolean('executable')
          : null,
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      original: f.optional('original', RuleRecord.fromWire),
      knowledge: f.optional('knowledge', RuleKnowledgeInput.fromWire),
      constraints: f.optional('constraints', RuleConstraintInput.fromWire),
      evidence: f.optional('evidence', RuleEvidenceInput.fromWire),
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => _texts(toWire());
}

/// Incomplete device-private input. Exact references are parsed on submission.
final class RuleEvidenceCategoryInput {
  const RuleEvidenceCategoryInput({
    this.universe = '',
    this.record = '',
    this.version = '',
  });
  final String universe, record, version;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('universe', CanonicalString(universe)),
    MapEntry('record', CanonicalString(record)),
    MapEntry('version', CanonicalString(version)),
  ]);
  factory RuleEvidenceCategoryInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'universe', 'record', 'version'});
    return RuleEvidenceCategoryInput(
      universe: f.string('universe'),
      record: f.string('record'),
      version: f.string('version'),
    );
  }
}

final class RuleEvidenceInput {
  RuleEvidenceInput({
    this.enabled = false,
    Iterable<RuleEvidenceCategoryInput> categories = const [],
    Iterable<String> reviewMethods = const [],
  }) : categories = List.unmodifiable(categories),
       reviewMethods = List.unmodifiable(reviewMethods);
  final bool enabled;
  final List<RuleEvidenceCategoryInput> categories;
  final List<String> reviewMethods;
  RuleEvidenceInput copyWith({
    bool? enabled,
    Iterable<RuleEvidenceCategoryInput>? categories,
    Iterable<String>? reviewMethods,
  }) => RuleEvidenceInput(
    enabled: enabled ?? this.enabled,
    categories: categories ?? this.categories,
    reviewMethods: reviewMethods ?? this.reviewMethods,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('enabled', CanonicalBool(enabled)),
    MapEntry('categories', CanonicalArray(categories.map((c) => c.toWire()))),
    MapEntry(
      'review_methods',
      CanonicalArray(reviewMethods.map(CanonicalString.new)),
    ),
  ]);
  factory RuleEvidenceInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'enabled', 'categories', 'review_methods'});
    return RuleEvidenceInput(
      enabled: f.boolean('enabled'),
      categories: f.array('categories').map(RuleEvidenceCategoryInput.fromWire),
      reviewMethods: f.array('review_methods').map(wireString),
    );
  }
}

Iterable<String> _texts(CanonicalValue value) sync* {
  switch (value) {
    case CanonicalString(:final value):
      yield value;
    case CanonicalArray(:final items):
      for (final item in items) {
        yield* _texts(item);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        yield* _texts(field.value);
      }
    default:
      break;
  }
}

final class SavedRuleForm {
  SavedRuleForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedRuleForm form;
}
