part of 'records.dart';

enum CommitPolicy {
  alwaysBlock('always_block'),
  blockUnlessException('block_unless_exception'),
  recordFinding('record_finding'),
  advisory('advisory'),
  scopeEnforced('scope_enforced'),
  reportUnsupported('report_unsupported');

  const CommitPolicy(this.wireName);
  final String wireName;
  static CommitPolicy fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown commit policy'),
  );
}

enum RuleKind {
  structuralInvariant('structural_invariant', CommitPolicy.alwaysBlock),
  physicalConstraint('physical_constraint', CommitPolicy.blockUnlessException),
  operationalRequirement('operational_requirement', CommitPolicy.recordFinding),
  law('law', CommitPolicy.recordFinding),
  behavioralTendency('behavioral_tendency', CommitPolicy.advisory),
  authorialRestriction('authorial_restriction', CommitPolicy.scopeEnforced),
  descriptive('descriptive', CommitPolicy.reportUnsupported);

  const RuleKind(this.wireName, this.defaultCommitPolicy);
  final String wireName;
  final CommitPolicy defaultCommitPolicy;
  static RuleKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown rule kind'),
  );
}

/// Inclusive authored delay bounds in the same clock; no conversion is inferred.
final class ChannelChronology {
  const ChannelChronology({
    required this.channel,
    required this.forwardOnly,
    this.minimumDelay,
    this.maximumDelay,
  });
  final String channel;
  final bool forwardOnly;
  final String? minimumDelay, maximumDelay;
  factory ChannelChronology.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'channel', 'forwardOnly', 'minimumDelay', 'maximumDelay'});
    return ChannelChronology(
      channel: f.string('channel'),
      forwardOnly: f.boolean('forwardOnly'),
      minimumDelay: f.optionalString('minimumDelay'),
      maximumDelay: f.optionalString('maximumDelay'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('channel', CanonicalString(channel)),
    MapEntry('forwardOnly', CanonicalBool(forwardOnly)),
    if (minimumDelay != null)
      MapEntry('minimumDelay', CanonicalString(minimumDelay!)),
    if (maximumDelay != null)
      MapEntry('maximumDelay', CanonicalString(maximumDelay!)),
  ]);
}

sealed class CardinalityKey {
  const CardinalityKey();
  CanonicalObject toWire();
  static CardinalityKey fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'subject':
        f.allow({'kind'});
        return const SubjectCardinalityKey();
      case 'role':
        f.allow({'kind', 'role'});
        return RoleCardinalityKey(f.string('role'));
      default:
        throw const FormatException('Unknown cardinality grouping');
    }
  }
}

final class SubjectCardinalityKey extends CardinalityKey {
  const SubjectCardinalityKey();
  @override
  CanonicalObject toWire() => tagged('subject', []);
}

final class RoleCardinalityKey extends CardinalityKey {
  const RoleCardinalityKey(this.role);
  final String role;
  @override
  CanonicalObject toWire() =>
      tagged('role', [MapEntry('role', CanonicalString(role))]);
}

final class RelationCardinality {
  RelationCardinality({
    required this.relation,
    required this.grouping,
    required this.countedRole,
    required int maximum,
    required this.scope,
    required this.validity,
  }) : maximum = _checkedU32(maximum);
  final RecordRef relation;
  final CardinalityKey grouping;
  final String countedRole;
  final int maximum;
  final Scope scope;
  final Validity validity;
  factory RelationCardinality.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'relation',
        'grouping',
        'countedRole',
        'maximum',
        'scope',
        'validity',
      });
    return RelationCardinality(
      relation: RecordRef.fromCanonical(f.require('relation')),
      grouping: CardinalityKey.fromWire(f.require('grouping')),
      countedRole: f.string('countedRole'),
      maximum: _u32(f, 'maximum'),
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('relation', relation.toCanonical()),
    MapEntry('grouping', grouping.toWire()),
    MapEntry('countedRole', CanonicalString(countedRole)),
    MapEntry('maximum', CanonicalNumber(maximum.toString())),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
  ]);
}

