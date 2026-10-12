import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'writing_powers_test.dart' as powers;
import 'rule_checks_test.dart' as facts;

List<RecordVersion> base() => [
  ...powers.rows(),
  f.row(
    6,
    powers.property('stock', const SimpleValueShape(SimpleShapeKind.integer)),
  ),
  f.row(
    99,
    RepresentedContextRecord(
      universe: f.u,
      kind: const ObjectiveContext(),
      labels: {},
    ),
  ),
];
WritingClaim claim() => WritingClaim(
  subject: 'Wand',
  property: 'able',
  value: const FactBooleanValue(true),
);
WritingKnowledgeBoundary boundary({
  String scope = 'universe',
  String? tick = '10',
  FactLifetime lifetime = const FactUntilLifetime(endTick: '20'),
}) => WritingKnowledgeBoundary(
  name: 'sealed',
  holder: 'Mara',
  claim: claim(),
  scope: scope,
  atTick: tick,
  lifetime: lifetime,
);

void main() {
  test('knowledge boundaries policies and constraints compile through canonical operations', () {
    final rows = base();
    final result = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: rows,
      corrections: [],
      boundaries: [boundary()],
      policies: [
        const WritingKnowledgeModePolicy(
          name: 'learning',
          mode: KnowledgeMode.authorEstablished,
        ),
        const WritingChannelPolicy(
          name: 'mail',
          channel: 'post',
          forwardOnly: true,
          minimumDelay: '9007199254740993',
          maximumDelay: '9007199254740994',
        ),
      ],
      constraints: [
        WritingResourceAccountingConstraint(
          name: 'accounting',
          property: 'stock',
          scope: 'universe',
        ),
        WritingNoOpposingEvidenceConstraint(
          name: 'consistent',
          object: 'Wand',
          property: 'able',
          scope: 'universe',
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    expect(result.operations, hasLength(6));
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: result.operations,
    );
    final rules = candidate
        .where((r) => r.payload is RuleRecord)
        .map((r) => r.payload as RuleRecord)
        .toList();
    expect(rules, hasLength(5));
    final sealed = rules.singleWhere((r) => r.key == 'sealed');
    expect(supportedWritingBoundary(sealed), isTrue);
    validateKnowledgeBoundaryRule(sealed, candidate);
    final acquisition = rules.singleWhere((r) => r.key == 'learning');
    expect(supportedWritingKnowledgePolicy(acquisition), isTrue);
    expect(acquisition.knowledgePolicy!.context, powers.frame.context);
    final mail = rules.singleWhere((r) => r.key == 'mail');
    validateChannelChronologyRule(mail);
    expect(mail.channelChronology!.minimumDelay, '9007199254740993');
    expect(
      supportedWritingPolicy(rules.singleWhere((r) => r.key == 'accounting')),
      isTrue,
    );
    expect(
      supportedWritingPolicy(rules.singleWhere((r) => r.key == 'consistent')),
      isTrue,
    );
    // Reuse the pinned exact proposition instead of inventing another identity.
    final reused = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: candidate.where((r) => r.payload is! RuleRecord).toList(),
      corrections: [],
      boundaries: [boundary()],
      policies: [],
      constraints: [],
    );
    expect(reused.operations, hasLength(1));
    expect(
      (reused.operations.single as DefineRuleOperation)
          .record
          .knowledgeBoundary!
          .proposition,
      sealed.knowledgeBoundary!.proposition,
    );
  });

  test('invalid declarations clarify atomically and do not create partial boundary claims', () {
    final result = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: base(),
      corrections: [],
      boundaries: [
        boundary(scope: 'unspecified'),
        boundary(tick: null),
        boundary(lifetime: const FactUntilChangedLifetime()),
      ],
      policies: [
        const WritingChannelPolicy(
          name: 'bad',
          channel: 'post',
          forwardOnly: true,
          minimumDelay: '20',
          maximumDelay: '10',
        ),
      ],
      constraints: [
        WritingResourceAccountingConstraint(
          name: 'wrongShape',
          property: 'able',
          scope: 'universe',
        ),
        WritingNoOpposingEvidenceConstraint(
          name: 'missing',
          object: 'Hidden',
          property: 'able',
          scope: 'universe',
        ),
      ],
    );
    expect(result.operations, isEmpty);
    expect(result.clarifications, hasLength(6));
    final repeated = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: base(),
      corrections: [],
      boundaries: [],
      policies: [],
      constraints: [
        WritingResourceAccountingConstraint(
          name: 'same',
          property: 'stock',
          scope: 'universe',
        ),
        WritingResourceAccountingConstraint(
          name: 'same',
          property: 'stock',
          scope: 'universe',
        ),
      ],
    );
    expect(repeated.operations, hasLength(1));
    expect(repeated.clarifications, hasLength(1));
  });

  test('knowledge and channel corrections preserve metadata and pin exact original versions', () {
    final rows = base();
    final created = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: rows,
      corrections: [],
      boundaries: [],
      constraints: [],
      policies: [
        const WritingKnowledgeModePolicy(
          name: 'learning',
          mode: KnowledgeMode.authorEstablished,
        ),
        const WritingChannelPolicy(
          name: 'mail',
          channel: 'post',
          forwardOnly: true,
          minimumDelay: '3',
          maximumDelay: '10',
        ),
      ],
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: rows,
      operations: created.operations,
    );
    RecordVersion rule(String key) => candidate.singleWhere(
      (r) => r.payload is RuleRecord && (r.payload as RuleRecord).key == key,
    );
    final learning = rule('learning'), mail = rule('mail');
    final changed = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: candidate,
      boundaries: [],
      policies: [],
      constraints: [],
      corrections: [
        WritingPolicyCorrection(
          policyHandle: learning.recordVersionId.value,
          reason: 'Switch mode',
          mode: KnowledgeMode.justified,
        ),
        WritingPolicyCorrection(
          policyHandle: mail.recordVersionId.value,
          reason: 'Clear floor',
          clearMinimumDelay: true,
        ),
      ],
    );
    expect(changed.clarifications, isEmpty);
    final knowledge = changed.operations.first as ReviseDefinitionOperation;
    expect(knowledge.expectedVersion, learning.recordVersionId);
    expect(
      (knowledge.replacement as RuleRecord).knowledgePolicy!.mode,
      KnowledgeMode.justified,
    );
    expect(
      permittedWritingPolicyCorrection(
        learning.payload as RuleRecord,
        knowledge.replacement as RuleRecord,
      ),
      isTrue,
    );
    final channel =
        (changed.operations.last as ReviseDefinitionOperation).replacement
            as RuleRecord;
    expect(channel.channelChronology!.minimumDelay, isNull);
    expect(channel.channelChronology!.maximumDelay, '10');
    expect(channel.channelChronology!.channel, 'post');
    expect(channel.channelChronology!.forwardOnly, isTrue);
    final revised = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: candidate,
      operations: changed.operations,
    );
    expect(
      () => compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: revised,
        operations: changed.operations,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    final altered = f.patch<RuleRecord>(channel, {
      'key': CanonicalString('different'),
    });
    expect(
      permittedWritingPolicyCorrection(mail.payload as RuleRecord, altered),
      isFalse,
    );
    final denied = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: candidate,
      boundaries: [],
      policies: [],
      constraints: [],
      corrections: [
        WritingPolicyCorrection(
          policyHandle: mail.recordVersionId.value,
          reason: 'Conflict',
          minimumDelay: '5',
          clearMinimumDelay: true,
        ),
        WritingPolicyCorrection(
          policyHandle: mail.recordVersionId.value,
          reason: 'Duplicate',
          forwardOnly: false,
        ),
        WritingPolicyCorrection(
          policyHandle: learning.recordVersionId.value,
          reason: 'Scope change',
          scope: 'unspecified',
        ),
      ],
    );
    expect(denied.operations, isEmpty);
    expect(denied.clarifications, hasLength(3));
  });

  test('constraint corrections permit only explicit scope and paired validity changes', () {
    final created = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: base(),
      corrections: [],
      boundaries: [],
      policies: [],
      constraints: [
        WritingResourceAccountingConstraint(
          name: 'accounting',
          property: 'stock',
          scope: 'universe',
        ),
      ],
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base(),
      operations: created.operations,
    );
    final original = candidate.singleWhere((r) => r.payload is RuleRecord);
    final result = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: candidate,
      boundaries: [],
      policies: [],
      constraints: [],
      corrections: [
        WritingPolicyCorrection(
          policyHandle: original.recordVersionId.value,
          reason: 'Limit period',
          atTick: '12',
          lifetime: const FactUntilLifetime(endTick: '20'),
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final replacement =
        (result.operations.single as ReviseDefinitionOperation).replacement
            as RuleRecord;
    expect(
      replacement.validity,
      CalendarIntervalValidity(
        facts.calendar,
        const ExactBound('12'),
        const ExactBound('20'),
      ),
    );
    expect(
      replacement.targetPredicates,
      (original.payload as RuleRecord).targetPredicates,
    );
    expect(
      replacement.capabilities,
      (original.payload as RuleRecord).capabilities,
    );
    for (final patch in [
      WritingPolicyCorrection(
        policyHandle: original.recordVersionId.value,
        reason: 'No change',
      ),
      WritingPolicyCorrection(
        policyHandle: original.recordVersionId.value,
        reason: 'Partial time',
        atTick: '12',
      ),
      WritingPolicyCorrection(
        policyHandle: original.recordVersionId.value,
        reason: 'Wrong mode',
        mode: KnowledgeMode.justified,
      ),
      WritingPolicyCorrection(
        policyHandle: original.identity.recordId.value,
        reason: 'Wrong handle',
        scope: 'unspecified',
      ),
    ]) {
      final denied = compileWritingPolicies(
        universe: f.u,
        frame: powers.frame,
        rows: candidate,
        boundaries: [],
        policies: [],
        constraints: [],
        corrections: [patch],
      );
      expect(denied.operations, isEmpty);
      expect(denied.clarifications, hasLength(1));
    }
  });

  test('policy handles cannot cross represented contexts or reveal unsupported rules', () {
    final foreign = f.row(
      20,
      RuleRecord(
        namespace: 'test',
        key: 'private',
        labels: {},
        kind: RuleKind.physicalConstraint,
        commitPolicy: CommitPolicy.alwaysBlock,
        applicability: const UniverseApplicability(),
        targetPredicates: [],
        expression: const LiteralExpr(true),
        capabilities: [knowledgeAcquisitionCapability],
        executable: true,
        validity: const UnspecifiedValidity(),
        knowledgePolicy: KnowledgePolicy(
          context: f.ref(98),
          mode: KnowledgeMode.authorEstablished,
        ),
      ),
    );
    final denied = compileWritingPolicies(
      universe: f.u,
      frame: powers.frame,
      rows: [...base(), foreign],
      boundaries: [],
      policies: [],
      constraints: [],
      corrections: [
        WritingPolicyCorrection(
          policyHandle: foreign.recordVersionId.value,
          reason: 'Different context',
          mode: KnowledgeMode.justified,
        ),
      ],
    );
    expect(denied.operations, isEmpty);
    expect(
      denied.clarifications.single,
      contains('current author-visible policy handle'),
    );
    final unsupported = f.patch<RuleRecord>(foreign.payload as RuleRecord, {
      'capabilities': CanonicalArray([CanonicalString('unknown')]),
    });
    expect(supportedWritingKnowledgePolicy(unsupported), isFalse);
  });
}