/// Absence of knowledge is not refutation of the proposition itself.
final class KnowledgeBoundary {
  const KnowledgeBoundary({
    required this.holder,
    required this.proposition,
    required this.context,
  });
  final RecordRef holder, proposition, context;
  factory KnowledgeBoundary.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'holder', 'proposition', 'context'});
    return KnowledgeBoundary(
      holder: RecordRef.fromCanonical(f.require('holder')),
      proposition: RecordRef.fromCanonical(f.require('proposition')),
      context: RecordRef.fromCanonical(f.require('context')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('holder', holder.toCanonical()),
    MapEntry('proposition', proposition.toCanonical()),
    MapEntry('context', context.toCanonical()),
  ]);
}

/// Permitted attribution methods selected by an authored evidence policy.
enum EvidenceReviewMethod {
  humanReview('human_review'),
  externalModelReview('external_model_review');

  const EvidenceReviewMethod(this.wireName);
  final String wireName;
  static EvidenceReviewMethod fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown evidence review method'),
  );
}

/// Exact published source-category packs; an empty review list imposes no
/// interpretation-review duty. This declaration alone does not establish truth.
final class RequiredEvidence {
  RequiredEvidence({
    required Iterable<VersionRef> sourceCategories,
    Iterable<EvidenceReviewMethod> reviewMethods = const [],
  }) : sourceCategories = List.unmodifiable(sourceCategories),
       reviewMethods = List.unmodifiable(reviewMethods);
  final List<VersionRef> sourceCategories;
  final List<EvidenceReviewMethod> reviewMethods;
  factory RequiredEvidence.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'sourceCategories', 'reviewMethods'});
    return RequiredEvidence(
      sourceCategories: f
          .array('sourceCategories')
          .map(VersionRef.fromCanonical),
      reviewMethods: _array(
        f,
        'reviewMethods',
      ).map((v) => EvidenceReviewMethod.fromName(_string(v))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'sourceCategories',
      CanonicalArray(sourceCategories.map((v) => v.toCanonical())),
    ),
    if (reviewMethods.isNotEmpty)
      MapEntry(
        'reviewMethods',
        CanonicalArray(reviewMethods.map((v) => CanonicalString(v.wireName))),
      ),
  ]);
}

final class RuleRecord extends RecordPayload {
  RuleRecord({
    this.requiredEvidence,
    this.knowledgeBoundary,
    this.relationCardinality,
    this.knowledgePolicy,
    this.channelChronology,
    required this.namespace,
    required this.key,
    required Map<String, String> labels,
    required this.kind,
    required this.commitPolicy,
    required this.applicability,
    Iterable<RecordId> subjectTypes = const [],
    required Iterable<String> targetPredicates,
    required this.expression,
    required Iterable<String> capabilities,
    required this.executable,
    required this.validity,
  }) : labels = Map.unmodifiable(labels),
       subjectTypes = List.unmodifiable(subjectTypes),
       targetPredicates = List.unmodifiable(targetPredicates),
       capabilities = List.unmodifiable(capabilities);
  final RequiredEvidence? requiredEvidence;
  final KnowledgeBoundary? knowledgeBoundary;
  final RelationCardinality? relationCardinality;
  final KnowledgePolicy? knowledgePolicy;
  final ChannelChronology? channelChronology;
  final String namespace, key;
  final Map<String, String> labels;
  final RuleKind kind;
  final CommitPolicy commitPolicy;
  final Applicability applicability;
  final List<RecordId> subjectTypes;
  final List<String> targetPredicates, capabilities;
  final Expr expression;
  final bool executable;
  final Validity validity;
  factory RuleRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.rule, {
      'requiredEvidence',
      'knowledgeBoundary',
      'relationCardinality',
      'knowledgePolicy',
      'channelChronology',
      'namespace',
      'key',
      'labels',
      'kind',
      'commitPolicy',
      'applicability',
      'subjectTypes',
      'targetPredicates',
      'expression',
      'capabilities',
      'executable',
      'validity',
    });
    return RuleRecord(
      requiredEvidence: _optionalObject(
        f,
        'requiredEvidence',
        RequiredEvidence.fromWire,
      ),
      knowledgeBoundary: _optionalObject(
        f,
        'knowledgeBoundary',
        KnowledgeBoundary.fromWire,
      ),
      relationCardinality: _optionalObject(
        f,
        'relationCardinality',
        RelationCardinality.fromWire,
      ),
      knowledgePolicy: _optionalObject(
        f,
        'knowledgePolicy',
        KnowledgePolicy.fromWire,
      ),
      channelChronology: _optionalObject(
        f,
        'channelChronology',
        ChannelChronology.fromWire,
      ),
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: _strings(f, 'labels'),
      kind: RuleKind.fromName(f.string('kind')),
      commitPolicy: CommitPolicy.fromName(f.string('commitPolicy')),
      applicability: Applicability.fromWire(f.require('applicability')),
      subjectTypes: _ids(_array(f, 'subjectTypes')),
      targetPredicates: f.array('targetPredicates').map(_string),
      expression: Expr.fromWire(f.require('expression')),
      capabilities: f.array('capabilities').map(_string),
      executable: f.boolean('executable'),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.rule;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    if (requiredEvidence != null)
      MapEntry('requiredEvidence', requiredEvidence!.toWire()),
    if (knowledgeBoundary != null)
      MapEntry('knowledgeBoundary', knowledgeBoundary!.toWire()),
    if (relationCardinality != null)
      MapEntry('relationCardinality', relationCardinality!.toWire()),
    if (knowledgePolicy != null)
      MapEntry('knowledgePolicy', knowledgePolicy!.toWire()),
    if (channelChronology != null)
      MapEntry('channelChronology', channelChronology!.toWire()),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', _stringMap(labels)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('commitPolicy', CanonicalString(commitPolicy.wireName)),
    MapEntry('applicability', applicability.toWire()),
    if (subjectTypes.isNotEmpty)
      MapEntry('subjectTypes', _idArray(subjectTypes)),
    MapEntry(
      'targetPredicates',
      CanonicalArray(targetPredicates.map(CanonicalString.new)),
    ),
    MapEntry('expression', expression.toWire()),
    MapEntry(
      'capabilities',
      CanonicalArray(capabilities.map(CanonicalString.new)),
    ),
    MapEntry('executable', CanonicalBool(executable)),
    MapEntry('validity', validity.toWire()),
  ]);
}

enum BoundaryMode {
  fixed('fixed'),
  openWithConstraints('open_with_constraints'),
  proposalRequired('proposal_required'),
  authorReserved('author_reserved'),
  intentionallyUnresolved('intentionally_unresolved'),
  prohibited('prohibited');

  const BoundaryMode(this.wireName);
  final String wireName;
  static BoundaryMode fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown boundary mode'),
  );
}

sealed class BoundaryArea {
  const BoundaryArea();
  CanonicalObject toWire();
  static BoundaryArea fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'record':
        f.allow({'kind', 'record', 'universe'});
        return RecordBoundaryArea(
          RecordRef.fromCanonical(
            CanonicalObject(f.values.entries.where((e) => e.key != 'kind')),
          ),
        );
      case 'predicate':
        f.allow({'kind', 'predicate', 'subject'});
        return PredicateBoundaryArea(
          f.string('predicate'),
          _optionalRef(f, 'subject'),
        );
      case 'category':
        f.allow({'kind', 'entity_type'});
        return CategoryBoundaryArea(RecordId.parse(f.string('entity_type')));
      default:
        throw const FormatException('Unknown boundary area');
    }
  }
}

final class RecordBoundaryArea extends BoundaryArea {
  const RecordBoundaryArea(this.record);
  final RecordRef record;
  @override
  CanonicalObject toWire() => tagged('record', record.toCanonical().fields);
}

final class PredicateBoundaryArea extends BoundaryArea {
  const PredicateBoundaryArea(this.predicate, this.subject);
  final String predicate;
  final RecordRef? subject;
  @override
  CanonicalObject toWire() => tagged('predicate', [
    MapEntry('predicate', CanonicalString(predicate)),
    MapEntry('subject', _nullableRef(subject)),
  ]);
}

final class CategoryBoundaryArea extends BoundaryArea {
  const CategoryBoundaryArea(this.entityType);
  final RecordId entityType;
  @override
  CanonicalObject toWire() => tagged('category', [
    MapEntry('entity_type', CanonicalString(entityType.value)),
  ]);
}

final class BoundaryRecord extends RecordPayload {
  BoundaryRecord({
    required this.key,
    required this.area,
    required this.mode,
    Iterable<Expr> constraints = const [],
    required this.validity,
    required this.scope,
  }) : constraints = List.unmodifiable(constraints);
  final String key;
  final BoundaryArea area;
  final BoundaryMode mode;
  final List<Expr> constraints;
  final Validity validity;
  final Scope scope;
  factory BoundaryRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.boundary, {
      'key',
      'area',
      'mode',
      'constraints',
      'validity',
      'scope',
    });
    return BoundaryRecord(
      key: f.string('key'),
      area: BoundaryArea.fromWire(f.require('area')),
      mode: BoundaryMode.fromName(f.string('mode')),
      constraints: _array(f, 'constraints').map(Expr.fromWire),
      validity: Validity.fromWire(f.require('validity')),
      scope: Scope.fromWire(f.require('scope')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.boundary;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('key', CanonicalString(key)),
    MapEntry('area', area.toWire()),
    MapEntry('mode', CanonicalString(mode.wireName)),
    if (constraints.isNotEmpty)
      MapEntry(
        'constraints',
        CanonicalArray(constraints.map((e) => e.toWire())),
      ),
    MapEntry('validity', validity.toWire()),
    MapEntry('scope', scope.toWire()),
  ]);
}

final class ExceptionRecord extends RecordPayload {
  const ExceptionRecord({
    required this.rule,
    this.ruleVersion,
    required this.scope,
    required this.validity,
    required this.authorizingDecision,
    required this.rationale,
  });
  final RecordRef rule, authorizingDecision;
  final RecordVersionId? ruleVersion;
  final Scope scope;
  final Validity validity;
  final String rationale;
  factory ExceptionRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.exception, {
      'rule',
      'ruleVersion',
      'scope',
      'validity',
      'authorizingDecision',
      'rationale',
    });
    final pin = f.optionalString('ruleVersion');
    return ExceptionRecord(
      rule: RecordRef.fromCanonical(f.require('rule')),
      ruleVersion: pin == null ? null : RecordVersionId.parse(pin),
      scope: Scope.fromWire(f.require('scope')),
      validity: Validity.fromWire(f.require('validity')),
      authorizingDecision: RecordRef.fromCanonical(
        f.require('authorizingDecision'),
      ),
      rationale: f.string('rationale'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.exception;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('rule', rule.toCanonical()),
    if (ruleVersion != null)
      MapEntry('ruleVersion', CanonicalString(ruleVersion!.value)),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('authorizingDecision', authorizingDecision.toCanonical()),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

/// A fingerprint is an opaque finding identity, not an application authority.
final class FindingFingerprint {
  const FindingFingerprint(this.value);
  final String value;
  @override
  bool operator ==(Object other) =>
      other is FindingFingerprint && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

enum IssueDecisionMode {
  accept,
  defer,
  resolve;

  static IssueDecisionMode fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown issue decision mode'),
  );
}

final class IssueDecisionRecord extends RecordPayload {
  IssueDecisionRecord({
    required Iterable<FindingFingerprint> fingerprints,
    required this.mode,
    required this.scope,
    required this.rationale,
    required this.principal,
  }) : fingerprints = List.unmodifiable(fingerprints);
  final List<FindingFingerprint> fingerprints;
  final IssueDecisionMode mode;
  final String scope, rationale;
  final PrincipalId principal;
  factory IssueDecisionRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.issueDecision, {
      'fingerprints',
      'mode',
      'scope',
      'rationale',
      'principal',
    });
    return IssueDecisionRecord(
      fingerprints: f
          .array('fingerprints')
          .map((v) => FindingFingerprint(_string(v))),
      mode: IssueDecisionMode.fromName(f.string('mode')),
      scope: f.string('scope'),
      rationale: f.string('rationale'),
      principal: PrincipalId.parse(f.string('principal')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.issueDecision;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry(
      'fingerprints',
      CanonicalArray(fingerprints.map((f) => CanonicalString(f.value))),
    ),
    MapEntry('mode', CanonicalString(mode.name)),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('principal', CanonicalString(principal.value)),
  ]);
}
